import AppKit
import SwiftUI

@main
struct WispMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let controller = Controller()
    private var settingsWindow: NSWindow?
    private var onboarding: OnboardingWindow!
    private var observer: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "waveform", accessibilityDescription: "Wisp"
        )
        statusItem.button?.image?.isTemplate = true
        onboarding = OnboardingWindow(controller: controller)
        rebuildMenu()

        // Lets the capsule be inspected without permissions, a model, or a voice.
        if ProcessInfo.processInfo.environment["WISP_PREVIEW_CAPSULE"] != nil {
            controller.previewCapsule()
            return
        }

        // First run, or the grants were revoked since last time: walk the user through it.
        if !OnboardingWindow.hasCompleted || !Controller.isConfigured {
            onboarding.show()
            Task { await controller.start(); rebuildMenu() }
        } else {
            Task {
                await controller.start()
                rebuildMenu()
            }
        }

        // Keep the menu's status line honest as the controller changes state.
        observer = NotificationCenter.default.addObserver(
            forName: .wispStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildMenu() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let status = NSMenuItem(title: controller.status, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if !Controller.isConfigured {
            menu.addItem(item("Finish Setup…", #selector(openWelcome)))
        }
        if let reason = Polisher.unavailableReason {
            let note = NSMenuItem(title: reason, action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
        }

        menu.addItem(.separator())

        let stats = History.shared.stats
        if stats.words > 0 {
            let line = NSMenuItem(
                title: "\(stats.words.formatted()) words · \(stats.wpm) wpm",
                action: nil, keyEquivalent: ""
            )
            line.isEnabled = false
            menu.addItem(line)
        }

        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Welcome & Setup…", #selector(openWelcome)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Wisp", #selector(quit), key: "q"))

        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openWelcome() {
        onboarding.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Wisp"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: SettingsView(controller: controller)
                .environmentObject(Settings.shared)
                .environmentObject(History.shared)
        )
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name {
    static let wispStateChanged = Notification.Name("WispStateChanged")
}
