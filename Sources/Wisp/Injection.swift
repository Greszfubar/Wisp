import AppKit
import ApplicationServices

/// Reads whatever text is selected in the frontmost app via the accessibility API.
/// This is what decides between "dictate" and "edit" mode — no classifier needed.
enum SelectionReader {

    static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focused
        )
        guard result == .success, let value = focused else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func selectedText() -> String? {
        guard let element = focusedElement() else { return nil }
        var selection: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selection
        )
        guard result == .success, let text = selection as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }

    static var frontmostAppName: String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}

/// Puts text into whatever app has focus.
///
/// Pasting beats synthesising keystrokes: it is instant regardless of length,
/// it survives non-ASCII and emoji, and it doesn't trip autocomplete in editors.
/// The cost is borrowing the pasteboard, which we put back afterwards.
enum TextInjector {

    private static let vKey: CGKeyCode = 9

    static func insert(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Let the pasteboard settle before the synthetic paste, or fast apps read stale contents.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            pressCommand(vKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                restore(saved, to: pasteboard)
            }
        }
    }

    /// Replaces the current selection. Pasting over a selection already replaces it,
    /// so this is `insert` — kept separate because the intent differs at the call site.
    static func replaceSelection(with text: String) { insert(text) }

    private static func pressCommand(_ key: CGKeyCode) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        // We post after the trigger key is already up, so the user's own input should
        // keep flowing normally — permit everything rather than suppressing it.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up   = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: Pasteboard preservation

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var stored: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { stored[type] = data }
            }
            return stored
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { stored -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in stored { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
