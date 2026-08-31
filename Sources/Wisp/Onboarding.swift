import AppKit
import AVFoundation
import SwiftUI

/// Polls the two grants Wisp needs. Accessibility is granted outside the app,
/// so there is no callback to observe — polling is the only way to notice.
@MainActor
final class PermissionState: ObservableObject {
    @Published var microphone = false
    @Published var accessibility = false

    private var timer: Timer?

    var allGranted: Bool { microphone && accessibility }

    init() { refresh() }

    func beginPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        microphone = MicPermission.isAuthorized
        accessibility = Permissions.hasAccessibility
    }
}

@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let permissions = PermissionState()
    private let controller: Controller

    init(controller: Controller) {
        self.controller = controller
    }

    static var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: "didOnboard") }
        set { UserDefaults.standard.set(newValue, forKey: "didOnboard") }
    }

    func show() {
        permissions.beginPolling()

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: WelcomeView(permissions: permissions, controller: controller) { [weak self] in
                self?.finish()
            }
        )
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish() {
        Self.hasCompleted = true
        permissions.stopPolling()
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        permissions.stopPolling()
    }
}

// MARK: - View

private struct WelcomeView: View {
    @ObservedObject var permissions: PermissionState
    @ObservedObject var controller: Controller
    var onFinish: () -> Void

    @State private var requestingMic = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 22)
            steps
            Spacer(minLength: 20)
            footer
        }
        .padding(30)
        .frame(width: 520, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.tint)

            Text("Wisp")
                .font(.system(size: 32, weight: .bold))

            Text("Hold a key, say the thing, let go. The finished text lands wherever your cursor already is — and none of it leaves this Mac.")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Two permissions and one download")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(.secondary)

            StepRow(
                title: "Microphone",
                detail: "So Wisp can hear you while the key is held.",
                done: permissions.microphone,
                busy: requestingMic,
                action: permissions.microphone ? nil : ("Allow", requestMic)
            )

            StepRow(
                title: "Accessibility",
                detail: "So Wisp can see your hotkey and type into other apps.",
                done: permissions.accessibility,
                busy: false,
                action: permissions.accessibility ? nil : ("Open Settings", openAccessibility)
            )

            StepRow(
                title: "Speech model",
                detail: modelDetail,
                done: controller.isReady,
                busy: controller.isPreparing,
                action: modelAction
            )
        }
    }

    private var modelDetail: String {
        if controller.isReady { return "Parakeet is loaded and running on the Neural Engine." }
        if controller.isPreparing { return "Downloading — this is about 600 MB and happens once." }
        if !permissions.allGranted { return "Available once the permissions above are granted." }
        return "About 600 MB, downloaded once, then it works offline."
    }

    private var modelAction: (String, () -> Void)? {
        guard !controller.isReady, !controller.isPreparing, permissions.allGranted else { return nil }
        return ("Download", { Task { await controller.start() } })
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            if controller.isReady {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Ready. Hold \(Settings.shared.trigger.label) anywhere and talk.")
                        .font(.system(size: 13, weight: .medium))
                }
            } else {
                Text(controller.status)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Wisp lives in the menu bar — there's no Dock icon.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(controller.isReady ? "Start Using Wisp" : "Skip for Now", action: onFinish)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
    }

    private func requestMic() {
        requestingMic = true
        Task {
            _ = await MicPermission.request()
            permissions.refresh()
            requestingMic = false
        }
    }

    private func openAccessibility() {
        // Prompting first puts Wisp in the list, so the user has something to toggle.
        Permissions.promptForAccessibility()
        Permissions.openAccessibilitySettings()
    }
}

private struct StepRow: View {
    let title: String
    let detail: String
    let done: Bool
    let busy: Bool
    let action: (String, () -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            marker
                .frame(width: 20, height: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let (label, run) = action {
                Button(label, action: run).controlSize(.regular)
            }
        }
        .opacity(action == nil && !done && !busy ? 0.5 : 1)
    }

    @ViewBuilder private var marker: some View {
        if done {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.system(size: 16))
        } else if busy {
            ProgressView().controlSize(.small)
        } else {
            Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
        }
    }
}
