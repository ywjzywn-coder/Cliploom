import AppKit
import XCTest
@testable import PasteBox

final class ClipboardPayloadTests: XCTestCase {
    func testLinkDetectionAcceptsHTTPAndHTTPSOnly() {
        XCTAssertTrue(ClipboardPayload.isWebLink("https://example.com/path?q=1"))
        XCTAssertTrue(ClipboardPayload.isWebLink("http://例子.测试"))
        XCTAssertFalse(ClipboardPayload.isWebLink("example.com"))
        XCTAssertFalse(ClipboardPayload.isWebLink("hello world"))
        XCTAssertFalse(ClipboardPayload.isWebLink("file:///tmp/example"))
    }

    func testTextHashIsDeterministicAndKindSpecific() {
        let first = ClipboardPayload.text("https://example.com", isLink: true)
        let second = ClipboardPayload.text("https://example.com", isLink: true)
        let plainText = ClipboardPayload.text("https://example.com", isLink: false)

        XCTAssertEqual(first.contentHash, second.contentHash)
        XCTAssertNotEqual(first.contentHash, plainText.contentHash)
    }

    func testFileHashIgnoresSelectionOrder() {
        let first = ClipboardPayload.files([
            URL(fileURLWithPath: "/tmp/中文.txt"),
            URL(fileURLWithPath: "/tmp/b.txt")
        ])
        let second = ClipboardPayload.files([
            URL(fileURLWithPath: "/tmp/b.txt"),
            URL(fileURLWithPath: "/tmp/中文.txt")
        ])
        XCTAssertEqual(first.contentHash, second.contentHash)
    }

    func testPasteboardUsesFileBeforeText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("示例.txt")
        try Data("hello".utf8).write(to: file)

        let pasteboard = NSPasteboard(name: .init("PasteBoxTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([file as NSURL]))
        pasteboard.setString("fallback text", forType: .string)

        guard case let .files(urls) = ClipboardPayload.read(from: pasteboard) else {
            return XCTFail("Expected a file payload")
        }
        XCTAssertEqual(urls.first?.lastPathComponent, "示例.txt")
    }
}
