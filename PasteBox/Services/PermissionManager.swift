import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var isAccessibilityGranted = AXIsProcessTrusted()
    private var appActiveObserver: NSObjectProtocol?

    init() {
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.scheduleFollowUpChecks()
            }
        }
    }

    deinit {
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
        }
    }

    @discardableResult
    func refresh() -> Bool {
        let granted = AXIsProcessTrusted()
        if isAccessibilityGranted != granted {
            isAccessibilityGranted = granted
        }
        return granted
    }

    func requestAccessibilityPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        isAccessibilityGranted = AXIsProcessTrustedWithOptions(options)
        scheduleFollowUpChecks()
    }

    func openAccessibilitySettings() {
        requestAccessibilityPermission()
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSWorkspace.shared.open(url)
        }
    }

    func monitorUntilCancelled() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func scheduleFollowUpChecks() {
        for delay in [0.5, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refresh()
            }
        }
    }
}
