import Foundation

/// Reads a shared .txt log handed to the app by AirDrop, Files, or Messages.
/// Never throws: unreadable input becomes "" and the Import sheet shows its
/// normal empty state.
enum IncomingFile {
    /// Far above any real log; keeps parsing and the text editor responsive.
    static let maxBytes = 512 * 1024

    static func read(_ url: URL) -> String {
        guard url.isFileURL else { return "" }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var data = Data()
        if let handle = try? FileHandle(forReadingFrom: url) {
            data = (try? handle.read(upToCount: maxBytes)) ?? Data()
            try? handle.close()
        }
        // With LSSupportsOpeningDocumentsInPlace = NO the system hands us a
        // copy in Documents/Inbox; don't let those pile up.
        if url.pathComponents.contains("Inbox") {
            try? FileManager.default.removeItem(at: url)
        }
        return decode(data)
    }

    static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        // The size cap may have cut a multi-byte character in half.
        for trim in 1...3 where data.count > trim {
            if let text = String(data: data.dropLast(trim), encoding: .utf8) { return text }
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        return String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }
}
