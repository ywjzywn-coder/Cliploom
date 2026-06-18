import AppKit
import CoreImage
import Foundation
import Vision

struct BarcodeResult: Identifiable, Hashable {
    let id = UUID()
    let symbology: String
    let payload: String
    let boundingBox: CGRect

    var webURL: URL? {
        guard ClipboardPayload.isWebLink(payload) else { return nil }
        return URL(string: payload)
    }
}

enum BarcodeScanner {
    private static let tileGridSize = 2
    private static let tileOverlap: CGFloat = 0.18
    private static let targetTileLongEdge: CGFloat = 1_800
    private static let maximumTileScale: CGFloat = 3

    static func scan(pngData: Data) async throws -> [BarcodeResult] {
        guard let image = NSImage(data: pngData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return [] }
        return try await scan(cgImage: cgImage)
    }

    static func scan(cgImage: CGImage) async throws -> [BarcodeResult] {
        return try await Task.detached(priority: .userInitiated) {
            var results = try detect(in: cgImage, sourceRect: nil)
            let imageContext = CIContext(options: [.cacheIntermediates: false])

            for sourceRect in tileRects(for: cgImage) {
                guard let croppedImage = cgImage.cropping(to: sourceRect) else {
                    continue
                }
                let scanImage = scaledTile(
                    croppedImage,
                    context: imageContext
                )
                results.append(
                    contentsOf: try detect(
                        in: scanImage,
                        sourceRect: sourceRect,
                        fullImageSize: CGSize(
                            width: cgImage.width,
                            height: cgImage.height
                        )
                    )
                )
            }

            return deduplicated(results).sorted {
                if abs($0.boundingBox.maxY - $1.boundingBox.maxY) > 0.02 {
                    return $0.boundingBox.maxY > $1.boundingBox.maxY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
        }.value
    }

    private static func detect(
        in image: CGImage,
        sourceRect: CGRect?,
        fullImageSize: CGSize? = nil
    ) throws -> [BarcodeResult] {
        let request = VNDetectBarcodesRequest()
        request.revision = VNDetectBarcodesRequestRevision4
        if let supported = try? request.supportedSymbologies() {
            request.symbologies = supported
        }
        try VNImageRequestHandler(cgImage: image).perform([request])

        return (request.results ?? []).map { observation in
            let payload = observation.payloadStringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return BarcodeResult(
                symbology: observation.symbology.rawValue,
                payload: payload,
                boundingBox: remap(
                    observation.boundingBox,
                    from: sourceRect,
                    fullImageSize: fullImageSize
                )
            )
        }
    }

    private static func tileRects(for image: CGImage) -> [CGRect] {
        let imageSize = CGSize(width: image.width, height: image.height)
        let cellSize = CGSize(
            width: imageSize.width / CGFloat(tileGridSize),
            height: imageSize.height / CGFloat(tileGridSize)
        )

        return (0..<tileGridSize).flatMap { row in
            (0..<tileGridSize).map { column in
                let leftOverlap = column == 0 ? 0 : cellSize.width * tileOverlap
                let rightOverlap = column == tileGridSize - 1
                    ? 0
                    : cellSize.width * tileOverlap
                let bottomOverlap = row == 0 ? 0 : cellSize.height * tileOverlap
                let topOverlap = row == tileGridSize - 1
                    ? 0
                    : cellSize.height * tileOverlap

                return CGRect(
                    x: CGFloat(column) * cellSize.width - leftOverlap,
                    y: CGFloat(row) * cellSize.height - bottomOverlap,
                    width: cellSize.width + leftOverlap + rightOverlap,
                    height: cellSize.height + bottomOverlap + topOverlap
                ).integral
            }
        }
    }

    private static func scaledTile(
        _ image: CGImage,
        context: CIContext
    ) -> CGImage {
        let longEdge = CGFloat(max(image.width, image.height))
        let scale = min(
            maximumTileScale,
            max(1, targetTileLongEdge / max(longEdge, 1))
        )
        guard scale > 1.01 else { return image }

        let source = CIImage(cgImage: image)
        let scaled = source.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        return context.createCGImage(scaled, from: scaled.extent) ?? image
    }

    private static func remap(
        _ boundingBox: CGRect,
        from sourceRect: CGRect?,
        fullImageSize: CGSize?
    ) -> CGRect {
        guard let sourceRect, let fullImageSize else { return boundingBox }

        let sourceBottom = fullImageSize.height - sourceRect.maxY
        return CGRect(
            x: (
                sourceRect.minX
                    + boundingBox.minX * sourceRect.width
            ) / fullImageSize.width,
            y: (
                sourceBottom
                    + boundingBox.minY * sourceRect.height
            ) / fullImageSize.height,
            width: boundingBox.width * sourceRect.width / fullImageSize.width,
            height: boundingBox.height * sourceRect.height / fullImageSize.height
        )
    }

    static func deduplicated(_ results: [BarcodeResult]) -> [BarcodeResult] {
        var accepted: [BarcodeResult] = []
        for result in results {
            let isDuplicate = accepted.contains { existing in
                guard existing.symbology == result.symbology,
                      existing.payload == result.payload
                else { return false }

                return abs(existing.boundingBox.midX - result.boundingBox.midX) < 0.01
                    && abs(existing.boundingBox.midY - result.boundingBox.midY) < 0.01
                    && abs(existing.boundingBox.width - result.boundingBox.width) < 0.02
                    && abs(existing.boundingBox.height - result.boundingBox.height) < 0.02
            }
            if !isDuplicate {
                accepted.append(result)
            }
        }
        return accepted
    }
}
