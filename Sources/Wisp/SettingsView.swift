import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: Controller
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var history: History
    @State private var newTerm = ""

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            vocabulary.tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
            historyTab.tabItem { Label("History", systemImage: "clock") }
        }
        .frame(width: 460, height: 480)
    }

    // MARK: General

    private var general: some View {
        Form {
            Section {
                Picker("Hold to talk", selection: $settings.trigger) {
                    ForEach(HotkeyMonitor.Trigger.allCases, id: \.self) { trigger in
                        Text(trigger.label).tag(trigger)
                    }
                }
                .onChange(of: settings.trigger) { _, _ in controller.applyTriggerChange() }

                Picker("Cleanup", selection: $settings.style) {
                    ForEach(WritingStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                Text(settings.style.blurb)
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Dictation")
            }

            Section {
                Toggle("Play sounds", isOn: $settings.playSounds)
                Toggle("Keep history on this Mac", isOn: $settings.keepHistory)
            }

            Section {
                Label {
                    Text(controller.status)
                } icon: {
                    Image(systemName: controller.isReady ? "checkmark.circle.fill" : "clock")
                        .foregroundStyle(controller.isReady ? .green : .secondary)
                }
                .font(.callout)

                if !Permissions.hasAccessibility {
                    Button("Open Accessibility Settings…") {
                        Permissions.openAccessibilitySettings()
                    }
                }
            } header: {
                Text("Status")
            } footer: {
                Text("Speech is recognised by Parakeet on the Neural Engine and cleaned up by Apple Intelligence. Nothing is uploaded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Vocabulary

    private var vocabulary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Names, products and jargon the recogniser keeps getting wrong. Wisp will spell these exactly.")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                TextField("Add a term", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTerm)
                Button("Add", action: addTerm)
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List {
                ForEach(settings.terms, id: \.self) { term in
                    HStack {
                        Text(term)
                        Spacer()
                        Button {
                            settings.terms.removeAll { $0 == term }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .overlay {
                if settings.terms.isEmpty {
                    Text("No custom terms yet")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !settings.terms.contains(term) else { return }
        settings.terms.append(term)
        newTerm = ""
    }

    // MARK: History

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            let stats = history.stats
            HStack(spacing: 16) {
                Stat(value: stats.words.formatted(), label: "words")
                Stat(value: "\(stats.wpm)", label: "wpm")
                Stat(value: "\(history.entries.count)", label: "sessions")
                Spacer()
                Button("Clear", role: .destructive) { history.clear() }
                    .disabled(history.entries.isEmpty)
            }
            .padding(.horizontal, 4)

            List(history.entries) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.text).lineLimit(3).font(.system(size: 12))
                    HStack(spacing: 6) {
                        if entry.wasEdit {
                            Text("EDIT").font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                        }
                        Text(entry.appName ?? "—")
                        Text("·")
                        Text(entry.date, style: .relative)
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .overlay {
                if history.entries.isEmpty {
                    Text("Nothing dictated yet").foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
    }
}

private struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
