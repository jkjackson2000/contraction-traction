import XCTest
@testable import ContractionCore

final class QuickLogTests: XCTestCase {
    private let latest = at(2026, 10, 18, 15, 0)

    // "4 of them about every 5 min, the last one 10 min ago" must produce
    // exactly those four, oldest first, all marked approximate.
    func testSeriesOrderingAndSpacing() {
        let series = QuickLog.series(mostRecentStart: latest, count: 4, every: 300, duration: 60, note: "from memory")
        XCTAssertEqual(series.map(\.start), [-900.0, -600, -300, 0].map { latest.addingTimeInterval($0) })
        XCTAssertTrue(series.allSatisfy { $0.isApproximate && $0.duration == 60 && $0.note == "from memory" })
        XCTAssertEqual(Set(series.map(\.id)).count, 4)
    }

    // The stepper bounds are a UI promise; out-of-range input must not
    // produce zero or hundreds of rows.
    func testCountIsClamped() {
        XCTAssertEqual(QuickLog.series(mostRecentStart: latest, count: 0, every: 300, duration: 60).count, 1)
        XCTAssertEqual(QuickLog.series(mostRecentStart: latest, count: -5, every: 300, duration: 60).count, 1)
        XCTAssertEqual(QuickLog.series(mostRecentStart: latest, count: 20, every: 300, duration: 60).count, 20)
        XCTAssertEqual(QuickLog.series(mostRecentStart: latest, count: 25, every: 300, duration: 60).count, 20)
    }

    // Stored times are whole seconds; fractional input must not leak through
    // or make the spacing uneven.
    func testWholeSeconds() {
        let series = QuickLog.series(mostRecentStart: latest.addingTimeInterval(0.7), count: 3,
                                     every: 299.6, duration: 45.4)
        XCTAssertEqual(series.map(\.start), [latest.addingTimeInterval(-600), latest.addingTimeInterval(-300), latest])
        XCTAssertTrue(series.allSatisfy { $0.duration == 45 })
    }

    // Shared helper the app relies on for every stored time.
    func testDateWholeSecondsTruncates() {
        XCTAssertEqual(Date(timeIntervalSinceReferenceDate: 10.9).wholeSeconds,
                       Date(timeIntervalSinceReferenceDate: 10))
    }
}
