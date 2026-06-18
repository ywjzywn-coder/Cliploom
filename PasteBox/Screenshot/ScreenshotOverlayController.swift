import AppKit
import Foundation

final class ScreenshotPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
protocol ScreenshotOverlayControllerDelegate: AnyObject {
    func screenshotOverlayDidCancel(_ controller: ScreenshotOverlayController)
    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didFinishWith data: Data
    )
    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didRequestSave data: Data
    )
    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didRequestScan image: CGImage
    )
    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didRequestRecognizeText image: CGImage
    )
    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didRequestTranslate image: CGImage
    )
    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didRequestCopyRecognizedText text: String
    )
    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didRequestCopyTranslation text: String
    )
    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didRequestOpenBarcode result: BarcodeResult
    )
    func screenshotOverlay(
        _ controller: ScreenshotOverlayController,
        didRequestCopyColor value: String
    ) -> Bool
}

@MainActor
final class ScreenshotOverlayController: NSWindowController {
    weak var delegate: ScreenshotOverlayControllerDelegate?
    let session: ScreenshotSession
    private let overlayView: ScreenshotOverlayView
    private var resultPanel: NSPanel?
    private var ocrResultView: ScreenshotOCRPanelView?
    private var translationResultView: ScreenshotTranslationPanelView?
    private var barcodeResultView: ScreenshotBarcodePanelView?
    private var keyMonitor: Any?
    private var isCancelling = false

    init(session: ScreenshotSession) {
        self.session = session
        overlayView = ScreenshotOverlayView(frame: CGRect(origin: .zero, size: session.screen.frame.size))
        let panel = ScreenshotPanel(
            contentRect: session.screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: session.screen
        )
        panel.setFrame(session.screen.frame, display: false)
        panel.contentView = overlayView
        panel.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.screenSaverWindow))
        )
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.contentsScale = session.screen.backingScaleFactor
        super.init(window: panel)

        overlayView.session = session
        overlayView.onCancel = { [weak self] in
            self?.cancelSession()
        }
        overlayView.onFinish = { [weak self] in
            guard let self, let data = self.renderPNG() else { return }
            self.delegate?.screenshotOverlay(self, didFinishWith: data)
        }
        overlayView.onSave = { [weak self] in
            guard let self, let data = self.renderPNG() else { return }
            self.delegate?.screenshotOverlay(self, didRequestSave: data)
        }
        overlayView.onScan = { [weak self] in
            self?.requestBarcodeScan()
        }
        overlayView.onRecognizeText = { [weak self] in
            self?.requestTextRecognition()
        }
        overlayView.onTranslate = { [weak self] in
            self?.requestTranslation()
        }
        overlayView.onCopyColor = { [weak self] value in
            guard let self else { return false }
            return self.delegate?.screenshotOverlay(
                self,
                didRequestCopyColor: value
            ) ?? false
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(overlayView)
    }

    override func close() {
        removeKeyMonitor()
        window?.orderOut(nil)
        resultPanel?.orderOut(nil)
        resultPanel = nil
        ocrResultView = nil
        translationResultView = nil
        barcodeResultView = nil
    }

    func suspendForSystemPanel() {
        removeKeyMonitor()
        window?.orderOut(nil)
    }

    func restoreAfterSystemPanel() {
        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(overlayView)
    }

    func showRecognizedText(_ result: TextRecognitionResult) {
        let panel = ensureOCRResultPanel()
        if result.text.isEmpty {
            panel.showMessage(String(localized: "screenshot.ocr.empty"))
        } else {
            panel.showResult(result)
        }
    }

    func showTextRecognitionMessage(_ message: String) {
        ensureOCRResultPanel().showMessage(message)
    }

    func showTranslationSource(_ text: String) {
        let panel = ensureTranslationResultPanel()
        if text.isEmpty {
            panel.showMessage(String(localized: "screenshot.translate.empty"))
        } else {
            panel.translate(text)
        }
    }

    func showTranslationMessage(_ message: String) {
        ensureTranslationResultPanel().showMessage(message)
    }

    func showBarcodeResults(_ results: [BarcodeResult]) {
        guard let panel = barcodeResultView else { return }
        if results.isEmpty {
            panel.showUnsupportedResult(
                String(localized: "screenshot.scan.empty")
            )
        } else {
            panel.showResults(results)
        }
    }

    func showBarcodeMessage(_ message: String) {
        barcodeResultView?.showMessage(message)
    }

    private func requestTextRecognition() {
        guard let image = croppedImage() else { return }
        let panel = ensureOCRResultPanel()
        panel.showPreview(image)
        panel.showLoading()
        delegate?.screenshotOverlay(self, didRequestRecognizeText: image)
    }

    private func requestTranslation() {
        guard let image = croppedImage() else { return }
        let panel = ensureTranslationResultPanel()
        panel.showPreview(image)
        panel.showRecognizing()
        delegate?.screenshotOverlay(self, didRequestTranslate: image)
    }

    private func requestBarcodeScan() {
        guard let image = croppedImage() else { return }
        let panel = ensureBarcodeResultPanel(previewImage: image)
        panel.showPreview(image)
        panel.showLoading()
        delegate?.screenshotOverlay(self, didRequestScan: image)
    }

    private func ensureOCRResultPanel() -> ScreenshotOCRPanelView {
        if let ocrResultView {
            return ocrResultView
        }
        dismissResultPanel()
        let maximumSize = session.screen.visibleFrame
            .insetBy(dx: 24, dy: 24)
            .size
        let preferredSize = OCRPanelGeometry.preferredSize(
            selection: session.selection?.standardized.size ?? .zero,
            maximum: maximumSize
        )
        let view = ScreenshotOCRPanelView(
            frame: CGRect(origin: .zero, size: preferredSize)
        )
        view.onRetry = { [weak self] in
            self?.requestTextRecognition()
        }
        view.onCopy = { [weak self] text in
            guard let self else { return }
            self.delegate?.screenshotOverlay(
                self,
                didRequestCopyRecognizedText: text
            )
        }
        view.onClose = { [weak self] in
            guard let self else { return }
            self.delegate?.screenshotOverlayDidCancel(self)
        }
        presentResultPanel(contentView: view)
        ocrResultView = view
        return view
    }

    private func ensureBarcodeResultPanel(
        previewImage: CGImage
    ) -> ScreenshotBarcodePanelView {
        if let barcodeResultView {
            return barcodeResultView
        }
        dismissResultPanel()
        let maximumSize = session.screen.visibleFrame
            .insetBy(dx: 24, dy: 24)
            .size
        let preferredSize = BarcodePanelGeometry.preferredSize(
            imageSize: CGSize(
                width: previewImage.width,
                height: previewImage.height
            ),
            selectionSize: session.selection?.standardized.size ?? .zero,
            maximum: maximumSize
        )
        let view = ScreenshotBarcodePanelView(
            frame: CGRect(origin: .zero, size: preferredSize)
        )
        view.onRetry = { [weak self] in
            self?.requestBarcodeScan()
        }
        view.onOpen = { [weak self] result in
            guard let self else { return }
            self.delegate?.screenshotOverlay(
                self,
                didRequestOpenBarcode: result
            )
        }
        view.onClose = { [weak self] in
            guard let self else { return }
            self.delegate?.screenshotOverlayDidCancel(self)
        }
        presentResultPanel(contentView: view)
        barcodeResultView = view
        return view
    }

    private func ensureTranslationResultPanel() -> ScreenshotTranslationPanelView {
        if let translationResultView {
            return translationResultView
        }
        dismissResultPanel()
        let maximumSize = session.screen.visibleFrame
            .insetBy(dx: 24, dy: 24)
            .size
        let preferredSize = OCRPanelGeometry.preferredSize(
            selection: session.selection?.standardized.size ?? .zero,
            maximum: maximumSize
        )
        let view = ScreenshotTranslationPanelView(
            frame: CGRect(origin: .zero, size: preferredSize)
        )
        view.onRetry = { [weak self] in
            self?.requestTranslation()
        }
        view.onCopy = { [weak self] text in
            guard let self else { return }
            self.delegate?.screenshotOverlay(
                self,
                didRequestCopyTranslation: text
            )
        }
        view.onClose = { [weak self] in
            guard let self else { return }
            self.delegate?.screenshotOverlayDidCancel(self)
        }
        presentResultPanel(contentView: view)
        translationResultView = view
        return view
    }

    private func presentResultPanel(contentView: NSView) {
        window?.orderOut(nil)
        let size = contentView.frame.size
        let panel = ScreenshotPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.contentView = contentView
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        let visibleFrame = session.screen.visibleFrame.insetBy(dx: 24, dy: 24)
        panel.maxSize = visibleFrame.size
        panel.contentMaxSize = visibleFrame.size
        let fittedSize = NSSize(
            width: min(size.width, visibleFrame.width),
            height: min(size.height, visibleFrame.height)
        )
        panel.setContentSize(fittedSize)
        panel.setFrameOrigin(
            CGPoint(
                x: visibleFrame.midX - fittedSize.width / 2,
                y: visibleFrame.midY - fittedSize.height / 2
            )
        )
        resultPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self,
                  event.keyCode == 53,
                  self.window?.isVisible == true
                    || self.resultPanel?.isVisible == true
            else {
                return event
            }
            self.cancelSession()
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func cancelSession() {
        guard !isCancelling else { return }
        isCancelling = true
        delegate?.screenshotOverlayDidCancel(self)
    }

    private func dismissResultPanel() {
        resultPanel?.orderOut(nil)
        resultPanel = nil
        ocrResultView = nil
        translationResultView = nil
        barcodeResultView = nil
    }

    private func croppedImage() -> CGImage? {
        guard let selection = session.selection,
              selection.width >= 2,
              selection.height >= 2
        else { return nil }
        let pixelRect = session.mapper.pixelCropRect(for: selection)
        guard pixelRect.width >= 1, pixelRect.height >= 1 else { return nil }
        return session.image.cropping(to: pixelRect)
    }

    private func renderPNG(includeAnnotations: Bool = true) -> Data? {
        guard let selection = session.selection, selection.width >= 2, selection.height >= 2 else {
            return nil
        }
        return ScreenshotRenderer.pngData(
            image: session.image,
            selection: selection,
            viewSize: session.screen.frame.size,
            annotations: includeAnnotations ? session.annotations : []
        )
    }
}

private enum OverlayDragMode {
    case none
    case creating
    case moving(origin: CGRect)
    case resizing(handle: ResizeHandle, origin: CGRect)
    case annotation(start: CGPoint)
}

private enum ResizeHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

private enum ToolbarAction {
    case tool(ScreenshotTool)
    case color(NSColor)
    case width(CGFloat)
    case undo
    case save
    case cancel
    case done
    case recognizeText
    case translate
    case scan
}

private struct ToolbarHitRegion {
    let rect: CGRect
    let action: ToolbarAction
    let title: String
    let isEnabled: Bool
}

@MainActor
final class ScreenshotOverlayView: NSView {
    var session: ScreenshotSession! {
        didSet {
            let representation = NSBitmapImageRep(cgImage: session.image)
            representation.size = session.screen.frame.size
            let image = NSImage(size: session.screen.frame.size)
            image.addRepresentation(representation)
            image.cacheMode = .never
            backgroundImage = image
        }
    }
    var onCancel: (() -> Void)?
    var onFinish: (() -> Void)?
    var onSave: (() -> Void)?
    var onScan: (() -> Void)?
    var onRecognizeText: (() -> Void)?
    var onTranslate: (() -> Void)?
    var onCopyColor: ((String) -> Bool)?

    private var backgroundImage: NSImage?
    private var dragMode: OverlayDragMode = .none
    private var mouseDownPoint: CGPoint = .zero
    private var draftAnnotation: ScreenshotAnnotation?
    private var penPoints: [CGPoint] = []
    private var toolbarHitRegions: [ToolbarHitRegion] = []
    private var toolbarFrame: CGRect?
    private var hoveredToolbarTitle: String?
    private var pointerLocation: CGPoint?
    private(set) var isColorInspectorSuppressed = false
    private var trackingAreaReference: NSTrackingArea?
    private var copiedColorValue: String?
    private var colorCopyResetWorkItem: DispatchWorkItem?
    private lazy var pixelSampler = ScreenshotPixelSampler(image: session.image)

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .none
        backgroundImage?.draw(
            in: bounds,
            from: CGRect(origin: .zero, size: backgroundImage?.size ?? bounds.size),
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.none]
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let selection = session.selection else {
            if let hovered = session.hoveredWindow {
                drawDimmedOutside(hovered.frame, opacity: 0.34)
                drawSelectionBorder(hovered.frame, color: .systemBlue, handles: false)
                drawSizeLabel(for: hovered.frame)
            } else {
                NSColor.black.withAlphaComponent(0.28).setFill()
                bounds.fill()
            }
            drawColorInspectorIfNeeded()
            return
        }

        drawDimmedOutside(selection)
        drawAnnotations(session.annotations)
        if let draftAnnotation {
            drawAnnotations([draftAnnotation])
        }
        drawSelectionBorder(selection, color: .systemBlue, handles: true)
        drawSizeLabel(for: selection)
        drawToolbar(near: selection)
        drawColorInspectorIfNeeded()
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        pointerLocation = clamped(convert(event.locationInWindow, from: nil))
        isColorInspectorSuppressed = false
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        pointerLocation = nil
        isColorInspectorSuppressed = true
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pointerLocation = clamped(point)
        isColorInspectorSuppressed = false
        if session.selection == nil {
            session.hoveredWindow = session.window(at: point)
            needsDisplay = true
            return
        }

        let title = toolbarItem(at: point)?.title
        if hoveredToolbarTitle != title {
            hoveredToolbarTitle = title
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouseDownPoint = point
        pointerLocation = nil
        isColorInspectorSuppressed = true
        needsDisplay = true

        if event.clickCount == 2,
           session.selection?.contains(point) == true {
            onFinish?()
            return
        }

        if let item = toolbarItem(at: point) {
            if item.isEnabled {
                performToolbarAction(item.action)
            }
            return
        }

        if toolbarFrame?.contains(point) == true {
            return
        }

        guard let selection = session.selection else {
            dragMode = .creating
            return
        }

        if let handle = resizeHandle(at: point, selection: selection) {
            dragMode = .resizing(handle: handle, origin: selection)
            return
        }

        guard selection.contains(point) else {
            onCancel?()
            return
        }

        switch session.tool {
        case .pointer:
            dragMode = .moving(origin: selection)
        default:
            dragMode = .annotation(start: point)
            if session.tool == .pen {
                penPoints = [point]
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        cancelScreenshot()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        pointerLocation = nil
        isColorInspectorSuppressed = true
        switch dragMode {
        case .none:
            break
        case .creating:
            let rect = rectBetween(mouseDownPoint, point)
            if rect.width > 3 || rect.height > 3 {
                session.selection = rect
                session.hoveredWindow = nil
            }
        case let .moving(origin):
            let delta = CGPoint(x: point.x - mouseDownPoint.x, y: point.y - mouseDownPoint.y)
            session.selection = clamp(
                origin.offsetBy(dx: delta.x, dy: delta.y),
                to: bounds
            )
        case let .resizing(handle, origin):
            session.selection = resized(origin, handle: handle, to: point)
        case let .annotation(start):
            draftAnnotation = makeAnnotation(from: start, to: point)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        switch dragMode {
        case .creating:
            if let selection = session.selection,
               selection.width > 3,
               selection.height > 3 {
                session.selection = clamp(selection.standardized, to: bounds)
            } else if let hovered = session.hoveredWindow {
                session.selection = hovered.frame.intersection(bounds)
                session.hoveredWindow = nil
            }
        case .annotation:
            if let draftAnnotation {
                session.annotations.append(draftAnnotation)
            }
            draftAnnotation = nil
            penPoints.removeAll()
        default:
            break
        }
        dragMode = .none
        pointerLocation = nil
        isColorInspectorSuppressed = true
        if session.selection?.contains(point) == false, session.selection != nil {
            session.selection = clamp(session.selection!, to: bounds)
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            guard let pointerLocation,
                  copyColorValue(at: pointerLocation)
            else {
                NSSound.beep()
                return
            }
            return
        }

        switch event.keyCode {
        case 53:
            cancelScreenshot()
        case 36, 76:
            if session.selection != nil { onFinish?() }
        case 51:
            session.undo()
            needsDisplay = true
        default:
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "z" {
                session.undo()
                needsDisplay = true
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func cancelOperation(_ sender: Any?) {
        cancelScreenshot()
    }

    private func cancelScreenshot() {
        dragMode = .none
        draftAnnotation = nil
        penPoints.removeAll()
        onCancel?()
    }

    private func performToolbarAction(_ action: ToolbarAction) {
        switch action {
        case let .tool(tool):
            session.tool = tool
        case let .color(color):
            session.color = color
        case let .width(width):
            session.lineWidth = width
        case .undo:
            session.undo()
        case .save:
            onSave?()
        case .cancel:
            cancelScreenshot()
        case .done:
            onFinish?()
        case .recognizeText:
            onRecognizeText?()
        case .translate:
            onTranslate?()
        case .scan:
            onScan?()
        }
        needsDisplay = true
    }

    private func makeAnnotation(from start: CGPoint, to end: CGPoint) -> ScreenshotAnnotation? {
        guard let selection = session.selection else { return nil }
        let start = constrained(start, to: selection)
        let end = constrained(end, to: selection)
        switch session.tool {
        case .pointer:
            return nil
        case .rectangle:
            return .rectangle(
                rect: rectBetween(start, end),
                color: session.color,
                width: session.lineWidth
            )
        case .arrow:
            return .arrow(
                start: start,
                end: end,
                color: session.color,
                width: session.lineWidth
            )
        case .pen:
            penPoints.append(end)
            return .pen(
                points: penPoints,
                color: session.color,
                width: session.lineWidth
            )
        case .mosaic:
            return .mosaic(rect: rectBetween(start, end))
        }
    }

    private func drawDimmedOutside(_ selection: CGRect, opacity: CGFloat = 0.48) {
        let path = NSBezierPath(rect: bounds)
        path.appendRect(selection)
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(opacity).setFill()
        path.fill()
    }

    private func drawSelectionBorder(_ rect: CGRect, color: NSColor, handles: Bool) {
        let borderRect = rect.insetBy(dx: 1, dy: 1)

        NSColor.black.withAlphaComponent(0.82).setStroke()
        let contrastPath = NSBezierPath(rect: borderRect)
        contrastPath.lineWidth = 5
        contrastPath.stroke()

        color.setStroke()
        let path = NSBezierPath(rect: borderRect)
        path.lineWidth = 3
        path.stroke()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let innerPath = NSBezierPath(rect: rect.insetBy(dx: 2.5, dy: 2.5))
        innerPath.lineWidth = 1
        innerPath.stroke()

        guard handles else { return }
        for (_, handleRect) in handleRects(for: rect) {
            NSColor.black.withAlphaComponent(0.8).setStroke()
            let contrastHandle = NSBezierPath(rect: handleRect.insetBy(dx: -1, dy: -1))
            contrastHandle.lineWidth = 2
            contrastHandle.stroke()
            NSColor.white.setFill()
            handleRect.fill()
            NSColor.systemBlue.setStroke()
            let handlePath = NSBezierPath(rect: handleRect)
            handlePath.lineWidth = 1.5
            handlePath.stroke()
        }
    }

    private func drawAnnotations(_ annotations: [ScreenshotAnnotation]) {
        for annotation in annotations {
            switch annotation {
            case let .rectangle(rect, color, width):
                color.setStroke()
                let path = NSBezierPath(rect: rect)
                path.lineWidth = width
                path.stroke()
            case let .arrow(start, end, color, width):
                drawArrow(start: start, end: end, color: color, width: width)
            case let .pen(points, color, width):
                guard let first = points.first else { continue }
                color.setStroke()
                let path = NSBezierPath()
                path.move(to: first)
                points.dropFirst().forEach { path.line(to: $0) }
                path.lineWidth = width
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            case let .mosaic(rect):
                let path = NSBezierPath(rect: rect)
                NSColor.white.withAlphaComponent(0.22).setFill()
                path.fill()
                NSColor.white.withAlphaComponent(0.75).setStroke()
                path.lineWidth = 1
                let pattern: CGFloat = 8
                var x = rect.minX
                while x < rect.maxX {
                    let line = NSBezierPath()
                    line.move(to: CGPoint(x: x, y: rect.minY))
                    line.line(to: CGPoint(x: x, y: rect.maxY))
                    line.stroke()
                    x += pattern
                }
                var y = rect.minY
                while y < rect.maxY {
                    let line = NSBezierPath()
                    line.move(to: CGPoint(x: rect.minX, y: y))
                    line.line(to: CGPoint(x: rect.maxX, y: y))
                    line.stroke()
                    y += pattern
                }
            }
        }
    }

    private func drawArrow(start: CGPoint, end: CGPoint, color: NSColor, width: CGFloat) {
        color.setStroke()
        color.setFill()
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(12, width * 4)
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: CGPoint(
            x: end.x - length * cos(angle - .pi / 6),
            y: end.y - length * sin(angle - .pi / 6)
        ))
        head.line(to: CGPoint(
            x: end.x - length * cos(angle + .pi / 6),
            y: end.y - length * sin(angle + .pi / 6)
        ))
        head.close()
        head.fill()
    }

    private func drawSizeLabel(for rect: CGRect) {
        let pixelRect = session.mapper.pixelCropRect(for: rect)
        let value = "\(Int(pixelRect.width)) × \(Int(pixelRect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = value.size(withAttributes: attributes)
        let labelRect = CGRect(
            x: rect.minX,
            y: min(rect.maxY + 6, bounds.maxY - size.height - 10),
            width: size.width + 14,
            height: size.height + 8
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        value.draw(
            at: CGPoint(x: labelRect.minX + 7, y: labelRect.minY + 4),
            withAttributes: attributes
        )
    }

    private func drawColorInspectorIfNeeded() {
        guard case .none = dragMode,
              !isColorInspectorSuppressed,
              let pointerLocation,
              !toolbarHitRegions.contains(where: { $0.rect.contains(pointerLocation) }),
              let sample = pixelSampler.sample(
                at: pointerLocation,
                mapper: session.mapper
              )
        else {
            return
        }

        let panelSize = CGSize(width: 112, height: 36)
        let panelRect = colorInspectorFrame(
            near: pointerLocation,
            size: panelSize
        )
        NSColor.black.withAlphaComponent(0.88).setFill()
        NSBezierPath(
            roundedRect: panelRect,
            xRadius: 10,
            yRadius: 10
        ).fill()
        let wasJustCopied = copiedColorValue == sample.hex
        (wasJustCopied
            ? NSColor.systemGreen.withAlphaComponent(0.95)
            : NSColor.white.withAlphaComponent(0.34)
        ).setStroke()
        let panelBorder = NSBezierPath(
            roundedRect: panelRect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 10,
            yRadius: 10
        )
        panelBorder.lineWidth = wasJustCopied ? 1.5 : 1
        panelBorder.stroke()

        let swatchRect = CGRect(
            x: panelRect.minX + 8,
            y: panelRect.minY + 8,
            width: 20,
            height: 20
        )
        sample.color.setFill()
        NSBezierPath(roundedRect: swatchRect, xRadius: 4, yRadius: 4).fill()
        NSColor.white.withAlphaComponent(0.5).setStroke()
        NSBezierPath(roundedRect: swatchRect, xRadius: 4, yRadius: 4).stroke()

        let primaryAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        sample.hex.draw(
            at: CGPoint(x: swatchRect.maxX + 8, y: panelRect.minY + 10),
            withAttributes: primaryAttributes
        )
    }

    @discardableResult
    func copyColorValue(at point: CGPoint) -> Bool {
        guard let sample = pixelSampler.sample(
            at: point,
            mapper: session.mapper
        ), onCopyColor?(sample.hex) == true
        else {
            return false
        }

        copiedColorValue = sample.hex
        colorCopyResetWorkItem?.cancel()
        let copiedValue = sample.hex
        let workItem = DispatchWorkItem { [weak self] in
            guard self?.copiedColorValue == copiedValue else { return }
            self?.copiedColorValue = nil
            self?.needsDisplay = true
        }
        colorCopyResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1.2,
            execute: workItem
        )
        needsDisplay = true
        return true
    }

    private func colorInspectorFrame(
        near point: CGPoint,
        size: CGSize
    ) -> CGRect {
        let gap: CGFloat = 10
        var x = point.x + gap
        var y = point.y - size.height - gap
        if x + size.width > bounds.maxX - 8 {
            x = point.x - size.width - gap
        }
        if y < bounds.minY + 8 {
            y = point.y + gap
        }
        return CGRect(
            x: min(max(x, bounds.minX + 8), bounds.maxX - size.width - 8),
            y: min(max(y, bounds.minY + 8), bounds.maxY - size.height - 8),
            width: size.width,
            height: size.height
        )
    }

    private func drawToolbar(near selection: CGRect) {
        toolbarHitRegions.removeAll()
        let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .black, .white]
        let toolItems: [(ScreenshotTool, String)] = ScreenshotTool.allCases.map {
            ($0, $0.symbolName)
        }
        let showsColors = session.tool.supportsColor
        let showsLineWidths = session.tool.supportsLineWidth
        let buttonSize: CGFloat = 30
        let spacing: CGFloat = 4
        let toolWidth = CGFloat(toolItems.count) * (buttonSize + spacing)
        let colorWidth = showsColors ? CGFloat(colors.count) * 25 + 6 : 0
        let lineWidthWidth: CGFloat = showsLineWidths ? 96 : 0
        let actionWidth: CGFloat = 7 * (buttonSize + spacing)
        let totalWidth = 18 + toolWidth + colorWidth + lineWidthWidth + actionWidth
        let height: CGFloat = 48
        let x = min(max(selection.midX - totalWidth / 2, 8), bounds.width - totalWidth - 8)
        let preferredY = selection.minY - height - 9
        let y = preferredY >= 8 ? preferredY : min(selection.maxY + 9, bounds.height - height - 8)
        let toolbarRect = CGRect(x: x, y: y, width: totalWidth, height: height)
        toolbarFrame = toolbarRect

        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: toolbarRect, xRadius: 11, yRadius: 11).fill()
        NSColor.separatorColor.setStroke()
        let toolbarBorder = NSBezierPath(
            roundedRect: toolbarRect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 11,
            yRadius: 11
        )
        toolbarBorder.lineWidth = 1
        toolbarBorder.stroke()

        var cursorX = toolbarRect.minX + 9
        for (tool, symbol) in toolItems {
            let rect = CGRect(x: cursorX, y: toolbarRect.minY + 8, width: buttonSize, height: buttonSize)
            drawSymbolButton(
                symbol,
                rect: rect,
                selected: session.tool == tool,
                tint: .labelColor,
                enabled: true
            )
            toolbarHitRegions.append(
                ToolbarHitRegion(
                    rect: rect,
                    action: .tool(tool),
                    title: tool.localizedTitle,
                    isEnabled: true
                )
            )
            cursorX += buttonSize + spacing
        }

        if showsColors {
            cursorX += 3
            for (index, color) in colors.enumerated() {
                let rect = CGRect(x: cursorX, y: toolbarRect.minY + 13, width: 22, height: 22)
                color.setFill()
                let swatch = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
                swatch.fill()
                NSColor.labelColor.withAlphaComponent(0.35).setStroke()
                swatch.lineWidth = 1
                swatch.stroke()
                if color.isEqual(session.color) {
                    NSColor.controlAccentColor.setStroke()
                    let ring = NSBezierPath(ovalIn: rect)
                    ring.lineWidth = 2
                    ring.stroke()
                }
                toolbarHitRegions.append(
                    ToolbarHitRegion(
                        rect: rect,
                        action: .color(color),
                        title: colorTitle(at: index),
                        isEnabled: true
                    )
                )
                cursorX += 25
            }
        }

        if showsLineWidths {
            cursorX += 6
            let lineWidths = [2.0, 4.0, 8.0] as [CGFloat]
            for (index, width) in lineWidths.enumerated() {
                let rect = CGRect(x: cursorX, y: toolbarRect.minY + 8, width: 28, height: 32)
                if session.lineWidth == width {
                    NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
                }
                NSColor.labelColor.setFill()
                NSBezierPath(
                    ovalIn: CGRect(
                        x: rect.midX - width / 2,
                        y: rect.midY - width / 2,
                        width: width,
                        height: width
                    )
                ).fill()
                toolbarHitRegions.append(
                    ToolbarHitRegion(
                        rect: rect,
                        action: .width(width),
                        title: lineWidthTitle(at: index),
                        isEnabled: true
                    )
                )
                cursorX += 30
            }
        }

        let actions: [(ToolbarAction, String, NSColor, String, Bool)] = [
            (
                .recognizeText,
                "text.viewfinder",
                .labelColor,
                String(localized: "screenshot.action.ocr"),
                true
            ),
            (
                .translate,
                "translate",
                .labelColor,
                String(localized: "screenshot.action.translate"),
                true
            ),
            (
                .scan,
                "qrcode.viewfinder",
                .labelColor,
                String(localized: "screenshot.action.scan"),
                true
            ),
            (
                .undo,
                "arrow.uturn.backward",
                .labelColor,
                String(localized: "screenshot.action.undo"),
                !session.annotations.isEmpty
            ),
            (
                .save,
                "square.and.arrow.down",
                .labelColor,
                String(localized: "screenshot.action.save"),
                true
            ),
            (
                .cancel,
                "xmark",
                .systemRed,
                String(localized: "action.cancel"),
                true
            ),
            (
                .done,
                "checkmark",
                .systemGreen,
                String(localized: "screenshot.action.done"),
                true
            )
        ]
        cursorX += 3
        for (action, symbol, tint, title, isEnabled) in actions {
            let rect = CGRect(x: cursorX, y: toolbarRect.minY + 8, width: buttonSize, height: buttonSize)
            drawSymbolButton(
                symbol,
                rect: rect,
                selected: false,
                tint: tint,
                enabled: isEnabled
            )
            toolbarHitRegions.append(
                ToolbarHitRegion(
                    rect: rect,
                    action: action,
                    title: title,
                    isEnabled: isEnabled
                )
            )
            cursorX += buttonSize + spacing
        }

        if let hoveredToolbarTitle,
           let hoveredItem = toolbarHitRegions.first(
            where: { $0.title == hoveredToolbarTitle }
           ) {
            drawToolbarTooltip(
                hoveredToolbarTitle,
                near: hoveredItem.rect,
                toolbarRect: toolbarRect
            )
        }
    }

    private func toolbarItem(at point: CGPoint) -> ToolbarHitRegion? {
        guard let index = ScreenshotToolbarGeometry.hitIndex(
            at: point,
            in: toolbarHitRegions.map(\.rect)
        ) else {
            return nil
        }
        return toolbarHitRegions[index]
    }

    private func drawSymbolButton(
        _ symbol: String,
        rect: CGRect,
        selected: Bool,
        tint: NSColor,
        enabled: Bool
    ) {
        if selected {
            NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        }
        guard let image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        ) else { return }
        let configuration = NSImage.SymbolConfiguration(
            pointSize: 15,
            weight: .medium
        )
        let configuredImage = image.withSymbolConfiguration(configuration) ?? image
        let tintedImage = configuredImage.tinted(
            with: enabled ? tint : tint.withAlphaComponent(0.28)
        )
        let iconContainer = rect.insetBy(dx: 7, dy: 7)
        let iconRect = ScreenshotToolbarGeometry.aspectFitRect(
            contentSize: tintedImage.size,
            in: iconContainer
        ).integral
        tintedImage.draw(
            in: iconRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func drawToolbarTooltip(
        _ value: String,
        near itemRect: CGRect,
        toolbarRect: CGRect
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = value.size(withAttributes: attributes)
        let width = textSize.width + 14
        let height = textSize.height + 8
        let x = min(max(itemRect.midX - width / 2, 8), bounds.maxX - width - 8)
        let belowY = toolbarRect.minY - height - 5
        let y = belowY >= 8 ? belowY : toolbarRect.maxY + 5
        let rect = CGRect(x: x, y: y, width: width, height: height)

        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        value.draw(
            at: CGPoint(x: rect.minX + 7, y: rect.minY + 4),
            withAttributes: attributes
        )
    }

    private func colorTitle(at index: Int) -> String {
        let keys = [
            "screenshot.color.red",
            "screenshot.color.yellow",
            "screenshot.color.green",
            "screenshot.color.blue",
            "screenshot.color.black",
            "screenshot.color.white"
        ]
        return String(localized: String.LocalizationValue(keys[index]))
    }

    private func lineWidthTitle(at index: Int) -> String {
        let keys = [
            "screenshot.width.thin",
            "screenshot.width.medium",
            "screenshot.width.thick"
        ]
        return String(localized: String.LocalizationValue(keys[index]))
    }

    private func handleRects(for selection: CGRect) -> [(ResizeHandle, CGRect)] {
        let size: CGFloat = 8
        let points: [(ResizeHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: selection.minX, y: selection.maxY)),
            (.top, CGPoint(x: selection.midX, y: selection.maxY)),
            (.topRight, CGPoint(x: selection.maxX, y: selection.maxY)),
            (.right, CGPoint(x: selection.maxX, y: selection.midY)),
            (.bottomRight, CGPoint(x: selection.maxX, y: selection.minY)),
            (.bottom, CGPoint(x: selection.midX, y: selection.minY)),
            (.bottomLeft, CGPoint(x: selection.minX, y: selection.minY)),
            (.left, CGPoint(x: selection.minX, y: selection.midY))
        ]
        return points.map {
            (
                $0.0,
                CGRect(
                    x: $0.1.x - size / 2,
                    y: $0.1.y - size / 2,
                    width: size,
                    height: size
                )
            )
        }
    }

    private func resizeHandle(at point: CGPoint, selection: CGRect) -> ResizeHandle? {
        handleRects(for: selection)
            .first { $0.1.insetBy(dx: -4, dy: -4).contains(point) }?
            .0
    }

    private func resized(_ origin: CGRect, handle: ResizeHandle, to point: CGPoint) -> CGRect {
        var minX = origin.minX
        var maxX = origin.maxX
        var minY = origin.minY
        var maxY = origin.maxY
        switch handle {
        case .topLeft:
            minX = point.x
            maxY = point.y
        case .top:
            maxY = point.y
        case .topRight:
            maxX = point.x
            maxY = point.y
        case .right:
            maxX = point.x
        case .bottomRight:
            maxX = point.x
            minY = point.y
        case .bottom:
            minY = point.y
        case .bottomLeft:
            minX = point.x
            minY = point.y
        case .left:
            minX = point.x
        }
        let rect = CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: max(abs(maxX - minX), 8),
            height: max(abs(maxY - minY), 8)
        )
        return clamp(rect, to: bounds)
    }

    private func rectBetween(_ first: CGPoint, _ second: CGPoint) -> CGRect {
        CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func constrained(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func clamp(_ rect: CGRect, to container: CGRect) -> CGRect {
        var value = rect.standardized
        value.size.width = min(value.width, container.width)
        value.size.height = min(value.height, container.height)
        value.origin.x = min(max(value.minX, container.minX), container.maxX - value.width)
        value.origin.y = min(max(value.minY, container.minY), container.maxY - value.height)
        return value
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let source = self
        let result = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        result.isTemplate = false
        return result
    }
}
