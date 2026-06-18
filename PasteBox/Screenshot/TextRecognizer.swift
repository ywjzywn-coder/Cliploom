import AppKit
import CoreGraphics
import Foundation
import Vision
import VisionKit

struct TextRecognitionResult {
    let text: String
    let imageAnalysis: ImageAnalysis?
}

enum TextRecognizer {
    private static let warmupTask = Task.detached(priority: .utility) {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 64,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let image = context.makeImage()
        else { return }
        if ImageAnalyzer.isSupported {
            let analyzer = ImageAnalyzer()
            let configuration = ImageAnalyzer.Configuration([.text])
            _ = try? await analyzer.analyze(
                image,
                orientation: .up,
                configuration: configuration
            )
        }
        _ = try? performRecognition(on: image)
    }

    static func prewarm() {
        _ = warmupTask
    }

    static func recognize(
        cgImage: CGImage,
        includeLiveTextAnalysis: Bool = true
    ) async throws -> TextRecognitionResult {
        await warmupTask.value

        if includeLiveTextAnalysis, ImageAnalyzer.isSupported {
            do {
                let analyzer = ImageAnalyzer()
                let configuration = ImageAnalyzer.Configuration([.text])
                let analysis = try await analyzer.analyze(
                    cgImage,
                    orientation: .up,
                    configuration: configuration
                )
                let text = analysis.transcript.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if !text.isEmpty {
                    return TextRecognitionResult(
                        text: text,
                        imageAnalysis: analysis
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Fall back to the existing Vision OCR path below.
            }
        }

        return try await Task.detached(priority: .userInitiated) {
            TextRecognitionResult(
                text: try performRecognition(on: cgImage),
                imageAnalysis: nil
            )
        }.value
    }

    private static func performRecognition(on cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        return (request.results ?? [])
            .sorted {
                if abs($0.boundingBox.maxY - $1.boundingBox.maxY) > 0.02 {
                    return $0.boundingBox.maxY > $1.boundingBox.maxY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
