import AppKit
import CoreGraphics

/// Watches a single modifier key globally and reports press/release.
/// Uses a listen-only event tap, so it needs Accessibility (or Input Monitoring) permission.
final class HotkeyMonitor {

    /// Modifier keys that make good push-to-talk triggers: they are easy to hold
    /// with the left hand and are rarely used alone by other apps.
    enum Trigger: String, CaseIterable {
        case rightOption, rightCommand, fn

        var keyCode: Int64 {
            switch self {
            case .rightOption:  return 61
            case .rightCommand: return 54
            case .fn:           return 63
            }
        }

        var flag: CGEventFlags {
            switch self {
            case .rightOption:  return .maskAlternate
            case .rightCommand: return .maskCommand
            case .fn:           return .maskSecondaryFn
            }
        }

        var label: String {
            switch self {
            case .rightOption:  return "Right ⌥"
            case .rightCommand: return "Right ⌘"
            case .fn:           return "fn"
            }
        }
    }

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private(set) var trigger: Trigger
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var isDown = false

    init(trigger: Trigger) { self.trigger = trigger }

    /// Returns false when the event tap could not be created — almost always a
    /// missing Accessibility grant.
    @discardableResult
    func start() -> Bool {
        stop()
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
        isDown = false
    }

    func setTrigger(_ new: Trigger) {
        trigger = new
        isDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // The system disables a tap that ever blocks; re-arm it rather than dying silently.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .flagsChanged else { return }
        guard event.getIntegerValueField(.keyboardEventKeycode) == trigger.keyCode else { return }

        let down = event.flags.contains(trigger.flag)
        guard down != isDown else { return }
        isDown = down
        DispatchQueue.main.async { down ? self.onPress?() : self.onRelease?() }
    }
}

enum Permissions {
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func promptForAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
