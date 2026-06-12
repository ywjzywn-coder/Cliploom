import AppKit
import Foundation

enum ScreenshotRenderer {
    static func pngData(
        image: CGImage,
        selection: CGRect,
        viewSize: CGSize,
        annotations: [ScreenshotAnnotation]
    ) -> Data? {
        let mapper = ScreenshotCoordinateMapper(
            viewSize: viewSize,
            pixelSize: CGSize(width: image.width, height: image.height)
        )
        let pixelRect = mapper.pixelCropRect(for: selection)
        guard pixelRect.width >= 1,
              pixelRect.height >= 1,
              let cropped = image.cropping(to: pixelRect)
        else { return nil }

        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: cropped.width,
            pixelsHigh: cropped.height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        representation.size = selection.size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else { return nil }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        let bounds = CGRect(origin: .zero, size: selection.size)
        NSImage(cgImage: cropped, size: selection.size).draw(in: bounds)

        for annotation in annotations {
            draw(
                annotation,
                selection: selection,
                sourceImage: image,
                mapper: mapper
            )
        }
        context.flushGraphics()
        return representation.representation(using: .png, properties: [:])
    }

    private static func draw(
        _ annotation: ScreenshotAnnotation,
        selection: CGRect,
        sourceImage: CGImage,
        mapper: ScreenshotCoordinateMapper
    ) {
        switch annotation {
        case let .rectangle(rect, color, width):
            color.setStroke()
            let path = NSBezierPath(rect: local(rect, selection: selection))
            path.lineWidth = width
            path.stroke()

        case let .arrow(start, end, color, width):
            color.setStroke()
            color.setFill()
            let localStart = local(start, selection: selection)
            let localEnd = local(end, selection: selection)
            let path = NSBezierPath()
            path.move(to: localStart)
            path.line(to: localEnd)
            path.lineWidth = width
            path.lineCapStyle = .round
            path.stroke()
            drawArrowHead(from: localStart, to: localEnd, color: color, width: width)

        case let .pen(points, color, width):
            guard let first = points.first else { return }
            color.setStroke()
            let path = NSBezierPath()
            path.move(to: local(first, selection: selection))
            for point in points.dropFirst() {
                path.line(to: local(point, selection: selection))
            }
            path.lineWidth = width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()

        case let .mosaic(rect):
            drawMosaic(
                rect: rect,
                selection: selection,
                sourceImage: sourceImage,
                mapper: mapper
            )
        }
    }

    private static func drawMosaic(
        rect: CGRect,
        selection: CGRect,
        sourceImage: CGImage,
        mapper: ScreenshotCoordinateMapper
    ) {
        let clipped = rect.standardized.intersection(selection)
        guard clipped.width > 2, clipped.height > 2 else { return }
        let pixelRect = mapper.pixelCropRect(for: clipped)
        guard let source = sourceImage.cropping(to: pixelRect) else { return }
        let destination = local(clipped, selection: selection)
        let blockWidth = max(Int(destination.width / 12), 1)
        let blockHeight = max(Int(destination.height / 12), 1)

        guard let small = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: blockWidth,
            pixelsHigh: blockHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let smallContext = NSGraphicsContext(bitmapImageRep: small)
        else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = smallContext
        smallContext.imageInterpolation = .low
        NSImage(cgImage: source, size: NSSize(width: blockWidth, height: blockHeight))
            .draw(in: CGRect(x: 0, y: 0, width: blockWidth, height: blockHeight))
        smallContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(size: destination.size, flipped: false) { _ in
            small.draw(in: CGRect(origin: .zero, size: destination.size))
            return true
        }.draw(in: destination)
        NSGraphicsContext.current?.imageInterpolation = .high
    }

    private static func drawArrowHead(
        from start: CGPoint,
        to end: CGPoint,
        color: NSColor,
        width: CGFloat
    ) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(12, width * 4)
        let left = CGPoint(
            x: end.x - length * cos(angle - .pi / 6),
            y: end.y - length * sin(angle - .pi / 6)
        )
        let right = CGPoint(
            x: end.x - length * cos(angle + .pi / 6),
            y: end.y - length * sin(angle + .pi / 6)
        )
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: left)
        head.line(to: right)
        head.close()
        color.setFill()
        head.fill()
    }

    private static func local(_ rect: CGRect, selection: CGRect) -> CGRect {
        rect.offsetBy(dx: -selection.minX, dy: -selection.minY)
    }

    private static func local(_ point: CGPoint, selection: CGRect) -> CGPoint {
        CGPoint(x: point.x - selection.minX, y: point.y - selection.minY)
    }
}
