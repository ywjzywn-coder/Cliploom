import AppKit
import Foundation
import NaturalLanguage

enum ScreenshotTool: String, CaseIterable {
    case pointer
    case rectangle
    case arrow
    case pen
    case mosaic

    var symbolName: String {
        switch self {
        case .pointer: "hand.point.up.left.fill"
        case .rectangle: "rectangle"
        case .arrow: "arrow.up.right"
        case .pen: "pencil.tip"
        case .mosaic: "square.grid.3x3.fill"
        }
    }

    var localizedTitle: String {
        switch self {
        case .pointer: String(localized: "screenshot.tool.pointer")
        case .rectangle: String(localized: "screenshot.tool.rectangle")
        case .arrow: String(localized: "screenshot.tool.arrow")
        case .pen: String(localized: "screenshot.tool.pen")
        case .mosaic: String(localized: "screenshot.tool.mosaic")
        }
    }

    var supportsColor: Bool {
        switch self {
        case .rectangle, .arrow, .pen:
            true
        case .pointer, .mosaic:
            false
        }
    }

    var supportsLineWidth: Bool {
        switch self {
        case .rectangle, .arrow, .pen:
            true
        case .pointer, .mosaic:
            false
        }
    }
}

enum ScreenshotAnnotation {
    case rectangle(rect: CGRect, color: NSColor, width: CGFloat)
    case arrow(start: CGPoint, end: CGPoint, color: NSColor, width: CGFloat)
    case pen(points: [CGPoint], color: NSColor, width: CGFloat)
    case mosaic(rect: CGRect)
}

struct CapturableWindow {
    let windowID: CGWindowID
    let ownerName: String
    let frame: CGRect
    let layer: Int
}

struct ScreenshotCoordinateMapper {
    let viewSize: CGSize
    let pixelSize: CGSize

    var scaleX: CGFloat { pixelSize.width / max(viewSize.width, 1) }
    var scaleY: CGFloat { pixelSize.height / max(viewSize.height, 1) }

    func pixelPoint(for viewPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(floor(viewPoint.x * scaleX), 0), max(pixelSize.width - 1, 0)),
            y: min(
                max(floor((viewSize.height - viewPoint.y) * scaleY), 0),
                max(pixelSize.height - 1, 0)
            )
        )
    }

    func pixelCropRect(for selection: CGRect) -> CGRect {
        let standardized = selection.standardized.intersection(
            CGRect(origin: .zero, size: viewSize)
        )
        let pixelBounds = CGRect(origin: .zero, size: pixelSize)
        return CGRect(
            x: standardized.minX * scaleX,
            y: (viewSize.height - standardized.maxY) * scaleY,
            width: standardized.width * scaleX,
            height: standardized.height * scaleY
        )
        .integral
        .intersection(pixelBounds)
    }

    static func localWindowFrame(
        globalFrame: CGRect,
        displayBounds: CGRect,
        screenSize: CGSize
    ) -> CGRect {
        CGRect(
            x: globalFrame.minX - displayBounds.minX,
            y: displayBounds.maxY - globalFrame.maxY,
            width: globalFrame.width,
            height: globalFrame.height
        ).intersection(CGRect(origin: .zero, size: screenSize))
    }
}

enum ScreenshotCaptureGeometry {
    static func orientedPixelSize(
        logicalSize: CGSize,
        modePixelSize: CGSize?
    ) -> CGSize {
        guard let modePixelSize,
              logicalSize.width > 0,
              logicalSize.height > 0,
              modePixelSize.width > 0,
              modePixelSize.height > 0
        else {
            return logicalSize
        }

        let logicalAspect = logicalSize.width / logicalSize.height
        let directDifference = abs(
            modePixelSize.width / modePixelSize.height - logicalAspect
        )
        let rotatedDifference = abs(
            modePixelSize.height / modePixelSize.width - logicalAspect
        )

        if rotatedDifference < directDifference {
            return CGSize(
                width: modePixelSize.height,
                height: modePixelSize.width
            )
        }
        return modePixelSize
    }
}

enum ScreenshotTranslationDirection {
    static func targetIdentifier(
        for text: String,
        dominantLanguage: NLLanguage? = nil
    ) -> String {
        let language = dominantLanguage
            ?? NLLanguageRecognizer.dominantLanguage(for: text)
        switch language {
        case .simplifiedChinese?, .traditionalChinese?:
            return "en"
        default:
            return "zh-Hans"
        }
    }
}

struct ScreenshotColorSample: Equatable {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Int
    let pixelPoint: CGPoint

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var rgb: String {
        "RGB \(red), \(green), \(blue)"
    }

    var color: NSColor {
        NSColor(
            calibratedRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }
}

final class ScreenshotPixelSampler {
    let image: CGImage
    private let bitmap: NSBitmapImageRep

    init(image: CGImage) {
        self.image = image
        bitmap = NSBitmapImageRep(cgImage: image)
    }

    func sample(
        at viewPoint: CGPoint,
        mapper: ScreenshotCoordinateMapper
    ) -> ScreenshotColorSample? {
        let pixelPoint = mapper.pixelPoint(for: viewPoint)
        guard let color = bitmap.colorAt(
            x: Int(pixelPoint.x),
            y: Int(pixelPoint.y)
        )?.usingColorSpace(.sRGB) else {
            return nil
        }

        return ScreenshotColorSample(
            red: Self.byte(color.redComponent),
            green: Self.byte(color.greenComponent),
            blue: Self.byte(color.blueComponent),
            alpha: Self.byte(color.alphaComponent),
            pixelPoint: pixelPoint
        )
    }

    func magnifierCrop(
        centeredAt pixelPoint: CGPoint,
        diameter: Int
    ) -> (image: CGImage, rect: CGRect)? {
        let size = max(diameter, 1)
        let half = size / 2
        let maximumX = max(image.width - size, 0)
        let maximumY = max(image.height - size, 0)
        let originX = min(max(Int(pixelPoint.x) - half, 0), maximumX)
        let originY = min(max(Int(pixelPoint.y) - half, 0), maximumY)
        let cropRect = CGRect(
            x: originX,
            y: originY,
            width: min(size, image.width),
            height: min(size, image.height)
        )
        guard cropRect.width > 0,
              cropRect.height > 0,
              let cropped = image.cropping(to: cropRect)
        else {
            return nil
        }
        return (cropped, cropRect)
    }

    private static func byte(_ component: CGFloat) -> Int {
        min(max(Int((component * 255).rounded()), 0), 255)
    }
}

enum ScreenshotToolbarGeometry {
    static func centeredSquare(in container: CGRect) -> CGRect {
        guard container.width > 0, container.height > 0 else {
            return CGRect(origin: container.origin, size: .zero)
        }
        let side = min(container.width, container.height)
        return CGRect(
            x: container.midX - side / 2,
            y: container.midY - side / 2,
            width: side,
            height: side
        )
    }

    static func aspectFitRect(
        contentSize: CGSize,
        in container: CGRect
    ) -> CGRect {
        guard contentSize.width > 0,
              contentSize.height > 0,
              container.width > 0,
              container.height > 0
        else {
            return CGRect(origin: container.origin, size: .zero)
        }

        let scale = min(
            container.width / contentSize.width,
            container.height / contentSize.height
        )
        let size = CGSize(
            width: contentSize.width * scale,
            height: contentSize.height * scale
        )
        return CGRect(
            x: container.midX - size.width / 2,
            y: container.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func hitIndex(
        at point: CGPoint,
        in rects: [CGRect],
        expansion: CGFloat = 8
    ) -> Int? {
        if let exactIndex = rects.firstIndex(where: { $0.contains(point) }) {
            return exactIndex
        }

        return rects.indices
            .filter {
                rects[$0]
                    .insetBy(dx: -expansion, dy: -expansion)
                    .contains(point)
            }
            .min {
                distanceSquared(from: point, to: rects[$0].center)
                    < distanceSquared(from: point, to: rects[$1].center)
            }
    }

    private static func distanceSquared(
        from first: CGPoint,
        to second: CGPoint
    ) -> CGFloat {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return dx * dx + dy * dy
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

enum ScreenshotPreviewGeometry {
    static func aspectFitRect(
        contentSize: CGSize,
        in bounds: CGRect
    ) -> CGRect {
        guard contentSize.width > 0,
              contentSize.height > 0,
              bounds.width > 0,
              bounds.height > 0
        else { return .zero }

        let scale = min(
            bounds.width / contentSize.width,
            bounds.height / contentSize.height
        )
        let size = CGSize(
            width: contentSize.width * scale,
            height: contentSize.height * scale
        )
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func center(
        of normalizedBoundingBox: CGRect,
        in imageRect: CGRect
    ) -> CGPoint {
        CGPoint(
            x: imageRect.minX + normalizedBoundingBox.midX * imageRect.width,
            y: imageRect.minY + normalizedBoundingBox.midY * imageRect.height
        )
    }

    static func aspectFitUnitRect(
        contentSize: CGSize,
        in bounds: CGRect
    ) -> CGRect {
        let imageRect = aspectFitRect(contentSize: contentSize, in: bounds)
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        return CGRect(
            x: (imageRect.minX - bounds.minX) / bounds.width,
            y: (imageRect.minY - bounds.minY) / bounds.height,
            width: imageRect.width / bounds.width,
            height: imageRect.height / bounds.height
        )
    }
}

enum OCRPanelGeometry {
    private static let minimumWidth: CGFloat = 640
    private static let minimumHeight: CGFloat = 420
    private static let preferredMaximumWidth: CGFloat = 1100
    private static let preferredMaximumHeight: CGFloat = 680
    private static let maximumScreenWidthRatio: CGFloat = 0.86
    private static let maximumScreenHeightRatio: CGFloat = 0.82

    static func preferredSize(
        selection: CGSize,
        maximum: CGSize
    ) -> CGSize {
        guard maximum.width > 0, maximum.height > 0 else { return .zero }

        let allowedWidth = min(
            maximum.width,
            max(minimumWidth, min(preferredMaximumWidth, maximum.width * maximumScreenWidthRatio))
        )
        let allowedHeight = min(
            maximum.height,
            max(minimumHeight, min(preferredMaximumHeight, maximum.height * maximumScreenHeightRatio))
        )
        let previewWidth = max(360, selection.width)
        let resultWidth = max(280, previewWidth * 0.52)

        return CGSize(
            width: min(max(minimumWidth, previewWidth + resultWidth + 72), allowedWidth),
            height: min(max(minimumHeight, selection.height + 116), allowedHeight)
        )
    }
}

enum BarcodePanelGeometry {
    private static let horizontalChrome: CGFloat = 28
    private static let verticalChrome: CGFloat = 108
    private static let minimumWidth: CGFloat = 420
    private static let minimumHeight: CGFloat = 340
    private static let preferredMaximumWidth: CGFloat = 960
    private static let preferredMaximumHeight: CGFloat = 640
    private static let maximumScreenWidthRatio: CGFloat = 0.86
    private static let maximumScreenHeightRatio: CGFloat = 0.78

    static func preferredSize(
        imageSize: CGSize,
        selectionSize: CGSize,
        maximum: CGSize
    ) -> CGSize {
        guard maximum.width > 0, maximum.height > 0 else { return .zero }

        let allowedWidth = min(
            maximum.width,
            max(minimumWidth, min(preferredMaximumWidth, maximum.width * maximumScreenWidthRatio))
        )
        let allowedHeight = min(
            maximum.height,
            max(minimumHeight, min(preferredMaximumHeight, maximum.height * maximumScreenHeightRatio))
        )
        let width = min(
            max(minimumWidth, selectionSize.width + horizontalChrome),
            allowedWidth
        )
        let previewWidth = max(width - horizontalChrome, 1)
        let aspectRatio = imageSize.width / max(imageSize.height, 1)
        let previewHeight = previewWidth / max(aspectRatio, 0.01)
        let height = min(
            max(minimumHeight, previewHeight + verticalChrome),
            allowedHeight
        )

        return CGSize(
            width: width,
            height: height
        )
    }
}

@MainActor
final class ScreenshotSession: ObservableObject {
    let image: CGImage
    let screen: NSScreen
    let windows: [CapturableWindow]

    @Published var selection: CGRect?
    @Published var hoveredWindow: CapturableWindow?
    @Published var annotations: [ScreenshotAnnotation] = []
    @Published var tool: ScreenshotTool = .pointer
    @Published var color: NSColor = .systemRed
    @Published var lineWidth: CGFloat = 4

    init(image: CGImage, screen: NSScreen, windows: [CapturableWindow]) {
        self.image = image
        self.screen = screen
        self.windows = windows
    }

    var mapper: ScreenshotCoordinateMapper {
        ScreenshotCoordinateMapper(
            viewSize: screen.frame.size,
            pixelSize: CGSize(width: image.width, height: image.height)
        )
    }

    func window(at point: CGPoint) -> CapturableWindow? {
        windows.first { $0.frame.contains(point) }
    }

    func undo() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
    }
}
