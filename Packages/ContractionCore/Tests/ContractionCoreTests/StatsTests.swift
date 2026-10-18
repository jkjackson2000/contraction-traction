import XCTest
@testable import ContractionCore

final class StatsTests: XCTestCase {
    private let now = at(2026, 10, 18, 16, 0)
    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    /// `count` contractions `every` seconds apart lasting `duration`, the last
    /// one starting `lag` seconds before now.
    private func pattern(count: Int, every: TimeInterval, duration: TimeInterval,
                         lag: TimeInterval = 60) -> [ContractionRecord] {
        (0..<count).map { rec(ago(lag + Double(count - 1 - $0) * every), duration) }
    }

    // Providers ask for "how far apart" measured start to start, not the rest
    // between contractions.
    func testIntervalIsStartToStart() {
        let a = rec(ago(600), 60)
        let b = rec(ago(300), 90)
        XCTAssertEqual(Stats.intervals([a, b]), [b.id: 300])
        XCTAssertEqual(Stats.window([a, b], now: now).averageInterval, 300)
    }

    // Intervals feed every row of the list, so they must not depend on input
    // order, must include the live contraction, and must be defined for ties.
    func testIntervalsOrderTiesAndInProgress() {
        let first = rec(ago(900), 60)
        let tieA = rec(ago(600), 60)
        let tieB = rec(ago(600), 50)
        let live = rec(ago(100), nil)
        let result = Stats.intervals([live, tieA, first, tieB])
        XCTAssertNil(result[first.id])
        XCTAssertEqual(result[tieA.id], 300)
        XCTAssertEqual(result[tieB.id], 0) // later-listed of the tie
        XCTAssertEqual(result[live.id], 500)
        XCTAssertEqual(Stats.intervals([]), [:])
    }

    // "Last hour" is inclusive at both ends and ignores the live contraction
    // and anything dated in the future.
    func testWindowBoundaries() {
        let records = [
            rec(ago(3601), 40), rec(ago(3600), 50), rec(now, 70),
            rec(now.addingTimeInterval(10), 80), rec(ago(30), nil),
        ]
        let stats = Stats.window(records, now: now)
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats.averageDuration, 60)
        XCTAssertEqual(stats.averageInterval, 3600)
        XCTAssertEqual(Stats.window(records, now: now, length: 1800).count, 1)
    }

    // The home screen shows these averages; they must be exact means.
    func testAverages() {
        let records = [rec(ago(60), 80), rec(ago(600), 40), rec(ago(300), 60)]
        let stats = Stats.window(records, now: now)
        XCTAssertEqual(stats, WindowStats(count: 3, averageDuration: 60, averageInterval: 270))
        XCTAssertEqual(Stats.window([rec(ago(60), 45)], now: now),
                       WindowStats(count: 1, averageDuration: 45, averageInterval: nil))
        XCTAssertEqual(Stats.window([], now: now), WindowStats(count: 0, averageDuration: nil, averageInterval: nil))
    }

    // The banner tells parents it may be time to call; it must fire on a real
    // 5-1-1 hour and only for rules that hour satisfies.
    func testPatternMetOnRealisticHour() {
        let hour = pattern(count: 13, every: 300, duration: 60, lag: 30)
        XCTAssertTrue(PatternRule.fiveOneOne.isMet(by: hour, now: now))
        XCTAssertFalse(PatternRule.fourOneOne.isMet(by: hour, now: now))
        XCTAssertFalse(PatternRule.off.isMet(by: hour, now: now))
        // Slightly irregular real-world timings still qualify.
        let jittered = hour.enumerated().map { k, r in
            rec(r.start.addingTimeInterval(k % 2 == 0 ? 20 : -20), r.duration! + (k % 3 == 0 ? -8 : 6))
        }
        XCTAssertTrue(PatternRule.fiveOneOne.isMet(by: jittered, now: now))
    }

    // A 40-minute burst is not "an hour of data" no matter how regular.
    func testPatternNotMetWithShortSpan() {
        let burst = pattern(count: 15, every: 180, duration: 70) // 42 min
        XCTAssertFalse(PatternRule.fiveOneOne.isMet(by: burst, now: now))
        // Exactly 50 minutes is enough.
        XCTAssertTrue(PatternRule.fiveOneOne.isMet(by: pattern(count: 11, every: 300, duration: 60), now: now))
        XCTAssertFalse(PatternRule.fiveOneOne.isMet(by: pattern(count: 11, every: 299.0, duration: 60), now: now))
    }

    // Inclusive thresholds: maxInterval + 15 s and 50 s durations count.
    func testPatternBoundaries() {
        XCTAssertTrue(PatternRule.fiveOneOne.isMet(by: pattern(count: 12, every: 315, duration: 50), now: now))
        XCTAssertFalse(PatternRule.fiveOneOne.isMet(by: pattern(count: 12, every: 316, duration: 50), now: now))
        XCTAssertFalse(PatternRule.fiveOneOne.isMet(by: pattern(count: 12, every: 315, duration: 49), now: now))
        XCTAssertTrue(PatternRule.threeOneOne.isMet(by: pattern(count: 18, every: 195, duration: 50), now: now))
        XCTAssertFalse(PatternRule.threeOneOne.isMet(by: pattern(count: 18, every: 196, duration: 50), now: now))
    }

    // If contractions stopped, the banner must not keep saying the pattern
    // holds: the last one must be within maxInterval + 2 min.
    func testPatternNotMetWhenStale() {
        XCTAssertTrue(PatternRule.fiveOneOne.isMet(by: pattern(count: 12, every: 300, duration: 60, lag: 420), now: now))
        XCTAssertFalse(PatternRule.fiveOneOne.isMet(by: pattern(count: 12, every: 300, duration: 60, lag: 421), now: now))
    }

    // A live contraction is not yet a data point.
    func testPatternIgnoresInProgress() {
        var records = pattern(count: 11, every: 300, duration: 60, lag: 300)
        XCTAssertTrue(PatternRule.fiveOneOne.isMet(by: records, now: now))
        records.append(rec(ago(5), nil))
        XCTAssertTrue(PatternRule.fiveOneOne.isMet(by: records, now: now))
    }
}
