import AppKit
import SwiftData
import SwiftUI

@MainActor
final class AppController: ObservableObject {
    static let shared = AppController()

    @Published var isPaused = false {
        didSet { monitor?.isPaused = isPaused }
    }
    @Published var statusMessage: String?

    let permissionManager = PermissionManager()
    let screenCapturePermissionManager = ScreenCapturePermissionManager()
    let hotKeyManager = GlobalHotKeyManager()
    let launchAtLoginManager = LaunchAtLoginManager()

    private(set) var container: ModelContainer?
    private(set) var store: ClipboardStore?
    private var monitor: ClipboardMonitor?
    private var pasteCoordinator: PasteCoordinator?
    private var panelController: ClipboardPanelController?
    private var settingsController: SettingsWindowController?
    private var statusPanelController: StatusPanelController?
    private var screenshotCoordinator: ScreenshotCoordinator?
    private var screenshotWarmStateObservers: [NSObjectProtocol] = []
    private var previousApplication: NSRunningApplication?
    private var hasStarted = false

    private init() {}

    func install(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        let store = ClipboardStore(container: container)
        let monitor = ClipboardMonitor(store: store)
        self.store = store
        self.monitor = monitor
        pasteCoordinator = PasteCoordinator(
            monitor: monitor,
            permissionManager: permissionManager
        )
        screenshotCoordinator = ScreenshotCoordinator(
            monitor: monitor,
            store: store,
            permissionManager: screenCapturePermissionManager
        ) { [weak self] message in
            self?.showStatus(message)
        }
    }

    func start() {
        guard !hasStarted, let container else { return }
        hasStarted = true
        NSApp.setActivationPolicy(.accessory)
        monitor?.start()
        hotKeyManager.register(.clipboardPanel) { [weak self] in self?.showPanel() }
        hotKeyManager.register(.screenshot) { [weak self] in self?.startScreenshot() }
        panelController = ClipboardPanelController(container: container, controller: self)
        settingsController = SettingsWindowController(controller: self)
        statusPanelController = StatusPanelController()
        permissionManager.refresh()
        screenshotCoordinator?.prewarm()
        installScreenshotWarmStateObservers()

        if !permissionManager.isAccessibilityGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.permissionManager.requestAccessibilityPermission()
            }
        }

        if !UserDefaults.standard.bool(forKey: "onboarding.completed") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.showSettings()
            }
        }
    }

    func showPanel() {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != ownBundleIdentifier {
            previousApplication = frontmost
        }
        panelController?.show()
    }

    func startScreenshot() {
        closePanel()
        screenshotCoordinator?.start()
    }

    func refreshScreenshotWarmState() {
        screenshotCoordinator?.refreshWarmState()
    }

    func closePanel() {
        panelController?.close()
    }

    func showSettings() {
        settingsController?.show()
    }

    func paste(_ item: ClipboardItem) {
        let result = pasteCoordinator?.paste(item, into: previousApplication) ?? .failed
        closePanel()
        switch result {
        case .pasted:
            break
        case .copiedOnly:
            showStatus(String(localized: "status.copied.permission"))
        case .unavailableFile:
            showStatus(String(localized: "status.file.unavailable"))
        case .failed:
            showStatus(String(localized: "status.copy.failed"))
        }
    }

    func copyOnly(_ item: ClipboardItem) {
        let result = pasteCoordinator?.copy(item) ?? .failed
        switch result {
        case .copiedOnly, .pasted:
            showStatus(String(localized: "status.copied"))
        case .unavailableFile:
            showStatus(String(localized: "status.file.unavailable"))
        case .failed:
            showStatus(String(localized: "status.copy.failed"))
        }
    }

    func toggleFavorite(_ item: ClipboardItem) {
        store?.toggleFavorite(item)
    }

    func delete(_ item: ClipboardItem) {
        store?.delete(item)
    }

    func clearAll() {
        store?.clearAll()
        showStatus(String(localized: "status.cleared"))
    }

    func cleanupHistory() {
        try? store?.cleanup()
    }

    func revealInFinder(_ item: ClipboardItem) {
        let urls = item.filePaths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else {
            showStatus(String(localized: "status.file.unavailable"))
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding.completed")
        objectWillChange.send()
    }

    func showStatus(_ message: String) {
        statusMessage = message
        statusPanelController?.show(message: message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.statusMessage == message {
                self.statusMessage = nil
            }
        }
    }

    private func installScreenshotWarmStateObservers() {
        guard screenshotWarmStateObservers.isEmpty else { return }
        let center = NotificationCenter.default
        screenshotWarmStateObservers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.screenshotCoordinator?.refreshWarmState()
                }
            }
        )
        screenshotWarmStateObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.screenshotCoordinator?.refreshWarmState()
                }
            }
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in AppController.shared.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // SwiftData's main context autosaves; explicit lifecycle hook kept for future migrations.
    }
}
