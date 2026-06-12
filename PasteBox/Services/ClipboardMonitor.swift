import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private let store: ClipboardStore
    private var timer: Timer?
    private var lastChangeCount: Int
    private(set) var ignoredChangeCount: Int?
    var isPaused = false

    init(pasteboard: NSPasteboard = .general, store: ClipboardStore) {
        self.pasteboard = pasteboard
        self.store = store
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func ignoreCurrentChange() {
        lastChangeCount = pasteboard.changeCount
        ignoredChangeCount = lastChangeCount
    }

    func poll() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        if ignoredChangeCount == currentChangeCount {
            ignoredChangeCount = nil
            return
        }
        guard !isPaused, let payload = ClipboardPayload.read(from: pasteboard) else { return }
        _ = try? store.save(payload)
    }
}
