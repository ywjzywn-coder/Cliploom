import AppKit
import CoreImage
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
final class ScreenshotCoordinator: ScreenshotOverlayControllerDelegate {
    private let monitor: ClipboardMonitor
    private let store: ClipboardStore
    private let permissionManager: ScreenCapturePermissionManager
    private let pasteboard: NSPasteboard
    private let showStatus: (String) -> Void
    private var overlayController: ScreenshotOverlayController?
    private var isCapturing = false
    private var cachedShareableContent: SCShareableContent?
    private var shareableContentLoadedAt: Date?
    private var shareableContentTask: Task<SCShareableContent, Error>?
    private var captureTargets: [CGDirectDisplayID: CaptureTarget] = [:]
    private var captureTask: Task<Void, Never>?
    private var captureGeneration: UInt = 0
    private var warmupTask: Task<Void, Never>?
    private let frameCache = ScreenshotFrameCache()
    private var textRecognitionTask: Task<Void, Never>?
    private var barcodeScanTask: Task<Void, Never>?
    private var textRecognitionGeneration: UInt = 0
    private var barcodeScanGeneration: UInt = 0

    private static let shareableContentCacheLifetime: TimeInterval = 300
    private static let frameCacheMaximumAge: TimeInterval = 0.5

    init(
        monitor: ClipboardMonitor,
        store: ClipboardStore,
        permissionManager: ScreenCapturePermissionManager,
        pasteboard: NSPasteboard = .general,
        showStatus: @escaping (String) -> Void
    ) {
        self.monitor = monitor
        self.store = store
        self.permissionManager = permissionManager
        self.pasteboard = pasteboard
        self.showStatus = showStatus
    }

    func prewarm() {
        TextRecognizer.prewarm()
        guard permissionManager.refresh() else { return }
        guard warmupTask == nil else { return }
        warmupTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { warmupTask = nil }
            for screen in NSScreen.screens {
                guard !Task.isCancelled,
                      let displayID = displayID(for: screen),
                      let target = try? await captureTarget(for: screen),
                      !Task.isCancelled
                else { continue }
                try? await frameCache.start(
                    displayID: displayID,
                    target: target
                )
            }
        }
    }

    func refreshWarmState() {
        warmupTask?.cancel()
        warmupTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await frameCache.stopAll()
            invalidateShareableContent()
            warmupTask = nil
            prewarm()
        }
    }

    func start() {
        guard permissionManager.refresh() else {
            replaceActiveSession()
            permissionManager.requestPermission()
            showStatus(String(localized: "screenshot.permission.required"))
            return
        }
        guard let screen = screenUnderMouse() else {
            replaceActiveSession()
            showStatus(String(localized: "screenshot.capture.failed"))
            return
        }

        // Read the frame before closing an existing OCR or barcode result window.
        // The next overlay can then show exactly what was visible when the hotkey fired.
        let cachedImage = displayID(for: screen).flatMap { displayID in
            frameCache.image(
                for: displayID,
                maximumAge: Self.frameCacheMaximumAge
            )
        }
        replaceActiveSession()

        isCapturing = true
        captureGeneration &+= 1
        let generation = captureGeneration
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let windows = capturableWindows(on: screen)
                let capturedImage: CGImage
                if let cachedImage {
                    capturedImage = cachedImage
                } else {
                    capturedImage = try await capture(screen: screen)
                }
                guard !Task.isCancelled, generation == captureGeneration else {
                    return
                }
                let session = ScreenshotSession(
                    image: capturedImage,
                    screen: screen,
                    windows: windows
                )
                let controller = ScreenshotOverlayController(session: session)
                controller.delegate = self
                overlayController = controller
                isCapturing = false
                captureTask = nil
                controller.show()
            } catch {
                guard !Task.isCancelled, generation == captureGeneration else {
                    return
                }
                isCapturing = false
                captureTask = nil
                showStatus(String(localized: "screenshot.capture.failed"))
            }
        }
    }

    func screenshotOverlayDidCancel(_ controller: ScreenshotOverlayController) {
        finishSession()
    }

    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didFinishWith data: Data
    ) {
        guard commitImage(data) else {
            showStatus(String(localized: "screenshot.copy.failed"))
            return
        }
        finishSession()
        showStatus(String(localized: "screenshot.copied"))
    }

    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didRequestSave data: Data
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Cliploom-\(Self.fileTimestamp()).png"
        let response = panel.runModal()

        guard response == .OK, let url = panel.url else {
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            guard commitImage(data) else {
                showStatus(String(localized: "screenshot.copy.failed"))
                return
            }
            finishSession()
            showStatus(String(localized: "screenshot.saved"))
        } catch {
            showStatus(String(localized: "screenshot.save.failed"))
        }
    }

    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didRequestScan image: CGImage
    ) {
        barcodeScanGeneration &+= 1
        let generation = barcodeScanGeneration
        barcodeScanTask?.cancel()
        barcodeScanTask = Task { [weak self, weak controller] in
            guard let self, let controller else { return }
            defer {
                if barcodeScanGeneration == generation {
                    barcodeScanTask = nil
                }
            }
            do {
                let results = try await BarcodeScanner.scan(cgImage: image)
                guard !Task.isCancelled,
                      barcodeScanGeneration == generation,
                      overlayController === controller
                else {
                    return
                }
                controller.showBarcodeResults(results)
            } catch {
                guard !Task.isCancelled,
                      barcodeScanGeneration == generation,
                      overlayController === controller
                else {
                    return
                }
                controller.showBarcodeMessage(
                    String(localized: "screenshot.scan.failed")
                )
            }
        }
    }

    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didRequestRecognizeText image: CGImage
    ) {
        textRecognitionGeneration &+= 1
        let generation = textRecognitionGeneration
        textRecognitionTask?.cancel()
        textRecognitionTask = Task { [weak self, weak controller] in
            guard let self, let controller else { return }
            defer {
                if textRecognitionGeneration == generation {
                    textRecognitionTask = nil
                }
            }
            do {
                let text = try await TextRecognizer.recognize(cgImage: image)
                guard !Task.isCancelled,
                      textRecognitionGeneration == generation,
                      overlayController === controller
                else {
                    return
                }
                controller.showRecognizedText(text)
            } catch {
                guard !Task.isCancelled,
                      textRecognitionGeneration == generation,
                      overlayController === controller
                else {
                    return
                }
                controller.showTextRecognitionMessage(
                    String(localized: "screenshot.ocr.failed")
                )
            }
        }
    }

    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didRequestCopyRecognizedText text: String
    ) {
        commitRecognizedText(
            text,
            successMessage: String(localized: "screenshot.ocr.copied")
        )
    }

    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didRequestCopyBarcode result: BarcodeResult
    ) {
        commitBarcodeText(result)
    }

    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didRequestOpenBarcode result: BarcodeResult
    ) {
        guard let url = result.webURL else {
            showStatus(String(localized: "screenshot.scan.notLink"))
            return
        }
        NSWorkspace.shared.open(url)
    }

    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didRequestCopyColor value: String
    ) -> Bool {
        pasteboard.clearContents()
        guard pasteboard.setString(value, forType: .string) else {
            return false
        }
        monitor.ignoreCurrentChange()
        return true
    }

    private func capture(screen: NSScreen) async throws -> CGImage {
        do {
            let target = try await captureTarget(for: screen)
            return try await capture(target: target)
        } catch {
            invalidateShareableContent()
            let refreshedTarget = try await captureTarget(for: screen)
            return try await capture(target: refreshedTarget)
        }
    }

    private func captureTarget(for screen: NSScreen) async throws -> CaptureTarget {
        guard let displayID = displayID(for: screen) else {
            throw ScreenshotError.displayUnavailable
        }
        if let target = captureTargets[displayID] {
            return target
        }

        let content = try await shareableContent()
        guard let display = content.displays.first(
            where: { $0.displayID == displayID }
        ) else {
            throw ScreenshotError.displayUnavailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let modePixelSize = CGDisplayCopyDisplayMode(displayID).map {
            CGSize(width: $0.pixelWidth, height: $0.pixelHeight)
        }
        let pixelSize = ScreenshotCaptureGeometry.orientedPixelSize(
            logicalSize: CGSize(width: display.width, height: display.height),
            modePixelSize: modePixelSize
        )
        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.queueDepth = 1
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        let target = CaptureTarget(
            filter: filter,
            configuration: configuration
        )
        captureTargets[displayID] = target
        return target
    }

    private func capture(target: CaptureTarget) async throws -> CGImage {
        return try await SCScreenshotManager.captureImage(
            contentFilter: target.filter,
            configuration: target.configuration
        )
    }

    private func shareableContent() async throws -> SCShareableContent {
        if let cachedShareableContent,
           let shareableContentLoadedAt,
           Date().timeIntervalSince(shareableContentLoadedAt)
                < Self.shareableContentCacheLifetime {
            return cachedShareableContent
        }

        if let shareableContentTask {
            return try await shareableContentTask.value
        }

        let task = Task {
            try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        }
        shareableContentTask = task

        do {
            let content = try await task.value
            cachedShareableContent = content
            shareableContentLoadedAt = Date()
            shareableContentTask = nil
            return content
        } catch {
            shareableContentTask = nil
            throw error
        }
    }

    private func invalidateShareableContent() {
        cachedShareableContent = nil
        shareableContentLoadedAt = nil
        captureTargets.removeAll()
    }

    private func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            ?? NSScreen.main
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber).map {
            CGDirectDisplayID($0.uint32Value)
        }
    }

    private func capturableWindows(on screen: NSScreen) -> [CapturableWindow] {
        guard let displayID = displayID(for: screen),
              let rawWindows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[CFString: Any]]
        else { return [] }

        let displayBounds = CGDisplayBounds(displayID)
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        return rawWindows.compactMap { info in
            guard let boundsDictionary = info[kCGWindowBounds] as? [String: Any],
                  let globalFrame = CGRect(
                    dictionaryRepresentation: boundsDictionary as CFDictionary
                  ),
                  let number = info[kCGWindowNumber] as? NSNumber,
                  let layer = info[kCGWindowLayer] as? NSNumber,
                  layer.intValue == 0,
                  let alpha = info[kCGWindowAlpha] as? NSNumber,
                  alpha.doubleValue > 0.02,
                  globalFrame.width >= 40,
                  globalFrame.height >= 30,
                  globalFrame.intersects(displayBounds)
            else { return nil }

            let ownerName = info[kCGWindowOwnerName] as? String ?? ""
            let ownerPID = (info[kCGWindowOwnerPID] as? NSNumber)?.int32Value
            guard ownerPID != ownProcessID,
                  ownerName != "Window Server",
                  ownerName != "Dock"
            else { return nil }

            let localFrame = ScreenshotCoordinateMapper.localWindowFrame(
                globalFrame: globalFrame,
                displayBounds: displayBounds,
                screenSize: screen.frame.size
            )
            guard localFrame.width >= 40, localFrame.height >= 30 else { return nil }
            return CapturableWindow(
                windowID: CGWindowID(number.uint32Value),
                ownerName: ownerName,
                frame: localFrame,
                layer: layer.intValue
            )
        }
    }

    private func commitImage(_ data: Data) -> Bool {
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else { return false }
        monitor.ignoreCurrentChange()
        do {
            _ = try store.save(.image(data))
            return true
        } catch {
            return false
        }
    }

    private func commitBarcodeText(_ result: BarcodeResult) {
        commitRecognizedText(
            result.payload,
            successMessage: String(localized: "screenshot.scan.copied")
        )
    }

    private func commitRecognizedText(
        _ text: String,
        successMessage: String
    ) {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            showStatus(String(localized: "status.copy.failed"))
            return
        }
        monitor.ignoreCurrentChange()
        _ = try? store.save(
            .text(text, isLink: ClipboardPayload.isWebLink(text))
        )
        showStatus(successMessage)
    }

    private func finishSession() {
        textRecognitionGeneration &+= 1
        textRecognitionTask?.cancel()
        textRecognitionTask = nil
        barcodeScanGeneration &+= 1
        barcodeScanTask?.cancel()
        barcodeScanTask = nil
        overlayController?.close()
        overlayController = nil
    }

    private func replaceActiveSession() {
        captureGeneration &+= 1
        captureTask?.cancel()
        captureTask = nil
        isCapturing = false
        finishSession()
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: .now)
    }
}

private enum ScreenshotError: Error {
    case displayUnavailable
}

private struct CaptureTarget {
    let filter: SCContentFilter
    let configuration: SCStreamConfiguration
}

@MainActor
private final class ScreenshotFrameCache {
    private struct Entry {
        let stream: SCStream
        let receiver: ScreenshotFrameReceiver
    }

    private var entries: [CGDirectDisplayID: Entry] = [:]

    func start(
        displayID: CGDirectDisplayID,
        target: CaptureTarget
    ) async throws {
        guard entries[displayID] == nil else { return }

        let configuration = SCStreamConfiguration()
        configuration.width = target.configuration.width
        configuration.height = target.configuration.height
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.queueDepth = 2
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 15)

        let receiver = ScreenshotFrameReceiver()
        let stream = SCStream(
            filter: target.filter,
            configuration: configuration,
            delegate: nil
        )
        try stream.addStreamOutput(
            receiver,
            type: .screen,
            sampleHandlerQueue: receiver.queue
        )
        try await stream.startCapture()
        entries[displayID] = Entry(stream: stream, receiver: receiver)
    }

    func image(
        for displayID: CGDirectDisplayID,
        maximumAge: TimeInterval
    ) -> CGImage? {
        entries[displayID]?.receiver.image(maximumAge: maximumAge)
    }

    func stopAll() async {
        let currentEntries = entries.values
        entries.removeAll()
        for entry in currentEntries {
            try? await entry.stream.stopCapture()
        }
    }
}

private final class ScreenshotFrameReceiver: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(
        label: "com.local.PasteBox.screenshot-frame-cache",
        qos: .userInteractive
    )

    private static let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var pixelBuffer: CVPixelBuffer?
    private var receivedAt: Date?

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              sampleBuffer.isValid,
              CMSampleBufferDataIsReady(sampleBuffer),
              let imageBuffer = sampleBuffer.imageBuffer
        else { return }

        lock.lock()
        pixelBuffer = imageBuffer
        receivedAt = .now
        lock.unlock()
    }

    func image(maximumAge: TimeInterval) -> CGImage? {
        lock.lock()
        let buffer = pixelBuffer
        let date = receivedAt
        lock.unlock()

        guard let buffer,
              let date,
              Date().timeIntervalSince(date) <= maximumAge
        else { return nil }

        let image = CIImage(cvPixelBuffer: buffer)
        return Self.context.createCGImage(image, from: image.extent)
    }
}
