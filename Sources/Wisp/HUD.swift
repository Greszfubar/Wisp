import AppKit
import SwiftUI

enum HUDState: Equatable {
    case idle
    case listening(level: Float, partial: String, editing: Bool)
    case thinking(editing: Bool)
    case done(String)
    case failed(String)
}

@MainActor
final class HUDModel: ObservableObject {
    @Published var state: HUDState = .idle
    @Published var visible = false
}

/// A small capsule low on the active screen: the only way to know Wisp is listening.
///
/// The panel is deliberately oversized and transparent — the capsule inside hugs its
/// own content, so it can grow as words arrive without the window ever being resized.
@MainActor
final class HUD {
    private static let panelSize = NSSize(width: 620, height: 72)
    private static let bottomInset: CGFloat = 56

    private var panel: NSPanel?
    private let model = HUDModel()
    private var hideWork: DispatchWorkItem?

    func show(_ state: HUDState) {
        hideWork?.cancel()
        model.state = state
        ensurePanel()
        reposition()
        panel?.orderFrontRegardless()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            model.visible = true
        }
    }

    func update(_ state: HUDState) {
        model.state = state
        guard state != .idle else { return }
        ensurePanel()
        panel?.orderFrontRegardless()
    }

    func flash(_ state: HUDState, then delay: TimeInterval = 1.4) {
        update(state)
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { model.visible = false }
        // Let the fade finish before pulling the window out from under it.
        let panel = self.panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, self.model.visible == false else { return }
            panel?.orderOut(nil)
            self.model.state = .idle
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: CapsuleView(model: model))
        self.panel = panel
    }

    private func reposition() {
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - Self.panelSize.width / 2,
            y: visible.minY + Self.bottomInset
        ))
    }
}

// MARK: - Capsule

private struct CapsuleView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            capsule
                .opacity(model.visible ? 1 : 0)
                .scaleEffect(model.visible ? 1 : 0.88, anchor: .bottom)
                .offset(y: model.visible ? 0 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var capsule: some View {
        HStack(spacing: 10) {
            leading
            if let label = text {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 420, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(tint.opacity(isActive ? 0.5 : 0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 16, y: 5)
        )
        .animation(.easeOut(duration: 0.16), value: model.state)
    }

    // MARK: pieces

    @ViewBuilder private var leading: some View {
        switch model.state {
        case .listening(let level, _, let editing):
            HStack(spacing: 5) {
                // Editing overwrites the user's selection, so it must never be
                // distinguishable by colour alone — an orange system accent would
                // otherwise make it identical to plain dictation.
                if editing { modeGlyph }
                Meter(level: level, tint: tint)
            }
        case .thinking(let editing):
            HStack(spacing: 5) {
                if editing { modeGlyph }
                ProgressView().controlSize(.small).scaleEffect(0.8).frame(width: 22, height: 22)
            }
        case .done:
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                .foregroundStyle(.green).frame(width: 22, height: 22)
        case .failed:
            Image(systemName: "exclamationmark").font(.system(size: 12, weight: .bold))
                .foregroundStyle(.orange).frame(width: 22, height: 22)
        case .idle:
            EmptyView()
        }
    }

    /// Shown whenever speech will replace a selection rather than be inserted.
    private var modeGlyph: some View {
        Image(systemName: "pencil.line")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 14)
    }

    private var text: String? {
        switch model.state {
        case .listening(_, let partial, let editing):
            if partial.isEmpty { return editing ? "Editing selection" : "Listening" }
            return partial
        case .thinking(let editing):
            return editing ? "Rewriting" : "Tidying up"
        case .done(let result):
            return result
        case .failed(let message):
            return message
        case .idle:
            return nil
        }
    }

    private var isActive: Bool {
        if case .listening = model.state { return true }
        return false
    }

    private var tint: Color {
        switch model.state {
        case .listening(_, _, let editing), .thinking(let editing):
            return editing ? .orange : .accentColor
        case .done:   return .green
        case .failed: return .orange
        case .idle:   return .secondary
        }
    }

    private var textColor: Color {
        if case .listening(_, let partial, _) = model.state, partial.isEmpty {
            return .secondary
        }
        return .primary
    }
}

/// Five bars driven by input level. The middle reacts most, which reads as a voice.
private struct Meter: View {
    let level: Float
    let tint: Color

    private let weights: [CGFloat] = [0.45, 0.78, 1.0, 0.78, 0.45]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(tint)
                    .frame(width: 3, height: height(for: i))
            }
        }
        .frame(width: 22, height: 22)
        .animation(.easeOut(duration: 0.09), value: level)
    }

    private func height(for index: Int) -> CGFloat {
        let amplitude = CGFloat(max(0.08, min(1, level))) * weights[index]
        return max(3, amplitude * 20)
    }
}
