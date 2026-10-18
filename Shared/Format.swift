import Foundation
import ContractionCore

/// Display-only formatting. Duration text comes from `LogText.formatDuration`
/// so the UI and the share text always agree.
enum Format {
    /// Stopwatch style: "0:42", "12:05", "1:02:03".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "58s", "~1m 05s".
    static func duration(_ seconds: TimeInterval, approximate: Bool = false) -> String {
        (approximate ? "~" : "") + LogText.formatDuration(seconds)
    }

    /// Start-to-start gap: "5m 12s" under an hour, else "1h 05m".
    static func interval(_ seconds: TimeInterval) -> String {
        guard seconds >= 3600 else { return LogText.formatDuration(seconds) }
        let minutes = Int(seconds / 60)
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }

    /// VoiceOver: "1 minute, 5 seconds".
    static func spoken(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(max(0, seconds)))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
