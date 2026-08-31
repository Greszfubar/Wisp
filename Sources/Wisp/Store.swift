import Foundation

/// User preferences, backed by UserDefaults. Small enough not to warrant a database.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var trigger: HotkeyMonitor.Trigger {
        didSet { defaults.set(trigger.rawValue, forKey: "trigger") }
    }
    @Published var style: WritingStyle {
        didSet { defaults.set(style.rawValue, forKey: "style") }
    }
    /// Proper nouns, product names and jargon the recogniser keeps getting wrong.
    @Published var terms: [String] {
        didSet { defaults.set(terms, forKey: "terms") }
    }
    @Published var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: "playSounds") }
    }
    @Published var keepHistory: Bool {
        didSet { defaults.set(keepHistory, forKey: "keepHistory") }
    }

    private init() {
        trigger = HotkeyMonitor.Trigger(rawValue: defaults.string(forKey: "trigger") ?? "")
            ?? .rightOption
        style = WritingStyle(rawValue: defaults.string(forKey: "style") ?? "") ?? .faithful
        terms = defaults.stringArray(forKey: "terms") ?? []
        playSounds = defaults.object(forKey: "playSounds") as? Bool ?? true
        keepHistory = defaults.object(forKey: "keepHistory") as? Bool ?? true
    }
}

struct Dictation: Codable, Identifiable {
    let id: UUID
    let date: Date
    let text: String
    let appName: String?
    let wasEdit: Bool
    /// Seconds of speech, used for the words-per-minute figure.
    let duration: TimeInterval

    var wordCount: Int {
        text.split { $0 == " " || $0 == "\n" }.count
    }
}

/// Append-only local history, capped so the file never grows without bound.
/// Written to Application Support — it never leaves the machine.
@MainActor
final class History: ObservableObject {
    static let shared = History()
    private static let limit = 500

    @Published private(set) var entries: [Dictation] = []

    private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wisp", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("history.json")
    }()

    private init() { load() }

    func add(_ entry: Dictation) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: url)
    }

    /// Words per minute across everything dictated, and the running total.
    var stats: (words: Int, wpm: Int) {
        let words = entries.reduce(0) { $0 + $1.wordCount }
        let seconds = entries.reduce(0.0) { $0 + $1.duration }
        guard seconds > 1 else { return (words, 0) }
        return (words, Int(Double(words) / (seconds / 60)))
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Dictation].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard Settings.shared.keepHistory else { return }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
