import XCTest
@testable import ContractionTraction

final class IncomingFileTests: XCTestCase {
    private var temporaryDirectory: URL!
    private let text = "2026-10-18 14:10 | 60s · partner's log"

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    // A folder name alone must never authorize deleting the original log.
    func testExternalInboxOriginalIsPreserved() throws {
        let inbox = temporaryDirectory.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let url = inbox.appendingPathComponent("partner.txt")
        try Data(text.utf8).write(to: url)
        XCTAssertEqual(try IncomingFile.read(url), text)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // Importing a prefix silently drops contractions beyond the size cap.
    func testOversizedLogIsRejectedAndRetained() throws {
        let url = try appInbox().appendingPathComponent("large-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0x20, count: IncomingFile.maxBytes + 1).write(to: url)
        XCTAssertThrowsError(try IncomingFile.read(url))
        XCTAssertEqual(try Data(contentsOf: url).count, IncomingFile.maxBytes + 1)
    }

    func testExactSizeLimitIsReadInFull() throws {
        let url = temporaryDirectory.appendingPathComponent("limit.txt")
        let data = Data(repeating: 0x20, count: IncomingFile.maxBytes)
        try data.write(to: url)
        XCTAssertEqual(try IncomingFile.read(url).utf8.count, data.count)
    }

    // Cleanup is safe only for the system's disposable copy in our Inbox.
    func testSuccessfullyReadAppInboxCopyIsRemoved() throws {
        let url = try appInbox().appendingPathComponent("test-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(text.utf8).write(to: url)
        XCTAssertEqual(try IncomingFile.read(url), text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // Resolving the file must not turn an Inbox symlink into permission to
    // clean up a location outside the app's disposable-copy directory.
    func testSymlinkOutsideAppInboxIsNotCleanedUp() throws {
        let original = temporaryDirectory.appendingPathComponent("original.txt")
        try Data(text.utf8).write(to: original)
        let link = try appInbox().appendingPathComponent("link-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: link) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        XCTAssertEqual(try IncomingFile.read(link), text)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
    }

    func testMissingFileIsReportedInsteadOfLookingEmpty() {
        XCTAssertThrowsError(try IncomingFile.read(temporaryDirectory.appendingPathComponent("missing.txt")))
    }

    func testNonFileURLIsRejectedWithoutReadingIt() throws {
        let url = try XCTUnwrap(URL(string: "https://example.invalid/log.txt"))
        XCTAssertThrowsError(try IncomingFile.read(url))
    }

    func testUTF16LogsDecodeWithoutLosingText() throws {
        for encoding in [String.Encoding.utf16, .utf16BigEndian, .utf16LittleEndian] {
            var data = try XCTUnwrap(text.data(using: encoding))
            if encoding == .utf16BigEndian { data.insert(contentsOf: [0xFE, 0xFF], at: 0) }
            if encoding == .utf16LittleEndian { data.insert(contentsOf: [0xFF, 0xFE], at: 0) }
            XCTAssertEqual(IncomingFile.decode(data), text)
        }
    }

    // A non-UTF8 character at the end must not be mistaken for a truncated
    // UTF8 sequence and dropped before the legacy decoder gets a chance.
    func testLegacyEncodedNoteKeepsItsFinalCharacter() throws {
        let text = "2026-10-18 14:10 | 60s | café"
        let data = try XCTUnwrap(text.data(using: .windowsCP1252))
        XCTAssertEqual(IncomingFile.decode(data), text)
    }

    private func appInbox() throws -> URL {
        let inbox = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)
            .appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }
}
