import AppKit
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
    static func scan(pngData: Data) async throws -> [BarcodeResult] {
        guard let image = NSImage(data: pngData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return [] }
        return try await scan(cgImage: cgImage)
    }

    static func scan(cgImage: CGImage) async throws -> [BarcodeResult] {
        return try await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            request.revision = VNDetectBarcodesRequestRevision4
            if let supported = try? request.supportedSymbologies() {
                request.symbologies = supported
            }
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try handler.perform([request])

            var seen = Set<String>()
            return (request.results ?? [])
                .compactMap { observation -> BarcodeResult? in
                    guard let payload = observation.payloadStringValue?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                        !payload.isEmpty
                    else { return nil }
                    let key = "\(observation.symbology.rawValue):\(payload)"
                    guard seen.insert(key).inserted else { return nil }
                    return BarcodeResult(
                        symbology: observation.symbology.rawValue,
                        payload: payload,
                        boundingBox: observation.boundingBox
                    )
                }
                .sorted {
                    if abs($0.boundingBox.maxY - $1.boundingBox.maxY) > 0.02 {
                        return $0.boundingBox.maxY > $1.boundingBox.maxY
                    }
                    return $0.boundingBox.minX < $1.boundingBox.minX
            }
        }.value
    }
}
