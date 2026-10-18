// Public contract for ContractionCore. The app depends only on what is
// declared here. Signatures are fixed; bodies marked `fatalError` are to be
// implemented in separate files (this file keeps the types and docs).
//
// Pure value logic: no SwiftData, no UIKit, no I/O. Every function that
// depends on the current time takes `now` explicitly so it is testable.

import Foundation

// MARK: - Record

/// One contraction. All times are whole seconds (see `Date.wholeSeconds`).
public struct ContractionRecord: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var start: Date
    /// nil while the contraction is in progress.
    public var duration: TimeInterval?
    /// Entered from memory or otherwise estimated; shown with "~".
    public var isApproximate: Bool
    /// Single line; newlines are replaced by spaces on export.
    public var note: String

    public init(id: UUID = UUID(), start: Date, duration: TimeInterval?,
                isApproximate: Bool = false, note: String = "") {
        self.id = id
        self.start = start.wholeSeconds
        self.duration = duration.map { $0.rounded() }
        self.isApproximate = isApproximate
        self.note = note
    }

    public var end: Date? { duration.map { start.addingTimeInterval($0) } }
    public var isInProgress: Bool { duration == nil }
}

public extension Date {
    /// Truncated to whole seconds since the reference date.
    var wholeSeconds: Date {
        Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.rounded(.down))
    }
}

/// Validation limits shared by manual entry, parsing, and import.
public enum Limits {
    public static let minDuration: TimeInterval = 1
    public static let maxDuration: TimeInterval = 600
    /// A start later than `now + futureTolerance` is invalid.
    public static let futureTolerance: TimeInterval = 300
}

// MARK: - Plain-text log (share + import)

/// The share format is plain text a human can read in iMessage or Notes and
/// that this app can parse back after a copy/paste. Export example:
///
///     Contraction Traction log
///     12 contractions · Oct 18, 2:10 PM – 3:42 PM
///     Time zone: America/Chicago (UTC-05:00)
///     ~ = approximate
///
///     2026-10-18 2:10:03 PM · 58s
///     2026-10-18 2:15:40 PM · ~1m 05s · back pain
///
/// Export rules:
/// - Entry lines oldest first: `yyyy-MM-dd h:mm:ss a` (en_US_POSIX, in the
///   export time zone) ` · ` duration [` · ` note]. Note omitted when empty.
/// - Duration: `Ns` under a minute, else `Nm SSs` (seconds zero-padded),
///   prefixed with `~` when approximate.
/// - In-progress contractions are omitted.
/// - Newlines in notes become spaces.
///
/// Parse rules (lenient, so hand-typed or lightly edited logs still work):
/// - Lines that do not start with a `yyyy-MM-dd` date are ignored (headers,
///   blank lines, chat text around the pasted block).
/// - Time: `h:mm[:ss] AM/PM` (case-insensitive) or 24-hour `H:mm[:ss]`. Date
///   and time may be separated by a space or `T`.
/// - Optional per-line UTC offset after the time (`-05:00`, `-0500`, `Z`)
///   overrides the zone. Otherwise the `Time zone:` header (identifier first,
///   else the `UTC±HH:MM` in parentheses), otherwise `defaultTimeZone`.
/// - Field separators: `·`, `•`, `|`, or a tab, with optional surrounding
///   whitespace.
/// - Duration: `58s`, `1m`, `1m 05s`, `1m5s`, `1:05`, `90` (bare = seconds);
///   a leading `~` means approximate.
/// - Everything after the duration's separator is the note, trimmed.
/// - A dated line whose time or duration does not parse, or that violates
///   `Limits` relative to `now`, goes to `rejectedLines` (verbatim, trimmed).
/// - Parsed records get fresh UUIDs.
public enum LogText {
    public static func export(_ records: [ContractionRecord],
                              timeZone: TimeZone = .current) -> String {
        LogTextImpl.export(records, timeZone: timeZone)
    }

    public static func parse(_ text: String,
                             defaultTimeZone: TimeZone = .current,
                             now: Date = .now) -> ParseResult {
        LogTextImpl.parse(text, defaultTimeZone: defaultTimeZone, now: now)
    }

    /// Duration as shown in the UI and export, without `~`: "58s", "1m 05s".
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        LogTextImpl.formatDuration(seconds)
    }
}

public struct ParseResult: Sendable, Equatable {
    /// Valid entries, sorted by start.
    public var records: [ContractionRecord]
    /// Dated lines that could not be used.
    public var rejectedLines: [String]

    public init(records: [ContractionRecord], rejectedLines: [String]) {
        self.records = records
        self.rejectedLines = rejectedLines
    }
}

// MARK: - Merge (import review)

/// What to do with a matched pair (same real contraction tracked on two
/// phones, or remembered and tracked).
public enum MatchResolution: String, Sendable, CaseIterable {
    /// Leave the existing row as is.
    case keepMine
    /// Overwrite the existing row's start, duration, and approximate flag
    /// with the incoming values (notes are combined, see `Merge.apply`).
    case useTheirs
}

public struct ImportPlan: Sendable, Equatable {
    /// Incoming records with no counterpart in the existing list; added on
    /// confirm (the user can deselect individual ones in the UI).
    public var additions: [ContractionRecord]
    /// Incoming records that matched an existing one and differ from it.
    public var matches: [Match]
    /// Count of incoming records identical to an existing one (start and
    /// duration within 1 s, same approximate flag, same note or incoming note
    /// empty). Nothing to decide; reported as "already in your list".
    public var identicalCount: Int
    /// Incoming records collapsed because they duplicated another incoming
    /// record (e.g. the same log pasted twice).
    public var collapsedIncomingCount: Int

    public struct Match: Sendable, Equatable, Identifiable {
        public var id: UUID { existing.id }
        public var existing: ContractionRecord
        public var incoming: ContractionRecord
        /// incoming.start − existing.start.
        public var startDelta: TimeInterval
        /// Default choice. `useTheirs` only when incoming is exact and existing
        /// is approximate; otherwise `keepMine`. Always `keepMine` when the
        /// existing record is in progress.
        public var suggested: MatchResolution

        public init(existing: ContractionRecord, incoming: ContractionRecord,
                    startDelta: TimeInterval, suggested: MatchResolution) {
            self.existing = existing
            self.incoming = incoming
            self.startDelta = startDelta
            self.suggested = suggested
        }
    }

    public init(additions: [ContractionRecord], matches: [Match],
                identicalCount: Int, collapsedIncomingCount: Int) {
        self.additions = additions
        self.matches = matches
        self.identicalCount = identicalCount
        self.collapsedIncomingCount = collapsedIncomingCount
    }
}

/// Matching rules:
/// 1. Collapse incoming against itself first with the same pairing rule
///    (keep the earlier-listed record).
/// 2. Two records are candidates when their [start, end] ranges overlap, or
///    |Δstart| ≤ `exactTolerance` (both exact) / `approximateTolerance`
///    (either approximate). An in-progress existing record spans
///    [start, now].
/// 3. Pair one-to-one, closest |Δstart| first (greedy over all candidate
///    pairs; ties broken by earlier existing start). Each existing record
///    absorbs at most one incoming record, so two real back-to-back
///    contractions never collapse into one.
/// 4. Nothing existing is ever deleted. Unmatched incoming → `additions`.
public enum Merge {
    public static let exactTolerance: TimeInterval = 45
    public static let approximateTolerance: TimeInterval = 120

    public static func plan(existing: [ContractionRecord],
                            incoming: [ContractionRecord],
                            now: Date = .now) -> ImportPlan {
        MergeImpl.plan(existing: existing, incoming: incoming, now: now)
    }

    /// The record the existing row becomes under `resolution`. Keeps
    /// `existing.id`. Notes: with `useTheirs`, the result's note is the
    /// non-empty one, or "mine; theirs" when both are non-empty and differ.
    /// With `keepMine`, returns `existing` unchanged.
    public static func apply(_ resolution: MatchResolution,
                             to match: ImportPlan.Match) -> ContractionRecord {
        MergeImpl.apply(resolution, to: match)
    }
}

// MARK: - Stats

public struct WindowStats: Sendable, Equatable {
    /// Completed contractions starting within the window.
    public var count: Int
    public var averageDuration: TimeInterval?
    /// Mean start-to-start interval between consecutive contractions in the
    /// window (needs count ≥ 2).
    public var averageInterval: TimeInterval?

    public init(count: Int, averageDuration: TimeInterval?, averageInterval: TimeInterval?) {
        self.count = count
        self.averageDuration = averageDuration
        self.averageInterval = averageInterval
    }
}

public enum Stats {
    /// Stats over completed records with start in [now − length, now].
    public static func window(_ records: [ContractionRecord], now: Date = .now,
                              length: TimeInterval = 3600) -> WindowStats {
        StatsImpl.window(records, now: now, length: length)
    }

    /// Start-to-previous-start interval per record id (completed or not).
    /// The earliest record has no entry. Records with equal starts: the
    /// later-listed one gets interval 0.
    public static func intervals(_ records: [ContractionRecord]) -> [UUID: TimeInterval] {
        StatsImpl.intervals(records)
    }
}

/// "X-1-1": contractions about X minutes apart, lasting about 1 minute, for
/// about an hour. Informational only.
public enum PatternRule: String, Sendable, CaseIterable, Codable {
    case fiveOneOne, fourOneOne, threeOneOne, off

    public var maxInterval: TimeInterval? {
        switch self {
        case .fiveOneOne: 300
        case .fourOneOne: 240
        case .threeOneOne: 180
        case .off: nil
        }
    }

    public var title: String {
        switch self {
        case .fiveOneOne: "5-1-1"
        case .fourOneOne: "4-1-1"
        case .threeOneOne: "3-1-1"
        case .off: "Off"
        }
    }

    /// Let W = completed records starting in [now − 60 min, now], by start.
    /// Met when all hold:
    /// - W.count ≥ 6
    /// - W.last.start − W.first.start ≥ 50 min (an hour of data, not a burst)
    /// - average interval in W ≤ maxInterval + 15 s
    /// - average duration in W ≥ 50 s
    /// - now − W.last.start ≤ maxInterval + 120 s (pattern is current)
    public func isMet(by records: [ContractionRecord], now: Date = .now) -> Bool {
        StatsImpl.isMet(self, records: records, now: now)
    }
}

// MARK: - Quick log (backfill from memory)

public enum QuickLog {
    /// `count` approximate contractions going back in time: the most recent
    /// starts at `mostRecentStart`, each earlier one `every` seconds before
    /// the previous. All get `duration` and `isApproximate = true`. Returned
    /// oldest first. `count` is clamped to 1...20.
    public static func series(mostRecentStart: Date, count: Int,
                              every: TimeInterval, duration: TimeInterval,
                              note: String = "") -> [ContractionRecord] {
        QuickLogImpl.series(mostRecentStart: mostRecentStart, count: count,
                            every: every, duration: duration, note: note)
    }
}
