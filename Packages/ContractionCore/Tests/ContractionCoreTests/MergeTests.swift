import XCTest
@testable import ContractionCore

final class MergeTests: XCTestCase {
    private let t0 = at(2026, 10, 18, 15, 0)
    private func t(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
    private var later: Date { t0.addingTimeInterval(6 * 3600) }

    /// Simulates the share sheet: export on one phone, paste on the other.
    private func share(_ records: [ContractionRecord], now: Date) -> [ContractionRecord] {
        LogText.parse(LogText.export(records, timeZone: TZ.chicago), defaultTimeZone: TZ.tokyo, now: now).records
    }

    // Re-importing your own share must be a no-op, including approximate
    // entries and notes that were flattened to one line on export.
    func testReimportOwnExportIsAllIdentical() {
        let mine = [
            rec(t(0), 58), rec(t(300), 65, approx: true, note: "back pain"),
            rec(t(610), 72, note: "two\nlines"), rec(t(900), 600),
            rec(t(1200), 1, approx: true), // inside the 10-minute one: still its own entry
            rec(t(1500), nil), // in progress: not exported, must stay untouched
        ]
        let plan = Merge.plan(existing: mine, incoming: share(mine, now: t(1530)), now: t(1530))
        XCTAssertEqual(plan.identicalCount, 5)
        XCTAssertEqual(plan.additions, [])
        XCTAssertEqual(plan.matches, [])
        XCTAssertEqual(plan.collapsedIncomingCount, 0)
    }

    // Two phones tracking the same contraction never agree to the second;
    // offsets of 5–30 s must pair up, not duplicate.
    func testPartnerOffsetsMatchInsteadOfAdding() {
        let mine = (0..<6).map { rec(t(Double($0) * 300), 60) }
        let offsets: [TimeInterval] = [5, -12, 30, -30, 18, -5]
        let theirs = mine.enumerated().map { k, r in rec(r.start.addingTimeInterval(offsets[k]), 60 + offsets[k] / 3) }
        let plan = Merge.plan(existing: mine, incoming: theirs, now: later)
        XCTAssertEqual(plan.additions, [])
        XCTAssertEqual(plan.matches.count, 6)
        XCTAssertEqual(plan.matches.map(\.startDelta), offsets)
        XCTAssertEqual(plan.matches.map(\.existing.id), mine.map(\.id))
        XCTAssertTrue(plan.matches.allSatisfy { $0.suggested == .keepMine })
    }

    // Two real contractions 2–3 min apart, one tracked on each phone, are
    // both real: neither may swallow the other.
    func testBackToBackRealContractionsAreBothKept() {
        for gap in [120.0, 150, 180] {
            let mine = [rec(t(0), 60)]
            let theirs = [rec(t(gap), 60)]
            let plan = Merge.plan(existing: mine, incoming: theirs, now: later)
            XCTAssertEqual(plan.additions.map(\.start), [t(gap)], "gap \(gap)")
            XCTAssertEqual(plan.matches, [])
        }
        // Approximate entries 3 min apart are still two contractions.
        let plan = Merge.plan(existing: [rec(t(0), 60, approx: true)],
                              incoming: [rec(t(180), 60, approx: true)], now: later)
        XCTAssertEqual(plan.additions.count, 1)
    }

    // One-to-one pairing: an incoming record overlapping two existing ones
    // pairs with the closest only; the other existing row is untouched.
    func testIncomingOverlappingTwoExistingPairsWithClosestOnly() {
        let a = rec(t(0), 90)       // 0–90
        let b = rec(t(120), 60)     // 120–180
        let incoming = rec(t(70), 80) // 70–150 overlaps both; Δa 70, Δb 50
        let plan = Merge.plan(existing: [a, b], incoming: [incoming], now: later)
        XCTAssertEqual(plan.matches.map(\.existing.id), [b.id])
        XCTAssertEqual(plan.matches.first?.startDelta, -50)
        XCTAssertEqual(plan.additions, [])
        XCTAssertEqual(plan.identicalCount, 0)
    }

    // Equal distances must resolve deterministically (earlier existing start)
    // so the review screen never flickers between runs.
    func testTieBreaksTowardEarlierExisting() {
        let a = rec(t(0), 90)
        let b = rec(t(120), 60)
        let plan = Merge.plan(existing: [b, a], incoming: [rec(t(60), 90)], now: later)
        XCTAssertEqual(plan.matches.map(\.existing.id), [a.id])
    }

    // Greedy over all pairs, not per incoming in list order: a per-row greedy
    // would steal y for p and leave q mismatched with x.
    func testPairingIsGlobalClosestFirst() {
        let x = rec(t(0), 40, approx: true)
        let y = rec(t(90), 40, approx: true)
        let p = rec(t(50), 30, approx: true)  // Δx 50, Δy 40
        let q = rec(t(95), 30, approx: true)  // Δy 5, Δx 95
        let plan = Merge.plan(existing: [x, y], incoming: [p, q], now: later)
        XCTAssertEqual(Set(plan.matches.map { "\($0.existing.id)>\($0.incoming.id)" }),
                       ["\(x.id)>\(p.id)", "\(y.id)>\(q.id)"])
        XCTAssertEqual(plan.additions, [])
    }

    // A contraction she is timing right now and he logged on his phone is the
    // same one; her live timer must win by default.
    func testOverlapWithInProgressExistingSuggestsKeepMine() {
        let live = rec(t(0), nil)
        let plan = Merge.plan(existing: [live], incoming: [rec(t(60), 60)], now: t(90))
        XCTAssertEqual(plan.matches.count, 1, "Δ60 > 45 s; only the [start, now] span makes them overlap")
        XCTAssertEqual(plan.matches.first?.suggested, .keepMine)
        XCTAssertEqual(plan.additions, [])

        // Even an approximate in-progress row (which would otherwise suggest
        // useTheirs against an exact incoming one) keeps mine.
        let approxLive = rec(t(0), nil, approx: true)
        let plan2 = Merge.plan(existing: [approxLive], incoming: [rec(t(10), 60)], now: t(30))
        XCTAssertEqual(plan2.matches.first?.suggested, .keepMine)

        // Before `now` reaches it, a later incoming record does not overlap.
        let plan3 = Merge.plan(existing: [live], incoming: [rec(t(60), 60)], now: t(5))
        XCTAssertEqual(plan3.additions.count, 1)
    }

    // Remembered times are fuzzy, so approximate entries match within 120 s;
    // exact ones 60 s apart that do not overlap are separate contractions.
    func testApproximateToleranceVersusExact() {
        let mine = [rec(t(0), 30)]
        XCTAssertEqual(Merge.plan(existing: mine, incoming: [rec(t(110), 30, approx: true)], now: later).matches.count, 1)
        XCTAssertEqual(Merge.plan(existing: mine, incoming: [rec(t(120), 30, approx: true)], now: later).matches.count, 1)
        XCTAssertEqual(Merge.plan(existing: mine, incoming: [rec(t(121), 30, approx: true)], now: later).additions.count, 1)
        XCTAssertEqual(Merge.plan(existing: mine, incoming: [rec(t(60), 30)], now: later).additions.count, 1)
        XCTAssertEqual(Merge.plan(existing: mine, incoming: [rec(t(45), 10)], now: later).matches.count, 1)
        XCTAssertEqual(Merge.plan(existing: mine, incoming: [rec(t(46), 10)], now: later).additions.count, 1)
    }

    // The same log pasted twice (or three times) must not double the import.
    func testPastedLogTwiceCollapses() {
        let theirs = (0..<5).map { rec(t(Double($0) * 300), 60, approx: $0 == 2, note: $0 == 1 ? "a" : "") }
        let text = LogText.export(theirs, timeZone: TZ.chicago)
        let twice = LogText.parse(text + "\n" + text, defaultTimeZone: TZ.chicago, now: later).records
        let plan = Merge.plan(existing: [], incoming: twice, now: later)
        XCTAssertEqual(plan.collapsedIncomingCount, 5)
        XCTAssertEqual(plan.additions.map(\.start), theirs.map(\.start))

        let thrice = LogText.parse([text, text, text].joined(separator: "\n"), defaultTimeZone: TZ.chicago, now: later).records
        let plan3 = Merge.plan(existing: theirs, incoming: thrice, now: later)
        XCTAssertEqual(plan3.collapsedIncomingCount, 10)
        XCTAssertEqual(plan3.identicalCount, 5)
        XCTAssertEqual(plan3.additions, [])
    }

    // Self-collapse only merges copies (same start second). Distinct entries
    // of one log must survive even when they look alike: approximate ones
    // 100 s apart, or a quick-logged one inside a long, mis-stopped one.
    func testSelfCollapseOnlyMergesCopies() {
        let neighbors = [rec(t(0), 50, approx: true), rec(t(100), 50, approx: true)]
        XCTAssertEqual(Merge.plan(existing: [], incoming: neighbors, now: later).additions.count, 2)
        let nested = [rec(t(0), 600), rec(t(200), 40, approx: true)]
        XCTAssertEqual(Merge.plan(existing: [], incoming: nested, now: later).additions.count, 2)

        // A copy re-shared after an edit (same start, new duration and note)
        // collapses, keeping the earlier-listed one.
        let first = rec(t(0), 60)
        let edited = rec(t(0), 75, note: "edited")
        let plan = Merge.plan(existing: [], incoming: [first, edited, rec(t(0), 60)], now: later)
        XCTAssertEqual(plan.collapsedIncomingCount, 2)
        XCTAssertEqual(plan.additions.map(\.id), [first.id])
    }

    // A pathological paste (thousands of copies) must not freeze the app.
    func testSelfCollapseOfManyCopiesIsFast() {
        let copies = (0..<20_000).map { _ in rec(t(0), 60) }
        let clock = ContinuousClock()
        var plan = ImportPlan(additions: [], matches: [], identicalCount: 0, collapsedIncomingCount: 0)
        let elapsed = clock.measure { plan = Merge.plan(existing: [], incoming: copies, now: later) }
        XCTAssertEqual(plan.collapsedIncomingCount, 19_999)
        XCTAssertLessThan(elapsed, .seconds(1))
    }

    // She shares to him, he shares back: nothing may come back as "new".
    func testRoundTripAtoBtoAAddsNothing() {
        let a: [ContractionRecord] = (0..<10).map { (k: Int) -> ContractionRecord in
            rec(t(Double(k) * 300), 60 + Double(k), approx: k == 7, note: k == 4 ? "x" : "")
        }
        // B tracked #3 and #4 himself, slightly off; his #4 is approximate.
        let b3 = rec(a[3].start.addingTimeInterval(12), 55)
        let b4 = rec(a[4].start.addingTimeInterval(-8), 70, approx: true)
        var b = [b3, b4]

        let planB = Merge.plan(existing: b, incoming: share(a, now: later), now: later)
        XCTAssertEqual(planB.additions.count, 8)
        XCTAssertEqual(planB.matches.count, 2)
        for match in planB.matches {
            let index = b.firstIndex { $0.id == match.existing.id }!
            b[index] = Merge.apply(match.suggested, to: match)
        }
        b += planB.additions

        let planA = Merge.plan(existing: a, incoming: share(b, now: later), now: later)
        XCTAssertEqual(planA.additions, [])
        XCTAssertEqual(planA.collapsedIncomingCount, 0)
        XCTAssertEqual(planA.identicalCount + planA.matches.count, 10)
        XCTAssertEqual(planA.matches.map(\.existing.id), [a[3].id]) // only B's own differing #3
    }

    // A precise timing beats a remembered one; otherwise the receiver's own
    // record is the safer default.
    func testSuggestedResolution() {
        func suggestion(mineApprox: Bool, theirsApprox: Bool) -> MatchResolution? {
            Merge.plan(existing: [rec(t(0), 60, approx: mineApprox)],
                       incoming: [rec(t(20), 62, approx: theirsApprox)], now: later).matches.first?.suggested
        }
        XCTAssertEqual(suggestion(mineApprox: true, theirsApprox: false), .useTheirs)
        XCTAssertEqual(suggestion(mineApprox: true, theirsApprox: true), .keepMine)
        XCTAssertEqual(suggestion(mineApprox: false, theirsApprox: false), .keepMine)
        XCTAssertEqual(suggestion(mineApprox: false, theirsApprox: true), .keepMine)
    }

    // Identical means nothing to decide; any real difference must be shown.
    func testIdenticalDefinition() {
        let mine = rec(t(0), 60, note: "mine")
        func identical(_ incoming: ContractionRecord) -> Bool {
            Merge.plan(existing: [mine], incoming: [incoming], now: later).identicalCount == 1
        }
        XCTAssertTrue(identical(rec(t(1), 61)))                   // within 1 s, empty note
        XCTAssertTrue(identical(rec(t(0), 60, note: " mine ")))   // same note as exported
        XCTAssertFalse(identical(rec(t(2), 60)))
        XCTAssertFalse(identical(rec(t(0), 62)))
        XCTAssertFalse(identical(rec(t(0), 60, approx: true)))
        XCTAssertFalse(identical(rec(t(0), 60, note: "theirs")))
    }

    // "Use theirs" must keep both people's notes and the row's identity.
    func testApplyCombinesNotes() {
        func applied(_ mine: String, _ theirs: String) -> ContractionRecord {
            let match = ImportPlan.Match(existing: rec(t(0), 60, approx: true, note: mine),
                                         incoming: rec(t(10), 70, note: theirs),
                                         startDelta: 10, suggested: .useTheirs)
            return Merge.apply(.useTheirs, to: match)
        }
        XCTAssertEqual(applied("", "").note, "")
        XCTAssertEqual(applied("mine", "").note, "mine")
        XCTAssertEqual(applied("", "theirs").note, "theirs")
        XCTAssertEqual(applied("same", "same").note, "same")
        XCTAssertEqual(applied("mine", "theirs").note, "mine; theirs")
        // Sharing back and forth must not keep appending the same notes.
        XCTAssertEqual(applied("back pain; tired", "tired").note, "back pain; tired")
        XCTAssertEqual(applied("tired", "back pain; tired").note, "back pain; tired")

        let existing = rec(t(0), 60, approx: true, note: "m")
        let match = ImportPlan.Match(existing: existing, incoming: rec(t(10), 70, note: "t"),
                                     startDelta: 10, suggested: .useTheirs)
        let used = Merge.apply(.useTheirs, to: match)
        XCTAssertEqual(used.id, existing.id)
        XCTAssertEqual(used.start, t(10))
        XCTAssertEqual(used.duration, 70)
        XCTAssertFalse(used.isApproximate)
        XCTAssertEqual(Merge.apply(.keepMine, to: match), existing)
    }

    // The motivating scenario: she has 1:00–1:30 and 2:00–2:30, he covered
    // 1:25–2:05. Only his contractions in her gap are new.
    func testGapFill() {
        let one = at(2026, 10, 18, 13, 0)
        func minute(_ m: Double) -> Date { one.addingTimeInterval(m * 60) }
        let hersStarts: [Double] = [0, 5, 10, 15, 20, 25, 30, 60, 65, 70, 75, 80, 85, 90]
        let hers: [ContractionRecord] = hersStarts.map { rec(minute($0), 60) }
        let hisStarts: [Double] = (0...8).map { 25 + 20.0 / 60 + 5 * Double($0) } // 1:25:20 … 2:05:20
        let his: [ContractionRecord] = hisStarts.enumerated().map { k, m in rec(minute(m), 55, approx: k % 2 == 0) }
        let plan = Merge.plan(existing: hers, incoming: his, now: later)
        let gapStarts: [Date] = hisStarts[2...6].map { minute($0) } // 1:35:20 … 1:55:20
        XCTAssertEqual(plan.additions.map(\.start), gapStarts)
        XCTAssertEqual(plan.matches.count, 4) // 1:25, 1:30, 2:00, 2:05
        XCTAssertEqual(plan.identicalCount, 0)
    }

    // A whole labor's worth of entries on both phones must plan quickly.
    func testLargeMergeIsFast() {
        let mine = (0..<5000).map { rec(t(Double($0) * 240), 60) }
        let theirs = (0..<5000).map { rec(t(Double($0) * 240 + 15), 60) }
        let clock = ContinuousClock()
        var plan = ImportPlan(additions: [], matches: [], identicalCount: 0, collapsedIncomingCount: 0)
        let elapsed = clock.measure { plan = Merge.plan(existing: mine, incoming: theirs, now: later) }
        XCTAssertEqual(plan.matches.count, 5000)
        XCTAssertLessThan(elapsed, .seconds(3))
    }
}
