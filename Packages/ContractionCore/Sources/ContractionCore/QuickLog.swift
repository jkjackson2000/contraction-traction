// Backfill a series of remembered contractions. See `QuickLog` in API.swift.

import Foundation

enum QuickLogImpl {
    static func series(mostRecentStart: Date, count: Int, every: TimeInterval,
                       duration: TimeInterval, note: String) -> [ContractionRecord] {
        let n = min(max(count, 1), 20)
        // Whole-second spacing so every start lands on a whole second.
        let step = every.isFinite ? max(every.rounded(), 0) : 0
        let latest = mostRecentStart.wholeSeconds
        return (0..<n).reversed().map { k in
            ContractionRecord(start: latest.addingTimeInterval(-Double(k) * step),
                              duration: duration, isApproximate: true, note: note)
        }
    }
}
