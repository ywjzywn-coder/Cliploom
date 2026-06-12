import AppKit
import Carbon
import CoreImage
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
}

final class ScreenshotToolbarGeometryTests: XCTestCase {
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
}

final class OCRPanelGeometryTests: XCTestCase {
    func testSmallSelectionProducesCompactPanel() {
        let size = OCRPanelGeometry.preferredSize(
            selection: CGSize(width: 140, height: 80),
            maximum: CGSize(width: 1400, height: 800)
        )

        XCTAssertEqual(size, CGSize(width: 712, height: 460))
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

        XCTAssertEqual(size, CGSize(width: 1200, height: 720))
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

        let text = try await TextRecognizer.recognize(cgImage: cgImage)

        XCTAssertTrue(text.localizedCaseInsensitiveContains("Cliploom"))
        XCTAssertTrue(text.contains("2026"))
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
