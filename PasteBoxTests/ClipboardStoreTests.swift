import AppKit
import SwiftData
import XCTest
@testable import PasteBox

@MainActor
final class ClipboardStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var imageDirectory: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var store: ClipboardStore!

    override func setUpWithError() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: ClipboardItem.self, configurations: configuration)
        imageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteBoxTests-\(UUID().uuidString)", isDirectory: true)
        defaultsSuiteName = "PasteBoxTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        store = ClipboardStore(
            container: container,
            imageDirectory: imageDirectory,
            defaults: defaults
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: imageDirectory)
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        store = nil
        container = nil
    }

    func testDuplicateContentIsMovedForwardWithoutNewRecord() throws {
        let originalDate = Date(timeIntervalSince1970: 100)
        let newerDate = Date(timeIntervalSince1970: 200)
        let first = try store.save(.text("hello", isLink: false), now: originalDate)
        let second = try store.save(.text("hello", isLink: false), now: newerDate)

        let items = try store.context.fetch(FetchDescriptor<ClipboardItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.updatedAt, newerDate)
    }

    func testCleanupKeepsFavoritesAndRemovesExpiredItems() throws {
        let now = Date()
        let oldDate = Calendar.current.date(byAdding: .day, value: -40, to: now)!
        let expired = try store.save(.text("expired", isLink: false), now: oldDate)
        let favorite = try store.save(.text("favorite", isLink: false), now: oldDate)
        favorite.isFavorite = true
        try store.context.save()

        try store.cleanup(now: now)
        let items = try store.context.fetch(FetchDescriptor<ClipboardItem>())
        XCTAssertFalse(items.contains { $0.id == expired.id })
        XCTAssertTrue(items.contains { $0.id == favorite.id })
    }

    func testCleanupEnforcesMaximumCount() throws {
        let now = Date()
        for index in 0..<6 {
            _ = try store.save(
                .text("item-\(index)", isLink: false),
                now: now.addingTimeInterval(TimeInterval(index))
            )
        }

        try store.cleanup(now: now.addingTimeInterval(10), maximumCount: 3)
        let items = try store.context.fetch(FetchDescriptor<ClipboardItem>())
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(Set(items.compactMap(\.textContent)), Set(["item-3", "item-4", "item-5"]))
    }

    func testCleanupUsesCustomHistorySettings() throws {
        ClipboardHistorySettings.saveMaximumCount(20, defaults: defaults)
        ClipboardHistorySettings.saveMaximumAgeDays(7, defaults: defaults)
        let now = Date()
        let oldDate = Calendar.current.date(byAdding: .day, value: -8, to: now)!
        let expired = try store.save(.text("expired-custom", isLink: false), now: oldDate)
        for index in 0..<25 {
            _ = try store.save(
                .text("custom-\(index)", isLink: false),
                now: now.addingTimeInterval(TimeInterval(index))
            )
        }

        try store.cleanup(now: now.addingTimeInterval(30))
        let items = try store.context.fetch(FetchDescriptor<ClipboardItem>())
        XCTAssertEqual(items.count, 20)
        XCTAssertFalse(items.contains { $0.id == expired.id })
        XCTAssertEqual(
            Set(items.compactMap(\.textContent)),
            Set((5..<25).map { "custom-\($0)" })
        )
    }

    func testHistorySettingsClampUnsafeValues() throws {
        ClipboardHistorySettings.saveMaximumCount(-1, defaults: defaults)
        ClipboardHistorySettings.saveMaximumAgeDays(0, defaults: defaults)

        XCTAssertEqual(
            ClipboardHistorySettings.maximumCount(defaults: defaults),
            ClipboardHistorySettings.countRange.lowerBound
        )
        XCTAssertEqual(
            ClipboardHistorySettings.maximumAgeDays(defaults: defaults),
            ClipboardHistorySettings.ageDaysRange.lowerBound
        )

        ClipboardHistorySettings.saveMaximumCount(99_999, defaults: defaults)
        ClipboardHistorySettings.saveMaximumAgeDays(99_999, defaults: defaults)

        XCTAssertEqual(
            ClipboardHistorySettings.maximumCount(defaults: defaults),
            ClipboardHistorySettings.countRange.upperBound
        )
        XCTAssertEqual(
            ClipboardHistorySettings.maximumAgeDays(defaults: defaults),
            ClipboardHistorySettings.ageDaysRange.upperBound
        )
    }

    func testDeletingImageRemovesCacheFile() throws {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            return XCTFail("Unable to create test image")
        }

        let item = try store.save(.image(png))
        let path = try XCTUnwrap(item.imagePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        store.delete(item)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testDeletingFileRecordDoesNotDeleteOriginalFile() throws {
        let original = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteBox原文件-\(UUID().uuidString).txt")
        try Data("keep me".utf8).write(to: original)
        defer { try? FileManager.default.removeItem(at: original) }

        let item = try store.save(.files([original]))
        store.delete(item)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testLargeImageDataCanBeCached() throws {
        let data = Data(repeating: 0x7f, count: 8 * 1024 * 1024)
        let item = try store.save(.image(data))
        let path = try XCTUnwrap(item.imagePath)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)).count, data.count)
    }
}
