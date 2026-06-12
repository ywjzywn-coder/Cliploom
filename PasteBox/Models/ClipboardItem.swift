import Foundation
import SwiftData

enum ClipboardKind: String, CaseIterable, Codable {
    case text
    case link
    case image
    case file

    var symbolName: String {
        switch self {
        case .text: "doc.text"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        }
    }

    var localizedKey: String {
        switch self {
        case .text: "category.text"
        case .link: "category.links"
        case .image: "category.images"
        case .file: "category.files"
        }
    }
}

@Model
final class ClipboardItem {
    @Attribute(.unique) var id: UUID
    var contentHash: String
    var kindRawValue: String
    var summary: String
    var textContent: String?
    var imagePath: String?
    var filePathsData: Data?
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        contentHash: String,
        kind: ClipboardKind,
        summary: String,
        textContent: String? = nil,
        imagePath: String? = nil,
        filePaths: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.contentHash = contentHash
        self.kindRawValue = kind.rawValue
        self.summary = summary
        self.textContent = textContent
        self.imagePath = imagePath
        self.filePathsData = try? JSONEncoder().encode(filePaths)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
    }

    var kind: ClipboardKind {
        get { ClipboardKind(rawValue: kindRawValue) ?? .text }
        set { kindRawValue = newValue.rawValue }
    }

    var filePaths: [String] {
        get {
            guard let filePathsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: filePathsData)) ?? []
        }
        set {
            filePathsData = try? JSONEncoder().encode(newValue)
        }
    }

    var filesAreAvailable: Bool {
        kind != .file || filePaths.allSatisfy(FileManager.default.fileExists(atPath:))
    }
}
