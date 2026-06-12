import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settingsWindow: NSWindow

    init(controller: AppController) {
        let rootView = SettingsRootView()
            .environmentObject(controller)
        let hostingController = NSHostingController(rootView: rootView)
        settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = String(localized: "settings.title")
        settingsWindow.titlebarSeparatorStyle = .none
        settingsWindow.contentViewController = hostingController
        settingsWindow.isReleasedWhenClosed = false
        super.init(window: settingsWindow)
        settingsWindow.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        settingsWindow.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
    }
}
