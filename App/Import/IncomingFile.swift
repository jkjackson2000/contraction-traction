import Foundation

/// Reads a shared .txt log handed to the app by AirDrop, Files, or Messages.
/// Rejects unreadable or oversized files rather than importing a partial log.
enum IncomingFile {
    /// Far above any real log; keeps parsing and the text editor responsive.
    static let maxBytes = 512 * 1024

    enum ReadError: LocalizedError {
        case unreadable, tooLarge

        var errorDescription: String? {
            switch self {
            case .unreadable: "Couldn't read this log. Try sharing it again or choosing another text file."
            case .tooLarge: "This log is too large to import. Share a smaller text file (up to 512 KB)."
            }
        }
    }

    static func read(_ url: URL) throws -> String {
        guard url.isFileURL else { throw ReadError.unreadable }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        } catch {
            throw ReadError.unreadable
        }
        guard data.count <= maxBytes else { throw ReadError.tooLarge }
        // With LSSupportsOpeningDocumentsInPlace = NO the system hands us a
        // disposable copy in our Documents/Inbox. Never delete an original
        // in another Inbox, or follow a symlink outside our own directory.
        let inbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .resolvingSymlinksInPath().appendingPathComponent("Inbox", isDirectory: true)
        if url.resolvingSymlinksInPath().deletingLastPathComponent() == inbox {
            try? FileManager.default.removeItem(at: url)
        }
        return decode(data)
    }

    static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        return String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }
}
