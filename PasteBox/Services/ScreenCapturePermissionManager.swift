import AppKit
import CoreGraphics
import Foundation

@MainActor
final class ScreenCapturePermissionManager: ObservableObject {
    @Published private(set) var isGranted = CGPreflightScreenCaptureAccess()

    @discardableResult
    func refresh() -> Bool {
        let value = CGPreflightScreenCaptureAccess()
        if isGranted != value {
            isGranted = value
        }
        return value
    }

    func requestPermission() {
        isGranted = CGRequestScreenCaptureAccess()
        scheduleFollowUpChecks()
    }

    func openSettings() {
        requestPermission()
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
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
