import Foundation
import SwiftData

@MainActor
final class ClipboardStore {
    let context: ModelContext
    let imageDirectory: URL
    private let defaults: UserDefaults

    init(
        container: ModelContainer,
        imageDirectory: URL? = nil,
        defaults: UserDefaults = .standard
    ) {
        context = container.mainContext
        context.autosaveEnabled = true
        self.defaults = defaults

        if let imageDirectory {
            self.imageDirectory = imageDirectory
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.imageDirectory = base
                .appendingPathComponent("PasteBox", isDirectory: true)
                .appendingPathComponent("Images", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: self.imageDirectory,
            withIntermediateDirectories: true
        )
    }

    @discardableResult
    func save(_ payload: ClipboardPayload, now: Date = .now) throws -> ClipboardItem {
        let hash = payload.contentHash
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.updatedAt = now
            existing.summary = payload.summary
            try context.save()
            try cleanup(now: now)
            return existing
        }

        var imagePath: String?
        var textContent: String?
        var filePaths: [String] = []

        switch payload {
        case let .text(text, _):
            textContent = text
        case let .image(data):
            let url = imageDirectory.appendingPathComponent("\(UUID().uuidString).png")
            try data.write(to: url, options: .atomic)
            imagePath = url.path
        case let .files(urls):
            filePaths = urls.map(\.standardizedFileURL.path)
        }

        let item = ClipboardItem(
            contentHash: hash,
            kind: payload.kind,
            summary: payload.summary,
            textContent: textContent,
            imagePath: imagePath,
            filePaths: filePaths,
            createdAt: now,
            updatedAt: now
        )
        context.insert(item)
        try context.save()
        try cleanup(now: now)
        return item
    }

    func toggleFavorite(_ item: ClipboardItem) {
        item.isFavorite.toggle()
        try? context.save()
    }

    func delete(_ item: ClipboardItem) {
        removeImage(for: item)
        context.delete(item)
        try? context.save()
    }

    func clearAll() {
        let descriptor = FetchDescriptor<ClipboardItem>()
        guard let items = try? context.fetch(descriptor) else { return }
        items.forEach {
            removeImage(for: $0)
            context.delete($0)
        }
        try? context.save()
    }

    func cleanup(
        now: Date = .now,
        maximumCount: Int? = nil,
        maximumAgeDays: Int? = nil
    ) throws {
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let items = try context.fetch(descriptor).filter { !$0.isFavorite }
        let resolvedMaximumCount = maximumCount
            ?? ClipboardHistorySettings.maximumCount(defaults: defaults)
        let resolvedMaximumAgeDays = maximumAgeDays
            ?? ClipboardHistorySettings.maximumAgeDays(defaults: defaults)
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -resolvedMaximumAgeDays,
            to: now
        ) ?? now

        for (index, item) in items.enumerated()
        where index >= resolvedMaximumCount || item.updatedAt < cutoff {
            removeImage(for: item)
            context.delete(item)
        }
        try context.save()
    }

    private func removeImage(for item: ClipboardItem) {
        guard let path = item.imagePath else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}
