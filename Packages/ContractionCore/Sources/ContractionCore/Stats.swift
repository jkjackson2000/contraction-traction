// Window stats, per-record intervals, and the X-1-1 pattern rule. See
// `Stats` and `PatternRule` in API.swift.

import Foundation

enum StatsImpl {

    static func window(_ records: [ContractionRecord], now: Date, length: TimeInterval) -> WindowStats {
        stats(of: windowRecords(records, now: now, length: length))
    }

    static func intervals(_ records: [ContractionRecord]) -> [UUID: TimeInterval] {
        let sorted = LogTextImpl.sortedByStart(records)
        var result: [UUID: TimeInterval] = [:]
        result.reserveCapacity(sorted.count)
        for k in sorted.indices.dropFirst() {
            result[sorted[k].id] = sorted[k].start.timeIntervalSince(sorted[k - 1].start)
        }
        return result
    }

    static func isMet(_ rule: PatternRule, records: [ContractionRecord], now: Date) -> Bool {
        guard let maxInterval = rule.maxInterval else { return false }
        let w = windowRecords(records, now: now, length: 3600)
        let stats = stats(of: w)
        guard w.count >= 6, let first = w.first, let last = w.last,
              let averageInterval = stats.averageInterval,
              let averageDuration = stats.averageDuration else { return false }
        return last.start.timeIntervalSince(first.start) >= 50 * 60
            && averageInterval <= maxInterval + 15
            && averageDuration >= 50
            && now.timeIntervalSince(last.start) <= maxInterval + 120
    }

    /// `w` must be completed records sorted by start.
    private static func stats(of w: [ContractionRecord]) -> WindowStats {
        guard let first = w.first, let last = w.last else {
            return WindowStats(count: 0, averageDuration: nil, averageInterval: nil)
        }
        let totalDuration = w.reduce(0) { $0 + ($1.duration ?? 0) }
        // The mean of consecutive start-to-start gaps telescopes to span / (n − 1).
        let averageInterval = w.count >= 2
            ? last.start.timeIntervalSince(first.start) / Double(w.count - 1)
            : nil
        return WindowStats(count: w.count,
                           averageDuration: totalDuration / Double(w.count),
                           averageInterval: averageInterval)
    }

    /// Completed records with start in [now − length, now], by start.
    private static func windowRecords(_ records: [ContractionRecord], now: Date,
                                      length: TimeInterval) -> [ContractionRecord] {
        let earliest = now.addingTimeInterval(-length)
        return LogTextImpl.sortedByStart(records.filter {
            !$0.isInProgress && $0.start >= earliest && $0.start <= now
        })
    }
}
