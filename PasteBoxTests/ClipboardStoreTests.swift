import AppKit
import SwiftData
import XCTest
@testable import PasteBox

@MainActor
final class ClipboardStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var imageDirectory: URL!
    private var store: ClipboardStore!

    override func setUpWithError() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: ClipboardItem.self, configurations: configuration)
        imageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteBoxTests-\(UUID().uuidString)", isDirectory: true)
        store = ClipboardStore(container: container, imageDirectory: imageDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: imageDirectory)
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
