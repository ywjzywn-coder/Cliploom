import AppKit
import CryptoKit
import Foundation

enum ClipboardPayload {
    case text(String, isLink: Bool)
    case image(Data)
    case files([URL])

    var kind: ClipboardKind {
        switch self {
        case let .text(_, isLink): isLink ? .link : .text
        case .image: .image
        case .files: .file
        }
    }

    var contentHash: String {
        let data: Data
        switch self {
        case let .text(value, isLink):
            data = Data("\(isLink ? "link" : "text"):\(value)".utf8)
        case let .image(value):
            data = Data("image:".utf8) + value
        case let .files(urls):
            let paths = urls.map(\.standardizedFileURL.path).sorted().joined(separator: "\n")
            data = Data("files:\(paths)".utf8)
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    var summary: String {
        switch self {
        case let .text(value, _):
            let oneLine = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            return String(oneLine.prefix(160))
        case let .image(data):
            guard let image = NSImage(data: data) else {
                return String(localized: "item.image")
            }
            return String(
                format: String(localized: "item.image.size"),
                Int(image.size.width),
                Int(image.size.height)
            )
        case let .files(urls):
            if urls.count == 1 {
                return urls[0].lastPathComponent
            }
            return String(format: String(localized: "item.files.count"), urls.count)
        }
    }

    static func isWebLink(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil
        else {
            return false
        }
        return true
    }

    static func read(from pasteboard: NSPasteboard) -> ClipboardPayload? {
        let urlOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: urlOptions),
           let urls = objects.compactMap({ ($0 as? NSURL) as URL? }).nonEmpty {
            return .files(urls)
        }

        if let png = pasteboard.data(forType: .png) {
            return .image(png)
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return .image(png)
        }

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return .text(string, isLink: isWebLink(string))
        }
        return nil
    }
}

private extension Array {
    var nonEmpty: Self? { isEmpty ? nil : self }
}
