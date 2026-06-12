import AppKit
import Foundation

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

    func pixelCropRect(for selection: CGRect) -> CGRect {
        let standardized = selection.standardized.intersection(
            CGRect(origin: .zero, size: viewSize)
        )
        return CGRect(
            x: standardized.minX * scaleX,
            y: (viewSize.height - standardized.maxY) * scaleY,
            width: standardized.width * scaleX,
            height: standardized.height * scaleY
        ).integral
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

enum ScreenshotToolbarGeometry {
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
}

enum OCRPanelGeometry {
    static func preferredSize(
        selection: CGSize,
        maximum: CGSize
    ) -> CGSize {
        let previewWidth = max(360, selection.width)
        let resultWidth = max(280, previewWidth * 0.52)

        return CGSize(
            width: min(previewWidth + resultWidth + 72, maximum.width),
            height: min(max(460, selection.height + 116), maximum.height)
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
