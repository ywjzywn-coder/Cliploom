import AppKit
import SwiftData
import SwiftUI

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension Notification.Name {
    static let pasteBoxPanelWillShow = Notification.Name("PasteBoxPanelWillShow")
    static let pasteBoxMoveSelection = Notification.Name("PasteBoxMoveSelection")
    static let pasteBoxConfirmSelection = Notification.Name("PasteBoxConfirmSelection")
}

@MainActor
final class ClipboardPanelController: NSWindowController, NSWindowDelegate {
    private static let savedOriginXKey = "clipboardPanel.originX"
    private static let savedOriginYKey = "clipboardPanel.originY"

    private let panel: KeyablePanel
    private var keyMonitor: Any?

    init(container: ModelContainer, controller: AppController) {
        let rootView = ClipboardPanelView()
            .environmentObject(controller)
            .modelContainer(container)
        let hostingController = NSHostingController(rootView: rootView)
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.title = "Cliploom"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        restoreOrPositionPanel()
        installKeyMonitor()
        NotificationCenter.default.post(name: .pasteBoxPanelWillShow, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    override func close() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    private func restoreOrPositionPanel() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.savedOriginXKey) != nil,
           defaults.object(forKey: Self.savedOriginYKey) != nil {
            let savedOrigin = NSPoint(
                x: defaults.double(forKey: Self.savedOriginXKey),
                y: defaults.double(forKey: Self.savedOriginYKey)
            )
            panel.setFrameOrigin(savedOrigin)
            keepPanelVisible()
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    private func keepPanelVisible() {
        guard let screen = bestScreen(for: panel.frame) ?? NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        var origin = panel.frame.origin
        origin.x = min(
            max(origin.x, visibleFrame.minX),
            max(visibleFrame.minX, visibleFrame.maxX - panel.frame.width)
        )
        origin.y = min(
            max(origin.y, visibleFrame.minY),
            max(visibleFrame.minY, visibleFrame.maxY - panel.frame.height)
        )
        panel.setFrameOrigin(origin)
    }

    private func bestScreen(for frame: NSRect) -> NSScreen? {
        NSScreen.screens.max {
            $0.visibleFrame.intersection(frame).area
                < $1.visibleFrame.intersection(frame).area
        }
    }

    func windowDidMove(_ notification: Notification) {
        let origin = panel.frame.origin
        let defaults = UserDefaults.standard
        defaults.set(origin.x, forKey: Self.savedOriginXKey)
        defaults.set(origin.y, forKey: Self.savedOriginYKey)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            switch event.keyCode {
            case 53:
                self.close()
                return nil
            case 125:
                NotificationCenter.default.post(
                    name: .pasteBoxMoveSelection,
                    object: nil,
                    userInfo: ["offset": 1]
                )
                return nil
            case 126:
                NotificationCenter.default.post(
                    name: .pasteBoxMoveSelection,
                    object: nil,
                    userInfo: ["offset": -1]
                )
                return nil
            case 36, 76:
                NotificationCenter.default.post(name: .pasteBoxConfirmSelection, object: nil)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
