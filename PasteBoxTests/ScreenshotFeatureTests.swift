import AppKit
import Carbon
import CoreImage
import VisionKit
import XCTest
@testable import PasteBox

final class ScreenshotCoordinateMapperTests: XCTestCase {
    func testRetinaCropConvertsBottomLeftPointsToTopLeftPixels() {
        let mapper = ScreenshotCoordinateMapper(
            viewSize: CGSize(width: 1000, height: 800),
            pixelSize: CGSize(width: 2000, height: 1600)
        )

        XCTAssertEqual(
            mapper.pixelCropRect(for: CGRect(x: 100, y: 150, width: 300, height: 200)),
            CGRect(x: 200, y: 900, width: 600, height: 400)
        )
    }

    func testWindowFrameConversionSupportsNegativeDisplayCoordinates() {
        let local = ScreenshotCoordinateMapper.localWindowFrame(
            globalFrame: CGRect(x: -1350, y: 120, width: 600, height: 500),
            displayBounds: CGRect(x: -1440, y: 0, width: 1440, height: 900),
            screenSize: CGSize(width: 1440, height: 900)
        )

        XCTAssertEqual(local, CGRect(x: 90, y: 280, width: 600, height: 500))
    }

    func testPixelPointUsesRetinaScaleAndTopLeftImageCoordinates() {
        let mapper = ScreenshotCoordinateMapper(
            viewSize: CGSize(width: 100, height: 50),
            pixelSize: CGSize(width: 200, height: 100)
        )

        XCTAssertEqual(
            mapper.pixelPoint(for: CGPoint(x: 12.5, y: 40)),
            CGPoint(x: 25, y: 20)
        )
        XCTAssertEqual(
            mapper.pixelPoint(for: CGPoint(x: 100, y: 0)),
            CGPoint(x: 199, y: 99)
        )
    }

    func testCropRectAtScaledDisplayEdgeStaysInsidePixelBounds() {
        let mapper = ScreenshotCoordinateMapper(
            viewSize: CGSize(width: 1728, height: 1117),
            pixelSize: CGSize(width: 3456, height: 2234)
        )

        let cropRect = mapper.pixelCropRect(
            for: CGRect(x: 1624.3, y: 1042.6, width: 103.7, height: 74.4)
        )

        XCTAssertGreaterThanOrEqual(cropRect.minX, 0)
        XCTAssertGreaterThanOrEqual(cropRect.minY, 0)
        XCTAssertLessThanOrEqual(cropRect.maxX, 3456)
        XCTAssertLessThanOrEqual(cropRect.maxY, 2234)
        XCTAssertGreaterThan(cropRect.width, 0)
        XCTAssertGreaterThan(cropRect.height, 0)
    }
}

final class ScreenshotCaptureGeometryTests: XCTestCase {
    func testUsesPhysicalDisplayModePixelsForScaledDisplay() {
        let size = ScreenshotCaptureGeometry.orientedPixelSize(
            logicalSize: CGSize(width: 1920, height: 1080),
            modePixelSize: CGSize(width: 3840, height: 2160)
        )

        XCTAssertEqual(size, CGSize(width: 3840, height: 2160))
    }

    func testRotatesPhysicalPixelSizeToMatchDisplayOrientation() {
        let size = ScreenshotCaptureGeometry.orientedPixelSize(
            logicalSize: CGSize(width: 1080, height: 1920),
            modePixelSize: CGSize(width: 3840, height: 2160)
        )

        XCTAssertEqual(size, CGSize(width: 2160, height: 3840))
    }

    func testFallsBackToLogicalSizeWithoutDisplayMode() {
        let size = ScreenshotCaptureGeometry.orientedPixelSize(
            logicalSize: CGSize(width: 2560, height: 1440),
            modePixelSize: nil
        )

        XCTAssertEqual(size, CGSize(width: 2560, height: 1440))
    }
}

final class ScreenshotTranslationDirectionTests: XCTestCase {
    func testSimplifiedChineseDefaultsToEnglish() {
        XCTAssertEqual(
            ScreenshotTranslationDirection.targetIdentifier(
                for: "你好，世界",
                dominantLanguage: .simplifiedChinese
            ),
            "en"
        )
    }

    func testTraditionalChineseDefaultsToEnglish() {
        XCTAssertEqual(
            ScreenshotTranslationDirection.targetIdentifier(
                for: "你好，世界",
                dominantLanguage: .traditionalChinese
            ),
            "en"
        )
    }

    func testOtherLanguagesDefaultToSimplifiedChinese() {
        XCTAssertEqual(
            ScreenshotTranslationDirection.targetIdentifier(
                for: "Hello world",
                dominantLanguage: .english
            ),
            "zh-CN"
        )
    }
}

@MainActor
final class ScreenshotTranslationPanelTests: XCTestCase {
    func testRepeatedTranslationsRefreshOrReplaceTheConfiguration() throws {
        let model = ScreenshotTranslationModel()

        model.translate("Hello")
        let firstConfiguration = try XCTUnwrap(model.configuration)

        model.translate("Goodbye")
        let refreshedConfiguration = try XCTUnwrap(model.configuration)
        XCTAssertNotEqual(firstConfiguration, refreshedConfiguration)
        XCTAssertEqual(model.sourceText, "Goodbye")

        model.translate("你好")
        let switchedConfiguration = try XCTUnwrap(model.configuration)
        XCTAssertNotEqual(refreshedConfiguration, switchedConfiguration)
        XCTAssertEqual(model.sourceText, "你好")
    }

    func testTranslationPanelCanPrepareRepeatedRequests() throws {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 320,
                pixelsHigh: 180,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let image = try XCTUnwrap(bitmap.cgImage)
        let panelView = ScreenshotTranslationPanelView(
            frame: CGRect(x: 0, y: 0, width: 960, height: 640)
        )

        panelView.showPreview(image)
        panelView.showRecognizing()
        panelView.showMessage("暂时无法识别")
        panelView.showPreview(image)

        XCTAssertEqual(panelView.frame.size, NSSize(width: 960, height: 640))
    }
}

@MainActor
final class ScreenshotOCRPanelTests: XCTestCase {
    func testPanelAcceptsFallbackRecognitionResult() throws {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 320,
                pixelsHigh: 180,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let image = try XCTUnwrap(bitmap.cgImage)
        let panel = ScreenshotOCRPanelView(
            frame: CGRect(x: 0, y: 0, width: 960, height: 640)
        )

        panel.showPreview(image)
        panel.showLoading()
        panel.showResult(
            TextRecognitionResult(
                text: "Cliploom OCR",
                imageAnalysis: nil
            )
        )
        panel.layoutSubtreeIfNeeded()

        XCTAssertTrue(allText(in: panel).contains("Cliploom OCR"))
    }

    func testPreviewUsesLogicalDisplaySizeOnScaledDisplays() throws {
        let image = try makeSolidImage(width: 3840, height: 2160)
        let panel = ScreenshotOCRPanelView(
            frame: CGRect(x: 0, y: 0, width: 960, height: 640)
        )

        panel.showPreview(
            image,
            displaySize: CGSize(width: 1920, height: 1080)
        )

        let sizes = imageSizes(in: panel)
        XCTAssertTrue(sizes.contains(NSSize(width: 1920, height: 1080)))
        XCTAssertFalse(sizes.contains(NSSize(width: 3840, height: 2160)))
    }

    private func allText(in view: NSView) -> [String] {
        let text: [String]
        if let textView = view as? NSTextView {
            text = [textView.string]
        } else if let textField = view as? NSTextField {
            text = [textField.stringValue]
        } else {
            text = []
        }
        return text + view.subviews.flatMap(allText)
    }

    private func imageSizes(in view: NSView) -> [NSSize] {
        let imageSize = (view as? NSImageView)?.image.map { [$0.size] } ?? []
        return imageSize + view.subviews.flatMap(imageSizes)
    }

    private func makeSolidImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}

final class ScreenshotPixelSamplerTests: XCTestCase {
    func testSamplerReadsTopAndBottomColorsAndFormatsValues() throws {
        let image = try makeTwoToneImage()
        let sampler = ScreenshotPixelSampler(image: image)
        let mapper = ScreenshotCoordinateMapper(
            viewSize: CGSize(width: 2, height: 2),
            pixelSize: CGSize(width: 2, height: 2)
        )

        let top = try XCTUnwrap(
            sampler.sample(at: CGPoint(x: 0.5, y: 1.5), mapper: mapper)
        )
        let bottom = try XCTUnwrap(
            sampler.sample(at: CGPoint(x: 0.5, y: 0.5), mapper: mapper)
        )

        XCTAssertEqual(top.hex, "#0000FF")
        XCTAssertEqual(top.rgb, "RGB 0, 0, 255")
        XCTAssertEqual(bottom.hex, "#FF0000")
        XCTAssertEqual(bottom.rgb, "RGB 255, 0, 0")
    }

    func testMagnifierCropStaysInsideImageAtEdges() throws {
        let image = try makeTwoToneImage(width: 20, height: 12)
        let sampler = ScreenshotPixelSampler(image: image)

        let crop = try XCTUnwrap(
            sampler.magnifierCrop(
                centeredAt: CGPoint(x: 19, y: 11),
                diameter: 11
            )
        )

        XCTAssertEqual(crop.rect, CGRect(x: 9, y: 1, width: 11, height: 11))
        XCTAssertEqual(crop.image.width, 11)
        XCTAssertEqual(crop.image.height, 11)
    }

    private func makeTwoToneImage(
        width: Int = 2,
        height: Int = 2
    ) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(
            CGRect(
                x: 0,
                y: height / 2,
                width: width,
                height: height - height / 2
            )
        )
        return try XCTUnwrap(context.makeImage())
    }
}

final class ScreenshotToolbarGeometryTests: XCTestCase {
    func testCenteredSquareDoesNotStretchInWideContainer() {
        let result = ScreenshotToolbarGeometry.centeredSquare(
            in: CGRect(x: 10, y: 20, width: 40, height: 18)
        )

        XCTAssertEqual(result.width, 18, accuracy: 0.001)
        XCTAssertEqual(result.height, 18, accuracy: 0.001)
        XCTAssertEqual(result.midX, 30, accuracy: 0.001)
        XCTAssertEqual(result.midY, 29, accuracy: 0.001)
    }

    func testCenteredSquareDoesNotStretchInTallContainer() {
        let result = ScreenshotToolbarGeometry.centeredSquare(
            in: CGRect(x: 10, y: 20, width: 18, height: 40)
        )

        XCTAssertEqual(result.width, 18, accuracy: 0.001)
        XCTAssertEqual(result.height, 18, accuracy: 0.001)
        XCTAssertEqual(result.midX, 19, accuracy: 0.001)
        XCTAssertEqual(result.midY, 40, accuracy: 0.001)
    }

    func testAspectFitKeepsWideSymbolProportions() {
        let result = ScreenshotToolbarGeometry.aspectFitRect(
            contentSize: CGSize(width: 19, height: 14),
            in: CGRect(x: 10, y: 20, width: 18, height: 18)
        )

        XCTAssertEqual(result.width, 18, accuracy: 0.001)
        XCTAssertEqual(result.height, 18 * 14 / 19, accuracy: 0.001)
        XCTAssertEqual(result.midX, 19, accuracy: 0.001)
        XCTAssertEqual(result.midY, 29, accuracy: 0.001)
    }

    func testAspectFitKeepsTallSymbolProportions() {
        let result = ScreenshotToolbarGeometry.aspectFitRect(
            contentSize: CGSize(width: 11, height: 14),
            in: CGRect(x: 0, y: 0, width: 18, height: 18)
        )

        XCTAssertEqual(result.width, 18 * 11 / 14, accuracy: 0.001)
        XCTAssertEqual(result.height, 18, accuracy: 0.001)
    }

    func testHitTestingAcceptsDoneButtonEdgePadding() {
        let buttons = [
            CGRect(x: 10, y: 8, width: 32, height: 32),
            CGRect(x: 47, y: 8, width: 32, height: 32)
        ]

        XCTAssertEqual(
            ScreenshotToolbarGeometry.hitIndex(
                at: CGPoint(x: 81, y: 24),
                in: buttons
            ),
            1
        )
    }

    func testHitTestingChoosesNearestButtonInSpacing() {
        let buttons = [
            CGRect(x: 10, y: 8, width: 32, height: 32),
            CGRect(x: 47, y: 8, width: 32, height: 32)
        ]

        XCTAssertEqual(
            ScreenshotToolbarGeometry.hitIndex(
                at: CGPoint(x: 45, y: 24),
                in: buttons
            ),
            1
        )
    }
}

@MainActor
final class ScreenshotOverlayInputTests: XCTestCase {
    @MainActor
    func testSystemPanelSuspensionHidesAndRestoresOverlay() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let controller = ScreenshotOverlayController(
            session: ScreenshotSession(
                image: try makeSolidImage(color: .systemBlue),
                screen: screen,
                windows: []
            )
        )

        controller.show()
        XCTAssertTrue(controller.window?.isVisible ?? false)

        controller.suspendForSystemPanel()
        XCTAssertFalse(controller.window?.isVisible ?? true)

        controller.restoreAfterSystemPanel()
        XCTAssertTrue(controller.window?.isVisible ?? false)

        controller.close()
    }

    func testScreenshotPanelCanReceiveKeyboardFocus() {
        let panel = ScreenshotPanel(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
    }

    func testRightClickCancelsScreenshot() throws {
        let view = ScreenshotOverlayView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        var cancellationCount = 0
        view.onCancel = { cancellationCount += 1 }
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: CGPoint(x: 120, y: 80),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )

        view.rightMouseDown(with: event)

        XCTAssertEqual(cancellationCount, 1)
    }

    func testEscapeCancelsScreenshot() throws {
        let view = ScreenshotOverlayView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        var cancellationCount = 0
        view.onCancel = { cancellationCount += 1 }
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\u{1B}",
                charactersIgnoringModifiers: "\u{1B}",
                isARepeat: false,
                keyCode: 53
            )
        )

        view.keyDown(with: event)

        XCTAssertEqual(cancellationCount, 1)
    }

    func testCancelOperationCancelsScreenshot() {
        let view = ScreenshotOverlayView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        var cancellationCount = 0
        view.onCancel = { cancellationCount += 1 }

        view.cancelOperation(nil)

        XCTAssertEqual(cancellationCount, 1)
    }

    func testDoneButtonWorksBeforeToolbarHitRegionsAreDrawn() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let session = ScreenshotSession(
            image: try makeSolidImage(color: .systemBlue),
            screen: screen,
            windows: []
        )
        session.selection = CGRect(x: 100, y: 250, width: 240, height: 160)
        let view = ScreenshotOverlayView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        view.session = session

        var finishCount = 0
        var cancellationCount = 0
        view.onFinish = {
            finishCount += 1
            return true
        }
        view.onCancel = { cancellationCount += 1 }

        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: CGPoint(x: 409, y: 216),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )

        view.mouseDown(with: event)

        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(cancellationCount, 0)
    }

    func testDoneButtonAcceptsEdgeClicks() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let session = ScreenshotSession(
            image: try makeSolidImage(color: .systemBlue),
            screen: screen,
            windows: []
        )
        session.selection = CGRect(x: 100, y: 250, width: 240, height: 160)
        let view = ScreenshotOverlayView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        view.session = session

        var finishCount = 0
        view.onFinish = {
            finishCount += 1
            return true
        }

        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: CGPoint(x: 430, y: 216),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )

        view.mouseDown(with: event)

        XCTAssertEqual(finishCount, 1)
    }

    func testToolbarBlankNearDoneButtonStillFinishes() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let session = ScreenshotSession(
            image: try makeSolidImage(color: .systemBlue),
            screen: screen,
            windows: []
        )
        session.selection = CGRect(x: 100, y: 250, width: 240, height: 160)
        let view = ScreenshotOverlayView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        view.session = session

        var finishCount = 0
        var cancellationCount = 0
        view.onFinish = {
            finishCount += 1
            return true
        }
        view.onCancel = { cancellationCount += 1 }

        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: CGPoint(x: 433, y: 216),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )

        view.mouseDown(with: event)

        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(cancellationCount, 0)
    }

    func testDoneButtonCanRetryAfterFailedFinish() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let session = ScreenshotSession(
            image: try makeSolidImage(color: .systemBlue),
            screen: screen,
            windows: []
        )
        session.selection = CGRect(x: 100, y: 250, width: 240, height: 160)
        let view = ScreenshotOverlayView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        view.session = session

        var finishCount = 0
        view.onFinish = {
            finishCount += 1
            return finishCount > 1
        }

        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: CGPoint(x: 430, y: 216),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )

        view.mouseDown(with: event)
        view.mouseDown(with: event)

        XCTAssertEqual(finishCount, 2)
    }

    func testColorInspectorCopiesHoveredHexValue() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let image = try makeSolidImage(
            color: NSColor(
                deviceRed: 0,
                green: 1,
                blue: 0,
                alpha: 1
            )
        )
        let session = ScreenshotSession(
            image: image,
            screen: screen,
            windows: []
        )
        let view = ScreenshotOverlayView(
            frame: CGRect(origin: .zero, size: screen.frame.size)
        )
        view.session = session
        var copiedValue: String?
        view.onCopyColor = { value in
            copiedValue = value
            return true
        }

        XCTAssertTrue(
            view.copyColorValue(
                at: CGPoint(
                    x: screen.frame.width / 2,
                    y: screen.frame.height / 2
                )
            )
        )
        XCTAssertEqual(copiedValue, "#00FF00")
    }

    func testColorInspectorStaysHiddenAfterMouseSelectionUntilPointerMoves() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let session = ScreenshotSession(
            image: try makeSolidImage(color: .systemBlue),
            screen: screen,
            windows: []
        )
        let view = ScreenshotOverlayView(
            frame: CGRect(origin: .zero, size: screen.frame.size)
        )
        view.session = session

        view.mouseMoved(with: try mouseEvent(type: .mouseMoved))
        XCTAssertFalse(view.isColorInspectorSuppressed)

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp))
        XCTAssertTrue(view.isColorInspectorSuppressed)

        view.mouseMoved(with: try mouseEvent(type: .mouseMoved))
        XCTAssertFalse(view.isColorInspectorSuppressed)
    }

    private func mouseEvent(type: NSEvent.EventType) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: CGPoint(x: 120, y: 120),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            )
        )
    }

    private func makeSolidImage(color: NSColor) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 4,
                height: 4,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return try XCTUnwrap(context.makeImage())
    }
}

final class OCRPanelGeometryTests: XCTestCase {
    func testSmallSelectionProducesCompactPanel() {
        let size = OCRPanelGeometry.preferredSize(
            selection: CGSize(width: 140, height: 80),
            maximum: CGSize(width: 1400, height: 800)
        )

        XCTAssertEqual(size, CGSize(width: 712, height: 420))
    }

    func testPanelGrowsWithSelection() {
        let size = OCRPanelGeometry.preferredSize(
            selection: CGSize(width: 620, height: 420),
            maximum: CGSize(width: 1400, height: 800)
        )

        XCTAssertEqual(size.width, 1014.4, accuracy: 0.001)
        XCTAssertEqual(size.height, 536, accuracy: 0.001)
    }

    func testPanelNeverExceedsVisibleScreen() {
        let size = OCRPanelGeometry.preferredSize(
            selection: CGSize(width: 1800, height: 1200),
            maximum: CGSize(width: 1200, height: 720)
        )

        XCTAssertEqual(size.width, 1032, accuracy: 0.001)
        XCTAssertEqual(size.height, 590.4, accuracy: 0.001)
        XCTAssertLessThan(size.width, 1200)
        XCTAssertLessThan(size.height, 720)
    }
}

final class ScreenshotPreviewGeometryTests: XCTestCase {
    func testAspectFitRectCentersWideImageVertically() {
        let rect = ScreenshotPreviewGeometry.aspectFitRect(
            contentSize: CGSize(width: 1600, height: 900),
            in: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(rect, CGRect(x: 0, y: 75, width: 800, height: 450))
    }

    func testAspectFitRectCentersTallImageHorizontally() {
        let rect = ScreenshotPreviewGeometry.aspectFitRect(
            contentSize: CGSize(width: 900, height: 1600),
            in: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(rect, CGRect(x: 231.25, y: 0, width: 337.5, height: 600))
    }

    func testNormalizedBarcodeCenterUsesVisionBottomLeftCoordinates() {
        let center = ScreenshotPreviewGeometry.center(
            of: CGRect(x: 0.2, y: 0.6, width: 0.2, height: 0.2),
            in: CGRect(x: 100, y: 50, width: 500, height: 300)
        )

        XCTAssertEqual(center.x, 250, accuracy: 0.001)
        XCTAssertEqual(center.y, 260, accuracy: 0.001)
    }

    func testAspectFitUnitRectUsesVisionKitUnitCoordinates() {
        let rect = ScreenshotPreviewGeometry.aspectFitUnitRect(
            contentSize: CGSize(width: 1600, height: 900),
            in: CGRect(x: 20, y: 40, width: 800, height: 800)
        )

        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 0.21875, accuracy: 0.001)
        XCTAssertEqual(rect.width, 1, accuracy: 0.001)
        XCTAssertEqual(rect.height, 0.5625, accuracy: 0.001)
    }
}

final class BarcodePanelGeometryTests: XCTestCase {
    func testWideSelectionProducesWidePreviewWindow() {
        let size = BarcodePanelGeometry.preferredSize(
            imageSize: CGSize(width: 1600, height: 900),
            selectionSize: CGSize(width: 700, height: 394),
            maximum: CGSize(width: 1400, height: 800)
        )

        XCTAssertEqual(size.width, 728)
        XCTAssertEqual(size.height, 501.75)
    }

    func testTallImageNeverExceedsVisibleScreen() {
        let size = BarcodePanelGeometry.preferredSize(
            imageSize: CGSize(width: 900, height: 2400),
            selectionSize: CGSize(width: 220, height: 700),
            maximum: CGSize(width: 1100, height: 720)
        )

        XCTAssertEqual(size.width, 420)
        XCTAssertEqual(size.height, 561.6, accuracy: 0.001)
        XCTAssertLessThan(size.height, 720)
    }

    func testLargeBarcodeSelectionDoesNotBecomeFullScreen() {
        let size = BarcodePanelGeometry.preferredSize(
            imageSize: CGSize(width: 2400, height: 1400),
            selectionSize: CGSize(width: 1800, height: 1100),
            maximum: CGSize(width: 1440, height: 900)
        )

        XCTAssertEqual(size.width, 960)
        XCTAssertLessThan(size.height, 900)
    }
}

final class ScreenshotRendererTests: XCTestCase {
    func testRendererProducesExpectedPixelDimensionsWithAnnotations() throws {
        let source = try makeImage(width: 400, height: 300)
        let data = try XCTUnwrap(
            ScreenshotRenderer.pngData(
                image: source,
                selection: CGRect(x: 25, y: 30, width: 100, height: 80),
                viewSize: CGSize(width: 200, height: 150),
                annotations: [
                    .rectangle(
                        rect: CGRect(x: 40, y: 45, width: 40, height: 30),
                        color: .systemRed,
                        width: 3
                    ),
                    .mosaic(rect: CGRect(x: 80, y: 60, width: 25, height: 20))
                ]
            )
        )
        let representation = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(representation.pixelsWide, 200)
        XCTAssertEqual(representation.pixelsHigh, 160)
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}

final class BarcodeScannerTests: XCTestCase {
    func testScannerRecognizesQRCode() async throws {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data("https://example.com/pastebox".utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        let output = try XCTUnwrap(filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)))
        let context = CIContext()
        let cgImage = try XCTUnwrap(context.createCGImage(output, from: output.extent))
        let representation = NSBitmapImageRep(cgImage: cgImage)
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))

        let directResults = try await BarcodeScanner.scan(cgImage: cgImage)
        let results = try await BarcodeScanner.scan(pngData: data)

        XCTAssertTrue(directResults.contains { $0.payload == "https://example.com/pastebox" })
        XCTAssertTrue(results.contains { $0.payload == "https://example.com/pastebox" })
        XCTAssertEqual(
            directResults.first { $0.payload == "https://example.com/pastebox" }?.webURL?.host,
            "example.com"
        )
    }

    func testDeduplicationKeepsSameLinkAtDifferentPositions() {
        let first = BarcodeResult(
            symbology: "QR",
            payload: "https://example.com",
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        )
        let nearDuplicate = BarcodeResult(
            symbology: "QR",
            payload: "https://example.com",
            boundingBox: CGRect(x: 0.102, y: 0.099, width: 0.2, height: 0.2)
        )
        let secondPosition = BarcodeResult(
            symbology: "QR",
            payload: "https://example.com",
            boundingBox: CGRect(x: 0.65, y: 0.6, width: 0.2, height: 0.2)
        )

        let results = BarcodeScanner.deduplicated([
            first,
            nearDuplicate,
            secondPosition
        ])

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains { $0.boundingBox == first.boundingBox })
        XCTAssertTrue(results.contains { $0.boundingBox == secondPosition.boundingBox })
    }

    func testScannerRecognizesMultipleQRCodesInOneImage() async throws {
        let canvasSize = CGSize(width: 1000, height: 700)
        let placements: [(String, CGRect)] = [
            ("https://example.com/one", CGRect(x: 40, y: 390, width: 240, height: 240)),
            ("https://example.com/two", CGRect(x: 380, y: 380, width: 180, height: 180)),
            ("https://example.com/three", CGRect(x: 690, y: 360, width: 260, height: 260)),
            ("plain text payload", CGRect(x: 330, y: 40, width: 220, height: 220))
        ]
        let image = try makeQRCodeCanvas(
            size: canvasSize,
            placements: placements
        )

        let results = try await BarcodeScanner.scan(cgImage: image)

        XCTAssertEqual(results.count, placements.count)
        for (payload, _) in placements {
            XCTAssertTrue(
                results.contains { $0.payload == payload },
                "Missing barcode payload: \(payload)"
            )
        }
    }

    func testUnsafeAndNonWebPayloadsDoNotProduceLinks() {
        XCTAssertNil(
            BarcodeResult(
                symbology: "QR",
                payload: "javascript:alert(1)",
                boundingBox: .zero
            ).webURL
        )
        XCTAssertNil(
            BarcodeResult(
                symbology: "QR",
                payload: "plain text",
                boundingBox: .zero
            ).webURL
        )
    }

    private func makeQRCodeCanvas(
        size: CGSize,
        placements: [(String, CGRect)]
    ) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        let ciContext = CIContext()
        for (payload, rect) in placements {
            let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
            filter.setValue(Data(payload.utf8), forKey: "inputMessage")
            filter.setValue("H", forKey: "inputCorrectionLevel")
            let output = try XCTUnwrap(filter.outputImage)
            let qrImage = try XCTUnwrap(
                ciContext.createCGImage(output, from: output.extent)
            )
            context.interpolationQuality = .none
            context.draw(qrImage, in: rect)
        }
        return try XCTUnwrap(context.makeImage())
    }
}

@MainActor
final class BarcodePanelTests: XCTestCase {
    func testPanelReplacesOldLinkButtonsAndHidesNonLinks() throws {
        let panel = ScreenshotBarcodePanelView(
            frame: CGRect(x: 0, y: 0, width: 720, height: 500)
        )
        let window = NSWindow(
            contentRect: panel.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = panel
        panel.showPreview(try makeSolidImage(width: 640, height: 360))

        let first = BarcodeResult(
            symbology: "QR",
            payload: "https://example.com/first",
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4)
        )
        let second = BarcodeResult(
            symbology: "QR",
            payload: "https://example.com/second",
            boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        )
        let nonLink = BarcodeResult(
            symbology: "QR",
            payload: "plain text",
            boundingBox: CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.2)
        )

        panel.showResults([first, nonLink])
        panel.layoutSubtreeIfNeeded()
        XCTAssertEqual(linkButtons(in: panel).count, 1)
        XCTAssertEqual(unsupportedButtons(in: panel).count, 1)
        XCTAssertEqual(panel.unsupportedMarkerCount, 1)
        XCTAssertEqual(
            unsupportedButtons(in: panel).first?.toolTip,
            String(localized: "screenshot.scan.unsupported")
        )
        XCTAssertTrue(panel.isPreviewDimmed)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertEqual(panel.animatedLinkButtonCount, 1)
        }

        panel.showLoading()
        XCTAssertFalse(panel.isPreviewDimmed)
        panel.showResults([second])
        panel.layoutSubtreeIfNeeded()

        let buttons = linkButtons(in: panel)
        XCTAssertEqual(buttons.count, 1)
        XCTAssertEqual(buttons.first?.toolTip, "example.com")
        XCTAssertEqual(panel.unsupportedMarkerCount, 0)
    }

    func testEmptyScanShowsCenteredUnsupportedMarker() throws {
        let panel = ScreenshotBarcodePanelView(
            frame: CGRect(x: 0, y: 0, width: 720, height: 500)
        )
        panel.showPreview(try makeSolidImage(width: 640, height: 360))
        panel.showUnsupportedResult(
            String(localized: "screenshot.scan.empty")
        )
        panel.layoutSubtreeIfNeeded()

        XCTAssertTrue(panel.isPreviewDimmed)
        XCTAssertEqual(panel.unsupportedMarkerCount, 1)
        XCTAssertEqual(unsupportedButtons(in: panel).count, 1)
    }

    func testClickingLinkButtonReturnsTheMatchingResult() throws {
        let panel = ScreenshotBarcodePanelView(
            frame: CGRect(x: 0, y: 0, width: 720, height: 500)
        )
        let result = BarcodeResult(
            symbology: "QR",
            payload: "https://example.com/open",
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3)
        )
        var openedResult: BarcodeResult?
        panel.onOpen = { openedResult = $0 }

        panel.showPreview(try makeSolidImage(width: 640, height: 360))
        panel.showResults([result])
        panel.layoutSubtreeIfNeeded()
        try XCTUnwrap(linkButtons(in: panel).first).performClick(nil)

        XCTAssertEqual(openedResult?.payload, result.payload)
    }

    func testPanelShowsEveryMarkerInMultiCodeResult() throws {
        let panel = ScreenshotBarcodePanelView(
            frame: CGRect(x: 0, y: 0, width: 900, height: 620)
        )
        panel.showPreview(try makeSolidImage(width: 1000, height: 700))
        panel.showResults([
            BarcodeResult(
                symbology: "QR",
                payload: "https://example.com/one",
                boundingBox: CGRect(x: 0.04, y: 0.56, width: 0.24, height: 0.34)
            ),
            BarcodeResult(
                symbology: "QR",
                payload: "https://example.com/two",
                boundingBox: CGRect(x: 0.38, y: 0.54, width: 0.18, height: 0.26)
            ),
            BarcodeResult(
                symbology: "QR",
                payload: "https://example.com/three",
                boundingBox: CGRect(x: 0.69, y: 0.51, width: 0.26, height: 0.37)
            ),
            BarcodeResult(
                symbology: "QR",
                payload: "plain text",
                boundingBox: CGRect(x: 0.33, y: 0.06, width: 0.22, height: 0.31)
            )
        ])
        panel.layoutSubtreeIfNeeded()

        XCTAssertEqual(linkButtons(in: panel).count, 3)
        XCTAssertEqual(unsupportedButtons(in: panel).count, 1)
    }

    func testPreviewUsesLogicalDisplaySizeOnScaledDisplays() throws {
        let panel = ScreenshotBarcodePanelView(
            frame: CGRect(x: 0, y: 0, width: 960, height: 640)
        )

        panel.showPreview(
            try makeSolidImage(width: 3840, height: 2160),
            displaySize: CGSize(width: 1920, height: 1080)
        )

        let sizes = imageSizes(in: panel)
        XCTAssertTrue(sizes.contains(NSSize(width: 1920, height: 1080)))
        XCTAssertFalse(sizes.contains(NSSize(width: 3840, height: 2160)))
    }

    private func linkButtons(in view: NSView) -> [NSButton] {
        markerButtons(in: view, identifier: "barcode.link")
    }

    private func unsupportedButtons(in view: NSView) -> [NSButton] {
        markerButtons(in: view, identifier: "barcode.unsupported")
    }

    private func markerButtons(
        in view: NSView,
        identifier: String
    ) -> [NSButton] {
        let ownButton = (view as? NSButton).flatMap {
            $0.identifier?.rawValue == identifier ? $0 : nil
        }.map { [$0] } ?? []
        return ownButton + view.subviews.flatMap {
            markerButtons(in: $0, identifier: identifier)
        }
    }

    private func imageSizes(in view: NSView) -> [NSSize] {
        let imageSize = (view as? NSImageView)?.image.map { [$0.size] } ?? []
        return imageSize + view.subviews.flatMap(imageSizes)
    }

    private func makeSolidImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}

final class TextRecognizerTests: XCTestCase {
    func testRecognizerReadsGeneratedText() async throws {
        let image = NSImage(size: NSSize(width: 640, height: 180))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        "Cliploom OCR 2026".draw(
            at: NSPoint(x: 30, y: 55),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 48, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
        )
        image.unlockFocus()

        let cgImage = try XCTUnwrap(
            image.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            )
        )

        let result = try await TextRecognizer.recognize(cgImage: cgImage)

        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("Cliploom"))
        XCTAssertTrue(result.text.contains("2026"))
        if ImageAnalyzer.isSupported {
            XCTAssertNotNil(result.imageAnalysis)
        }
    }

    func testRecognizerFallsBackToVisionWithoutLiveTextAnalysis() async throws {
        let image = NSImage(size: NSSize(width: 640, height: 180))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        "Fallback OCR".draw(
            at: NSPoint(x: 30, y: 55),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 48, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
        )
        image.unlockFocus()
        let cgImage = try XCTUnwrap(
            image.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            )
        )

        let result = try await TextRecognizer.recognize(
            cgImage: cgImage,
            includeLiveTextAnalysis: false
        )

        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("Fallback"))
        XCTAssertNil(result.imageAnalysis)
    }
}

@MainActor
final class GlobalHotKeyManagerTests: XCTestCase {
    func testDefaultsAndInternalConflictDetection() {
        let suiteName = "PasteBoxHotKeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = GlobalHotKeyManager(defaults: defaults)

        XCTAssertEqual(
            manager.configuration(for: .clipboardPanel),
            HotKeyConfiguration(
                keyCode: UInt32(kVK_ANSI_V),
                modifiers: UInt32(optionKey),
                keyLabel: "V"
            )
        )
        XCTAssertEqual(
            manager.configuration(for: .screenshot),
            HotKeyConfiguration(
                keyCode: UInt32(kVK_ANSI_A),
                modifiers: UInt32(optionKey),
                keyLabel: "A"
            )
        )
        XCTAssertTrue(
            manager.conflictsInternally(
                manager.configuration(for: .clipboardPanel),
                excluding: .screenshot
            )
        )
    }

    func testLegacyClipboardShortcutKeysStillLoad() {
        let suiteName = "PasteBoxHotKeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(UInt32(kVK_ANSI_B), forKey: "hotKey.keyCode")
        defaults.set(UInt32(cmdKey | shiftKey), forKey: "hotKey.modifiers")
        defaults.set("B", forKey: "hotKey.keyLabel")

        let manager = GlobalHotKeyManager(defaults: defaults)

        XCTAssertEqual(manager.configuration(for: .clipboardPanel).keyLabel, "B")
        XCTAssertEqual(
            manager.configuration(for: .screenshot),
            HotKeyAction.screenshot.defaultConfiguration
        )
    }
}
