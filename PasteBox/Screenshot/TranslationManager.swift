import Foundation

struct GoogleTranslationResponse: Decodable {
    struct Translation: Decodable {
        let translatedText: String
    }

    let data: Translations

    struct Translations: Decodable {
        let translations: [Translation]
    }
}

@MainActor
final class TranslationManager {
    private let session: URLSession
    private var requestGeneration: UInt = 0

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "Cliploom/1.0 (macOS)"
        ]
        session = URLSession(configuration: config)
    }

    func translate(
        texts: [String],
        targetIdentifier: String
    ) async -> [String] {
        requestGeneration &+= 1
        let generation = requestGeneration

        var results: [String] = []
        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                results.append("")
                continue
            }
            let translated = await translateSingle(
                trimmed,
                target: targetIdentifier,
                generation: generation
            )
            results.append(translated)
        }
        return results
    }

    private func translateSingle(
        _ text: String,
        target: String,
        generation: UInt
    ) async -> String {
        guard let encodedText = text.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) else { return "" }

        let urlString = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=\(target)&dt=t&q=\(encodedText)"
        guard let url = URL(string: urlString) else { return "" }

        do {
            let (data, _) = try await session.data(from: url)
            guard generation == requestGeneration else { return "" }

            let decoded = try JSONDecoder().decode(
                GoogleTranslateRawResponse.self,
                from: data
            )
            return decoded.translations.map(\.0).joined()
        } catch {
            return ""
        }
    }
}

private struct GoogleTranslateRawResponse: Decodable {
    let translations: [(String, String?)]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let array = try container.decode([AnyCodable].self)
        let chunks = array.first?.arrayValue ?? []
        translations = chunks.compactMap { chunk in
            guard let inner = chunk.arrayValue,
                  let text = inner.first?.stringValue
            else { return nil }
            return (text, inner.count > 1 ? inner[1].stringValue : nil)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

private struct AnyCodable: Decodable {
    let stringValue: String?
    let arrayValue: [AnyCodable]?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            stringValue = string
            arrayValue = nil
        } else if let array = try? container.decode([AnyCodable].self) {
            stringValue = nil
            arrayValue = array
        } else {
            stringValue = nil
            arrayValue = nil
        }
    }
}
