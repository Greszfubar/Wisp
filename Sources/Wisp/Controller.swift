import AppKit
import AVFoundation

/// Owns the push-to-talk lifecycle: hold key -> capture -> transcribe -> polish -> insert.
///
/// Mode is decided by context, not by a classifier: if the frontmost app has text
/// selected when you start speaking, your words are treated as an instruction to
/// rewrite that selection. Otherwise they are dictation.
@MainActor
final class Controller: ObservableObject {

    @Published private(set) var status: String = "Not set up yet"
    @Published private(set) var isReady = false
    @Published private(set) var isPreparing = false

    private let hotkey: HotkeyMonitor
    private let audio = AudioCapture()
    private let transcriber = Transcriber()
    private let polisher = Polisher()
    private let hud = HUD()

    private var partialTask: Task<Void, Never>?
    private var startedAt: Date?
    private var pendingSelection: String?
    private var targetApp: String?
    private var isCapturing = false

    /// Below this we assume a mis-press rather than speech, and stay silent.
    private let minimumUtterance: TimeInterval = 0.35

    init() {
        hotkey = HotkeyMonitor(trigger: Settings.shared.trigger)
        hotkey.onPress = { [weak self] in self?.beginCapture() }
        hotkey.onRelease = { [weak self] in self?.endCapture() }
    }

    // MARK: Startup

    /// Safe to call repeatedly — onboarding calls it again as each grant lands.
    func start() async {
        guard !isPreparing else { return }

        guard Permissions.hasAccessibility else {
            status = "Needs Accessibility permission"
            return
        }
        guard MicPermission.isAuthorized else {
            status = "Needs microphone access"
            return
        }
        guard hotkey.start() else {
            status = "Couldn't register the hotkey"
            return
        }

        isPreparing = true
        status = "Downloading speech model…"
        defer { isPreparing = false }

        do {
            try await transcriber.prepare()
            isReady = true
            status = "Hold \(Settings.shared.trigger.label) to talk"
        } catch {
            status = error.localizedDescription
        }
        NotificationCenter.default.post(name: .wispStateChanged, object: nil)
    }

    /// True when both grants exist, so the app can skip the welcome screen.
    static var isConfigured: Bool {
        Permissions.hasAccessibility && MicPermission.isAuthorized
    }

    func applyTriggerChange() {
        hotkey.setTrigger(Settings.shared.trigger)
        hotkey.start()
        if isReady { status = "Hold \(Settings.shared.trigger.label) to talk" }
    }

    func shutdown() {
        hotkey.stop()
        audio.stop()
    }

    // MARK: Capture

    private func beginCapture() {
        guard isReady, !isCapturing else { return }
        isCapturing = true

        // Read the selection now — the user may click elsewhere while speaking.
        pendingSelection = SelectionReader.selectedText()
        targetApp = SelectionReader.frontmostAppName
        startedAt = Date()

        let editing = pendingSelection != nil
        hud.show(.listening(level: 0, partial: "", editing: editing))
        if Settings.shared.playSounds { Sound.start() }

        audio.onLevel = { [weak self] level in
            guard let self, self.isCapturing else { return }
            if case .listening(_, let partial, let editing) = self.hudState {
                self.hudState = .listening(level: level, partial: partial, editing: editing)
                self.hud.update(self.hudState)
            }
        }
        audio.onBuffer = { [weak self] buffer in
            guard let self else { return }
            Task { await self.transcriber.feed(buffer) }
        }

        hudState = .listening(level: 0, partial: "", editing: editing)

        Task {
            do {
                try await transcriber.beginUtterance()
                try audio.start()
                streamPartials(editing: editing)
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    private var hudState: HUDState = .idle

    /// Show words in the HUD as they are recognised, so holding the key feels alive.
    private func streamPartials(editing: Bool) {
        partialTask?.cancel()
        partialTask = Task { [weak self] in
            guard let self, let stream = await self.transcriber.updates() else { return }
            for await update in stream {
                if Task.isCancelled { return }
                await MainActor.run {
                    guard self.isCapturing else { return }
                    var level: Float = 0
                    if case .listening(let l, _, _) = self.hudState { level = l }
                    self.hudState = .listening(level: level, partial: update.text, editing: editing)
                    self.hud.update(self.hudState)
                }
            }
        }
    }

    private func endCapture() {
        guard isCapturing else { return }
        isCapturing = false
        audio.stop()
        partialTask?.cancel()

        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        let selection = pendingSelection
        let app = targetApp
        pendingSelection = nil

        guard elapsed >= minimumUtterance else {
            Task { await transcriber.abort() }
            hud.hide()
            return
        }

        let editing = selection != nil
        hudState = .thinking(editing: editing)
        hud.update(hudState)

        Task {
            let raw = await transcriber.endUtterance()
            guard !raw.isEmpty else {
                hud.flash(.failed("Didn't catch that"))
                if Settings.shared.playSounds { Sound.fail() }
                return
            }
            await finish(raw: raw, selection: selection, app: app, elapsed: elapsed)
        }
    }

    private func finish(raw: String, selection: String?, app: String?, elapsed: TimeInterval) async {
        let settings = Settings.shared
        let terms = settings.terms

        if let selection {
            if let rewritten = await polisher.edit(selection: selection, instruction: raw, terms: terms) {
                TextInjector.replaceSelection(with: rewritten)
                record(rewritten, app: app, wasEdit: true, elapsed: elapsed)
                hud.flash(.done(rewritten))
                if settings.playSounds { Sound.done() }
                return
            }
            // The edit didn't take — fall through and dictate instead of doing nothing.
        }

        let text = await polisher.polish(raw, style: settings.style, terms: terms, appName: app)
        guard !text.isEmpty else {
            hud.flash(.failed("Nothing to insert"))
            return
        }
        TextInjector.insert(text)
        record(text, app: app, wasEdit: false, elapsed: elapsed)
        hud.flash(.done(text))
        if settings.playSounds { Sound.done() }
    }

    private func record(_ text: String, app: String?, wasEdit: Bool, elapsed: TimeInterval) {
        guard Settings.shared.keepHistory else { return }
        History.shared.add(Dictation(
            id: UUID(), date: Date(), text: text,
            appName: app, wasEdit: wasEdit, duration: elapsed
        ))
    }

    /// Drives the capsule through its states with no audio, so the overlay can be
    /// inspected without granting permissions or saying anything.
    func previewCapsule() {
        guard !isCapturing else { return }
        var level: Float = 0.3
        let words = ["I think we", "I think we should ship", "I think we should ship the beta on Friday"]
        var step = 0

        hud.show(.listening(level: level, partial: "", editing: false))

        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            MainActor.assumeIsolated {
                step += 1
                level = Float.random(in: 0.25...1.0)
                switch step {
                case 1...16:
                    let partial = step < 5 ? "" : words[min((step - 5) / 4, words.count - 1)]
                    self.hud.update(.listening(level: level, partial: partial, editing: false))
                case 17...22:
                    self.hud.update(.thinking(editing: false))
                case 23...30:
                    self.hud.update(.done("I think we should ship the beta on Friday."))
                default:
                    timer.invalidate()
                    self.hud.hide()
                }
            }
        }
    }

    private func fail(_ message: String) {
        isCapturing = false
        audio.stop()
        Task { await transcriber.abort() }
        hud.flash(.failed(message), then: 2.5)
    }
}

enum Sound {
    static func start() { NSSound(named: "Tink")?.play() }
    static func done()  { NSSound(named: "Pop")?.play() }
    static func fail()  { NSSound(named: "Basso")?.play() }
}
