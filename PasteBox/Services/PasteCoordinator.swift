import AppKit
import CoreGraphics
import Foundation

enum PasteResult {
    case pasted
    case copiedOnly
    case unavailableFile
    case failed
}

@MainActor
final class PasteCoordinator {
    private let pasteboard: NSPasteboard
    private let monitor: ClipboardMonitor
    private let permissionManager: PermissionManager

    init(
        pasteboard: NSPasteboard = .general,
        monitor: ClipboardMonitor,
        permissionManager: PermissionManager
    ) {
        self.pasteboard = pasteboard
        self.monitor = monitor
        self.permissionManager = permissionManager
    }

    func copy(_ item: ClipboardItem) -> PasteResult {
        guard write(item) else {
            return item.kind == .file && !item.filesAreAvailable ? .unavailableFile : .failed
        }
        return .copiedOnly
    }

    func paste(_ item: ClipboardItem, into targetApplication: NSRunningApplication?) -> PasteResult {
        permissionManager.refresh()
        guard permissionManager.isAccessibilityGranted else {
            guard write(item) else {
                return item.kind == .file && !item.filesAreAvailable ? .unavailableFile : .failed
            }
            return .copiedOnly
        }

        targetApplication?.activate(options: [.activateAllWindows])
        guard write(item) else {
            return item.kind == .file && !item.filesAreAvailable ? .unavailableFile : .failed
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
        return .pasted
    }

    private func write(_ item: ClipboardItem) -> Bool {
        pasteboard.clearContents()
        let didWrite: Bool

        switch item.kind {
        case .text, .link:
            guard let text = item.textContent else { return false }
            didWrite = pasteboard.setString(text, forType: .string)
        case .image:
            guard let path = item.imagePath,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path))
            else { return false }
            didWrite = pasteboard.setData(data, forType: .png)
        case .file:
            let urls = item.filePaths.map { URL(fileURLWithPath: $0) }
            guard !urls.isEmpty,
                  urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) })
            else { return false }
            didWrite = pasteboard.writeObjects(urls as [NSURL])
        }

        if didWrite {
            monitor.ignoreCurrentChange()
        }
        return didWrite
    }
}
