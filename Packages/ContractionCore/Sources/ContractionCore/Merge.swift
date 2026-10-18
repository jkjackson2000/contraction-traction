// Import planning: match incoming records (a pasted partner log) against the
// existing list. See `Merge` in API.swift for the rules.
//
// Self-collapse (rule 1) deliberately uses a narrower test than rule 2: two
// incoming records collapse only when their starts are within 1 s. Copies of
// the same exported entry (a log pasted twice, or shared again later with a
// duration or note edited) always share their start, and no two real
// contractions start in the same second. The rule-2 test (overlap, or within
// 45 s / 120 s) would also merge distinct entries of a single log: approximate
// entries two minutes apart in transition, or a quick-logged entry inside a
// long one whose timer was left running. That silently drops a contraction,
// so it is not used here. Pairing is still closest-first, keeping the
// earlier-listed record, and a kept record may absorb several copies, so a
// log pasted three times still yields one of each.

import Foundation

enum MergeImpl {

    private struct Span {
        let start: Double
        let end: Double
        let approximate: Bool

        init(_ record: ContractionRecord, now: Date) {
            start = record.start.timeIntervalSinceReferenceDate
            if let duration = record.duration, duration.isFinite {
                end = start + max(duration, 0)
            } else if record.duration == nil {
                end = max(start, now.timeIntervalSinceReferenceDate)
            } else {
                end = start
            }
            approximate = record.isApproximate
        }

        func overlaps(_ other: Span) -> Bool {
            max(start, other.start) < min(end, other.end)
        }

        func isCandidate(_ other: Span) -> Bool {
            let tolerance = approximate || other.approximate
                ? Merge.approximateTolerance : Merge.exactTolerance
            return overlaps(other) || abs(start - other.start) <= tolerance
        }
    }

    static func plan(existing: [ContractionRecord], incoming: [ContractionRecord],
                     now: Date) -> ImportPlan {
        let (kept, collapsedCount) = collapse(incoming, now: now)
        let existingSpans = existing.map { Span($0, now: now) }
        let keptSpans = kept.map { Span($0, now: now) }

        // Completed existing records sorted by start, for a windowed search.
        // In-progress ones span to `now` and are checked against everything.
        let completed = existing.indices
            .filter { existing[$0].duration != nil }
            .sorted { (existingSpans[$0].start, $0) < (existingSpans[$1].start, $1) }
        let inProgress = existing.indices.filter { existing[$0].duration == nil }
        let maxLength = completed.map { existingSpans[$0].end - existingSpans[$0].start }.max() ?? 0
        let reach = max(maxLength, Merge.approximateTolerance, Merge.exactTolerance)

        struct Pair {
            let distance: Double
            let existing: Int
            let incoming: Int
        }
        var pairs: [Pair] = []
        for (n, span) in keptSpans.enumerated() {
            let low = span.start - reach
            let high = max(span.end, span.start + Merge.approximateTolerance)
            var k = lowerBound(completed, low) { existingSpans[$0].start }
            while k < completed.count, existingSpans[completed[k]].start <= high {
                let e = completed[k]
                if existingSpans[e].isCandidate(span) {
                    pairs.append(Pair(distance: abs(span.start - existingSpans[e].start), existing: e, incoming: n))
                }
                k += 1
            }
            for e in inProgress where existingSpans[e].isCandidate(span) {
                pairs.append(Pair(distance: abs(span.start - existingSpans[e].start), existing: e, incoming: n))
            }
        }

        // Closest first; ties by earlier existing start, then earlier incoming.
        pairs.sort {
            ($0.distance, existingSpans[$0.existing].start, $0.existing, keptSpans[$0.incoming].start, $0.incoming)
                < ($1.distance, existingSpans[$1.existing].start, $1.existing, keptSpans[$1.incoming].start, $1.incoming)
        }

        var existingUsed = [Bool](repeating: false, count: existing.count)
        var incomingUsed = [Bool](repeating: false, count: kept.count)
        var matches: [ImportPlan.Match] = []
        var identicalCount = 0
        for pair in pairs where !existingUsed[pair.existing] && !incomingUsed[pair.incoming] {
            existingUsed[pair.existing] = true
            incomingUsed[pair.incoming] = true
            let mine = existing[pair.existing]
            let theirs = kept[pair.incoming]
            if isIdentical(mine, theirs) {
                identicalCount += 1
            } else {
                matches.append(ImportPlan.Match(existing: mine, incoming: theirs,
                                                startDelta: theirs.start.timeIntervalSince(mine.start),
                                                suggested: suggestion(mine: mine, theirs: theirs)))
            }
        }

        let additions = LogTextImpl.sortedByStart(kept.indices.filter { !incomingUsed[$0] }.map { kept[$0] })
        let orderedMatches = matches.enumerated().sorted {
            ($0.element.existing.start, $0.element.incoming.start, $0.offset)
                < ($1.element.existing.start, $1.element.incoming.start, $1.offset)
        }.map(\.element)

        return ImportPlan(additions: additions, matches: orderedMatches,
                          identicalCount: identicalCount, collapsedIncomingCount: collapsedCount)
    }

    static func apply(_ resolution: MatchResolution, to match: ImportPlan.Match) -> ContractionRecord {
        switch resolution {
        case .keepMine:
            return match.existing
        case .useTheirs:
            return ContractionRecord(id: match.existing.id,
                                     start: match.incoming.start,
                                     duration: match.incoming.duration,
                                     isApproximate: match.incoming.isApproximate,
                                     note: combinedNote(mine: match.existing.note, theirs: match.incoming.note))
        }
    }

    // MARK: - Helpers

    private static let selfDuplicateTolerance: TimeInterval = 1

    /// Rule 1 (see the file comment). Returns kept incoming records, in input
    /// order, and the number collapsed into an earlier-listed copy.
    private static func collapse(_ incoming: [ContractionRecord], now: Date) -> ([ContractionRecord], Int) {
        guard incoming.count > 1 else { return (incoming, 0) }
        let spans = incoming.map { Span($0, now: now) }
        let order = incoming.indices.sorted { (spans[$0].start, $0) < (spans[$1].start, $1) }

        var pairs: [(distance: Double, first: Int, second: Int)] = []
        for a in order.indices {
            let x = order[a]
            var b = a + 1
            while b < order.count {
                let y = order[b]
                let distance = spans[y].start - spans[x].start
                if distance > selfDuplicateTolerance { break }
                pairs.append((distance, min(x, y), max(x, y)))
                b += 1
            }
        }
        pairs.sort { ($0.distance, $0.first, $0.second) < ($1.distance, $1.first, $1.second) }

        var collapsed = [Bool](repeating: false, count: incoming.count)
        var count = 0
        for pair in pairs where !collapsed[pair.first] && !collapsed[pair.second] {
            collapsed[pair.second] = true
            count += 1
        }
        return (incoming.indices.filter { !collapsed[$0] }.map { incoming[$0] }, count)
    }

    /// Start and duration within 1 s, same approximate flag, and the same
    /// note or an empty incoming note. Notes compare as exported (newlines
    /// as spaces, trimmed) so a re-imported export is recognized.
    private static func isIdentical(_ mine: ContractionRecord, _ theirs: ContractionRecord) -> Bool {
        guard abs(theirs.start.timeIntervalSince(mine.start)) <= 1,
              mine.isApproximate == theirs.isApproximate else { return false }
        switch (mine.duration, theirs.duration) {
        case (nil, nil): break
        case let (a?, b?): guard abs(a - b) <= 1 else { return false }
        default: return false
        }
        let theirNote = LogTextImpl.normalizedNote(theirs.note)
        return theirNote.isEmpty || theirNote == LogTextImpl.normalizedNote(mine.note)
    }

    private static func suggestion(mine: ContractionRecord, theirs: ContractionRecord) -> MatchResolution {
        if mine.isInProgress { return .keepMine }
        return mine.isApproximate && !theirs.isApproximate ? .useTheirs : .keepMine
    }

    private static func combinedNote(mine: String, theirs: String) -> String {
        let a = LogTextImpl.normalizedNote(mine)
        let b = LogTextImpl.normalizedNote(theirs)
        if b.isEmpty || a == b { return mine }
        if a.isEmpty { return theirs }
        return mine.trimmingCharacters(in: .whitespacesAndNewlines) + "; "
            + theirs.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// First position in `sorted` whose key is ≥ `value`.
    private static func lowerBound(_ sorted: [Int], _ value: Double, key: (Int) -> Double) -> Int {
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if key(sorted[mid]) < value { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
