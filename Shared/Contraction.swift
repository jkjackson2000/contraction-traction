import Foundation
import SwiftData
import ContractionCore

/// Persistent row. Maps 1:1 to `ContractionRecord`; durations, intervals,
/// and stats are always derived, never stored.
@Model
final class Contraction {
    @Attribute(.unique) var id: UUID
    var start: Date
    /// nil while in progress (at most one at a time, enforced by the store).
    var duration: Double?
    var isApproximate: Bool
    var note: String

    init(_ record: ContractionRecord) {
        id = record.id
        start = record.start
        duration = record.duration
        isApproximate = record.isApproximate
        note = record.note
    }

    var record: ContractionRecord {
        ContractionRecord(id: id, start: start, duration: duration,
                          isApproximate: isApproximate, note: note)
    }

    func apply(_ record: ContractionRecord) {
        start = record.start
        duration = record.duration
        isApproximate = record.isApproximate
        note = record.note
    }
}

enum AppGroup {
    static let id = "group.com.jaredjackson.ContractionTraction"
}

enum SettingsKey {
    static let patternRule = "patternRule"
    static let keepScreenAwake = "keepScreenAwake"
    static let liveActivityEnabled = "liveActivityEnabled"
    static let hasSeenDisclaimer = "hasSeenDisclaimer"
}

extension UserDefaults {
    /// App Group defaults, so the app and the Live Activity intent agree on
    /// settings whichever process runs.
    static let shared: UserDefaults = UserDefaults(suiteName: AppGroup.id) ?? .standard

    var liveActivityEnabled: Bool {
        object(forKey: SettingsKey.liveActivityEnabled) as? Bool ?? true
    }
}
