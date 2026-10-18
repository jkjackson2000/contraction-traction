import XCTest
@testable import ContractionCore

final class LogTextExportTests: XCTestCase {

    // The share text is what a partner reads in iMessage; its exact shape is
    // the contract between app versions on two phones.
    func testExportGoldenFormat() {
        let records = [
            rec(at(2026, 10, 18, 14, 15, 40), 65, approx: true, note: "back pain"),
            rec(at(2026, 10, 18, 14, 10, 3), 58),
            rec(at(2026, 10, 18, 14, 20, 0), nil), // in progress: never shared
        ]
        let expected = """
        Contraction Traction log
        2 contractions · Oct 18, 2:10 PM – 2:15 PM
        Time zone: America/Chicago (UTC-05:00)
        ~ = approximate

        2026-10-18 2:10:03 PM · 58s
        2026-10-18 2:15:40 PM · ~1m 05s · back pain
        """
        XCTAssertEqual(LogText.export(records, timeZone: TZ.chicago), expected)
    }

    // The header must read naturally for one entry, a log crossing midnight,
    // and an empty log, and show half-hour offsets correctly.
    func testExportHeaderVariants() {
        let one = LogText.export([rec(at(2026, 10, 18, 9, 5, 0, TZ.kolkata), 45)], timeZone: TZ.kolkata)
        XCTAssertEqual(one.components(separatedBy: "\n")[1], "1 contraction · Oct 18, 9:05 AM")
        XCTAssertEqual(one.components(separatedBy: "\n")[2], "Time zone: Asia/Kolkata (UTC+05:30)")

        let overnight = LogText.export([rec(at(2026, 10, 18, 23, 50), 60), rec(at(2026, 10, 19, 0, 20), 60)],
                                       timeZone: TZ.chicago)
        XCTAssertEqual(overnight.components(separatedBy: "\n")[1],
                       "2 contractions · Oct 18, 11:50 PM – Oct 19, 12:20 AM")
        XCTAssertTrue(overnight.hasSuffix("2026-10-19 12:20:00 AM · 1m 00s"))

        let empty = LogText.export([rec(at(2026, 10, 18, 9, 0), nil)], timeZone: TZ.tokyo)
        XCTAssertEqual(empty, """
        Contraction Traction log
        0 contractions
        Time zone: Asia/Tokyo (UTC+09:00)
        ~ = approximate
        """)
    }

    // iOS formats "2:10 PM" with U+202F; the share text must use a plain space
    // so any app (and older parsers) can read it.
    func testExportUsesPlainSpacesOnly() {
        let text = LogText.export([rec(at(2026, 10, 18, 14, 10, 3), 58, note: "a\u{00A0}b")], timeZone: TZ.chicago)
        let entry = text.components(separatedBy: "\n").last!
        XCTAssertTrue(entry.hasPrefix("2026-10-18 2:10:03 PM · 58s · "))
        XCTAssertFalse(text.unicodeScalars.contains { $0.value == 0x202F })
    }

    // Notes are single-line in the share text; a newline would split an entry.
    func testExportFlattensNoteNewlines() {
        let text = LogText.export([rec(at(2026, 10, 18, 14, 10), 58, note: " one\ntwo\r\nthree\u{2028}four ")],
                                  timeZone: TZ.chicago)
        XCTAssertTrue(text.hasSuffix("· 58s · one two three four"))
    }

    // Duration text is shown in the UI too; it must be stable and never crash.
    func testFormatDuration() {
        XCTAssertEqual(LogText.formatDuration(0), "0s")
        XCTAssertEqual(LogText.formatDuration(58), "58s")
        XCTAssertEqual(LogText.formatDuration(59.6), "1m 00s")
        XCTAssertEqual(LogText.formatDuration(60), "1m 00s")
        XCTAssertEqual(LogText.formatDuration(65), "1m 05s")
        XCTAssertEqual(LogText.formatDuration(600), "10m 00s")
        XCTAssertEqual(LogText.formatDuration(-3), "0s")
        XCTAssertEqual(LogText.formatDuration(.nan), "0s")
        XCTAssertEqual(LogText.formatDuration(.infinity), "0s")
    }
}

final class LogTextRoundTripTests: XCTestCase {

    private func assertRoundTrip(_ records: [ContractionRecord], _ tz: TimeZone,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let text = LogText.export(records, timeZone: tz)
        let now = (records.map(\.start).max() ?? Date(timeIntervalSince1970: 0)).addingTimeInterval(3600)
        // A different default zone proves the header, not the default, is used.
        let result = LogText.parse(text, defaultTimeZone: TZ.tokyo == tz ? TZ.chicago : TZ.tokyo, now: now)
        let expected = LogTextImpl.sortedByStart(records.filter { !$0.isInProgress }).map { r -> Fields in
            var f = Fields(r)
            f.note = LogTextImpl.normalizedNote(r.note)
            return f
        }
        XCTAssertEqual(result.rejectedLines, [], file: file, line: line)
        XCTAssertEqual(result.records.map(Fields.init), expected, file: file, line: line)
        XCTAssertTrue(Set(result.records.map(\.id)).isDisjoint(with: records.map(\.id)), file: file, line: line)
    }

    // Partners exchange logs both ways; anything lost or shifted in transit
    // would corrupt the receiver's timeline.
    func testRoundTripWithApproximateAndTrickyNotes() {
        let base = at(2026, 10, 18, 14, 0)
        let notes = [
            "", "back pain", "a · b · c", "x | y | z", "~1m 05s", "· starts with separator",
            "ends with separator ·", "2026-10-18 2:10 PM · 58s", "line one\nline two", "crlf\r\nnote",
            "  padded  ", "tab\tinside", "nbsp\u{00A0}inside", "emoji 😣💧", "•", "– dash – note –",
        ]
        let durations: [TimeInterval] = [1, 59, 60, 61, 90, 599, 600]
        let records = notes.enumerated().map { k, note in
            rec(base.addingTimeInterval(Double(k) * 271), durations[k % durations.count],
                approx: k % 3 == 0, note: note)
        }
        assertRoundTrip(records, TZ.chicago)
    }

    // Labor does not stop for DST: entries in the repeated 1 AM hour must come
    // back at the right instant, in order.
    func testRoundTripAcrossFallBackHour() {
        // 2026-11-01 06:00Z = 1:00 AM CDT; 07:00Z = 1:00 AM CST.
        let start = Date(timeIntervalSince1970: 1_793_512_800 - 1800) // 00:30 CDT
        let records = (0..<16).map { rec(start.addingTimeInterval(Double($0) * 600 + 7), 55) }
        assertRoundTrip(records, TZ.chicago)
        // Starting inside the second 1 AM hour, with nothing before it.
        let lateStart = Date(timeIntervalSince1970: 1_793_516_400 + 600) // 1:10 AM CST
        assertRoundTrip([rec(lateStart, 50), rec(lateStart.addingTimeInterval(400), 50)], TZ.chicago)
        let text = LogText.export([rec(lateStart, 50)], timeZone: TZ.chicago)
        XCTAssertTrue(text.hasSuffix("2026-11-01 1:10:00 AM -06:00 · 50s"))
    }

    // Randomized check over zones with DST, half-hour offsets, and Lord Howe's
    // 30-minute DST shift.
    func testRoundTripFuzz() {
        var rng = SplitMix64(seed: 42)
        let zones = [TZ.chicago, TZ.kolkata, TZ.lordHowe, TZ.london, TZ.tokyo, TZ.utc]
        let notePool = ["", "ok", "a · b", "| pipe", "~approx", "multi\nline", "  spaced  ", "ünïcödé"]
        for zone in zones {
            var records: [ContractionRecord] = []
            for _ in 0..<300 {
                let start = Date(timeIntervalSince1970: Double(Int.random(in: 1_767_225_600...1_798_761_600, using: &rng)))
                records.append(rec(start, Double(Int.random(in: 1...600, using: &rng)),
                                   approx: Bool.random(using: &rng),
                                   note: notePool.randomElement(using: &rng)!))
            }
            assertRoundTrip(records, zone)
        }
    }
}

final class LogTextParseTests: XCTestCase {
    private let now = at(2026, 10, 18, 23, 0)

    private func one(_ line: String, tz: TimeZone = TZ.chicago,
                     file: StaticString = #filePath, lineNo: UInt = #line) -> ContractionRecord? {
        let result = LogText.parse(line, defaultTimeZone: tz, now: now)
        XCTAssertEqual(result.rejectedLines, [], "rejected: \(line)", file: file, line: lineNo)
        XCTAssertEqual(result.records.count, 1, "parsed: \(line)", file: file, line: lineNo)
        return result.records.first
    }

    // Hand-typed and lightly edited logs must still import; each case is a
    // shape a person or iOS text system plausibly produces.
    func testLenientLineShapes() {
        let t1410 = at(2026, 10, 18, 14, 10)
        let cases: [(String, Date, TimeInterval, Bool, String)] = [
            ("2026-10-18 14:10 | ~1m", t1410, 60, true, ""),                         // spec example, 24h
            ("2026-10-18 2:10 PM · 58s", t1410, 58, false, ""),                      // no seconds
            ("2026-10-18T14:10:03 · 58s", t1410 + 3, 58, false, ""),                 // T separator
            ("2026-10-18 2:10\u{202F}PM · 1:05", t1410, 65, false, ""),              // iOS U+202F
            ("2026-10-18\u{00A0}2:10\u{00A0}pm · 90", t1410, 90, false, ""),         // NBSP, lowercase, bare
            ("2026-10-18 2:10 p.m. • 1m5s", t1410, 65, false, ""),                   // bullet, compact
            ("2026-10-18\t2:10 PM\t~1m 05s\tnote here", t1410, 65, true, "note here"), // tabs
            ("  2026-10-18 2:10 PM – 45s – felt strong  ", t1410, 45, false, "felt strong"), // smart dashes
            ("2026–10–18 2:10 PM · 45s", t1410, 45, false, ""),                      // en dashes in date
            ("2026-10-18 2:10 PM 58s", t1410, 58, false, ""),                        // space only
            ("2026-10-18 2:10 PM · 2 min 5 sec · x", t1410, 125, false, "x"),        // spelled units
            ("2026-10-18 2:10 PM · ~ 1m · x", t1410, 60, true, "x"),                 // spaced tilde
            ("2026-10-18 2:10 PM·58s·x", t1410, 58, false, "x"),                     // no spaces
            ("2026-10-18 2:10 PM · 58s ·", t1410, 58, false, ""),                    // trailing separator
            ("\u{FEFF}\u{200E}2026-10-18 2:10 PM · 58s", t1410, 58, false, ""),      // BOM / LRM
            ("2026-10-18 12:05 AM · 30s", at(2026, 10, 18, 0, 5), 30, false, ""),
            ("2026-10-18 12:05 PM · 30s", at(2026, 10, 18, 12, 5), 30, false, ""),
            ("2026-10-18 0:05 · 30s", at(2026, 10, 18, 0, 5), 30, false, ""),
        ]
        for (line, start, duration, approx, note) in cases {
            guard let r = one(line) else { continue }
            XCTAssertEqual(r.start, start, line)
            XCTAssertEqual(r.duration, duration, line)
            XCTAssertEqual(r.isApproximate, approx, line)
            XCTAssertEqual(r.note, note, line)
        }
    }

    // A partner abroad, or an ISO timestamp, must land at the right instant
    // regardless of headers or the receiver's zone.
    func testPerLineOffsetsOverrideZones() {
        let instant = Date(timeIntervalSince1970: 1_792_350_603) // 2026-10-18 19:10:03Z
        let header = "Time zone: Asia/Tokyo (UTC+09:00)\n"
        for line in ["2026-10-18T19:10:03Z · 58s",
                     "2026-10-18 19:10:03 z · 58s",
                     "2026-10-18T19:10:03.750Z · 58s",
                     "2026-10-18 14:10:03-05:00 · 58s",
                     "2026-10-18 2:10:03 PM -0500 · 58s",
                     "2026-10-18 2:10:03 PM −05:00 · 58s",
                     "2026-10-19 4:10:03 AM +09:00 · 58s"] {
            let result = LogText.parse(header + line, defaultTimeZone: TZ.chicago, now: now)
            XCTAssertEqual(result.records.first?.start, instant, line)
            XCTAssertEqual(result.rejectedLines, [], line)
        }
    }

    // The sender's zone travels in the header so the receiver's phone setting
    // cannot shift every entry by hours.
    func testHeaderZoneAppliedElseDefault() {
        let lines = "2026-10-18 2:10 PM · 58s"
        let withHeader = LogText.parse("Time zone: America/Chicago (UTC-05:00)\n" + lines,
                                       defaultTimeZone: TZ.tokyo, now: now)
        XCTAssertEqual(withHeader.records.first?.start, at(2026, 10, 18, 14, 10))
        let without = LogText.parse(lines, defaultTimeZone: TZ.tokyo, now: now)
        XCTAssertEqual(without.records.first?.start, at(2026, 10, 18, 14, 10, 0, TZ.tokyo))
        // Unknown identifier: fall back to the offset in parentheses.
        let offsetOnly = LogText.parse("Time zone: Mars/Olympus (UTC+05:30)\n" + lines,
                                       defaultTimeZone: TZ.tokyo, now: now)
        XCTAssertEqual(offsetOnly.records.first?.start, at(2026, 10, 18, 14, 10, 0, TZ.kolkata))
        // Invisible marks pasted from right-to-left chats must not break the
        // identifier (a fixed-offset fallback would be wrong after DST ends).
        let marked = LogText.parse("Time zone: America/Chicago\u{200E} (UTC-05:00)\n2026-11-02 9:00 AM · 50s",
                                   defaultTimeZone: TZ.tokyo, now: now.addingTimeInterval(30 * 86_400))
        XCTAssertEqual(marked.records.first?.start, at(2026, 11, 2, 9, 0))
        // "Etc/GMT+5" is UTC-5 by POSIX convention: the identifier wins.
        let etc = LogText.parse("Time zone: Etc/GMT+5 (UTC-05:00)\n" + lines, defaultTimeZone: TZ.tokyo, now: now)
        XCTAssertEqual(etc.records.first?.start, at(2026, 10, 18, 14, 10, 0, TimeZone(secondsFromGMT: -18_000)!))
    }

    // Two logs from different zones pasted together: each header governs the
    // lines below it.
    func testHeadersApplyToFollowingLines() {
        let text = """
        Time zone: Asia/Tokyo (UTC+09:00)
        2026-10-18 9:00 AM · 50s
        Time zone: America/Chicago (UTC-05:00)
        2026-10-18 9:00 AM · 50s
        """
        let result = LogText.parse(text, defaultTimeZone: TZ.utc, now: now)
        XCTAssertEqual(result.records.map(\.start),
                       [at(2026, 10, 18, 9, 0, 0, TZ.tokyo), at(2026, 10, 18, 9, 0, 0, TZ.chicago)])
    }

    // Users paste a whole iMessage thread; only the log lines may count, and
    // line-ending style must not matter.
    func testChatThreadAroundBlockWithMixedLineEndings() {
        let block = [
            "Jared: here you go",
            "Contraction Traction log",
            "3 contractions · Oct 18, 2:10 PM – 2:21 PM",
            "Time zone: America/Chicago (UTC-05:00)",
            "~ = approximate",
            "",
            "2026-10-18 2:10:03 PM · 58s",
            "2026-10-18 2:15:40 PM · ~1m 05s · back pain",
            "   2026-10-18 2:21:00 PM · 1m 10s   ",
            "Sent from my iPhone",
            "Read 3:45 PM",
            "thanks!! 2026 is the year",
        ]
        for newline in ["\n", "\r\n", "\r"] {
            let result = LogText.parse(block.joined(separator: newline), defaultTimeZone: TZ.tokyo, now: now)
            XCTAssertEqual(result.rejectedLines, [])
            XCTAssertEqual(result.records.map(\.start),
                           [at(2026, 10, 18, 14, 10, 3), at(2026, 10, 18, 14, 15, 40), at(2026, 10, 18, 14, 21)])
            XCTAssertEqual(result.records.map(\.note), ["", "back pain", ""])
        }
    }

    // Bad entries are surfaced (not silently dropped, not imported) so the
    // user can fix them.
    func testRejectedLines() {
        let bad = [
            "2026-10-18 25:10 · 58s",
            "2026-10-18 2:61 PM · 58s",
            "2026-10-18 13:10 PM · 58s",
            "2026-10-18 0:10 AM · 58s",
            "2026-02-30 2:10 PM · 58s",
            "2026-13-01 2:10 PM · 58s",
            "2026-10-18 2:10 PM · 0s",
            "2026-10-18 2:10 PM · 601s",
            "2026-10-18 2:10 PM · 10m 01s",
            "2026-10-18 2:10 PM · 1:60",
            "2026-10-18 2:10 PM",
            "2026-10-18 2:10 PM · soon",
            "2026-10-18 2:10 PM · 1m back pain",
            "2026-10-18 2:10 PM · 1.5m",
            "2026-10-18 2:10 PM 10 - 12 min apart", // chat text: unitless number after bare space
            "2026-10-18",
            "2026-10-18 99999999999999999999:00 · 9999999999999999999999s",
        ]
        let text = bad.map { "  \($0)  " }.joined(separator: "\n")
        let result = LogText.parse(text, defaultTimeZone: TZ.chicago, now: now)
        XCTAssertEqual(result.records, [])
        XCTAssertEqual(result.rejectedLines, bad) // verbatim, trimmed, in order
    }

    // Limits are inclusive at 1 s and 10 min; 5 min in the future is allowed
    // (clock skew between phones), 5 min 1 s is not.
    func testLimitsBoundaries() {
        let now = at(2026, 10, 18, 14, 0)
        let text = """
        2026-10-18 1:00 PM · 1s
        2026-10-18 1:10 PM · 10m
        2026-10-18 2:05:00 PM · 30s
        2026-10-18 2:05:01 PM · 30s
        """
        let result = LogText.parse(text, defaultTimeZone: TZ.chicago, now: now)
        XCTAssertEqual(result.records.map(\.duration), [1, 600, 30])
        XCTAssertEqual(result.rejectedLines, ["2026-10-18 2:05:01 PM · 30s"])
    }

    // Records come back sorted even if the text was hand-edited out of order.
    func testRecordsSortedByStart() {
        let text = "2026-10-18 3:00 PM · 50s\n2026-10-18 1:00 PM · 40s\n2026-10-18 2:00 PM · 45s"
        let result = LogText.parse(text, defaultTimeZone: TZ.chicago, now: now)
        XCTAssertEqual(result.records.map(\.duration), [40, 45, 50])
    }

    // Pasting garbage must never crash the app or invent entries.
    func testGarbageNeverCrashes() {
        let samples = ["", "\n\n\r\n", "~", "·|•\t", "2026-", "2026-1", "0000-00-00 00:00 · 0",
                       "9999-99-99 99:99:99 · 99999999999999999999s", "😣😣😣", String(repeating: "9", count: 10_000),
                       "2026-10-18 2:10 PM · ~", "2026-10-18 2:10 PM · 1m ~", "Time zone:", "Time zone: (UTC+99:99)",
                       "Time zone: \u{202F}", "2026-10-18T", "2026-10-18 :", "2026-10-18 1:", "2026-10-18 1:0"]
        for sample in samples {
            let result = LogText.parse(sample, defaultTimeZone: TZ.chicago, now: now)
            XCTAssertEqual(result.records, [], sample)
        }

        var rng = SplitMix64(seed: 7)
        let alphabet = Array("0123456789-:·•|\t ~TZz+−–apmAPMs\u{202F}\u{00A0}\n\r漢😣Time zone()UTC")
        var lines: [String] = []
        for _ in 0..<3000 {
            var line = Bool.random(using: &rng) ? "2026-10-18 " : ""
            for _ in 0..<Int.random(in: 0...30, using: &rng) {
                line.append(alphabet.randomElement(using: &rng)!)
            }
            lines.append(line)
        }
        let result = LogText.parse(lines.joined(separator: "\n"), defaultTimeZone: TZ.chicago, now: now)
        for r in result.records {
            XCTAssertTrue((Limits.minDuration...Limits.maxDuration).contains(r.duration ?? 0))
            XCTAssertLessThanOrEqual(r.start, now.addingTimeInterval(Limits.futureTolerance))
        }
    }

    // A long labor log (or a huge paste) must parse without a visible stall.
    func testTenThousandLinesIsFast() {
        let base = at(2026, 10, 17, 0, 0)
        let records = (0..<10_000).map { rec(base.addingTimeInterval(Double($0) * 7), 50, note: "n\($0)") }
        let text = LogText.export(records, timeZone: TZ.chicago) + "\nchat line\n" + String(repeating: "noise\n", count: 2000)
        let clock = ContinuousClock()
        var result = ParseResult(records: [], rejectedLines: [])
        let elapsed = clock.measure {
            result = LogText.parse(text, defaultTimeZone: TZ.tokyo, now: base.addingTimeInterval(86_400))
        }
        XCTAssertEqual(result.records.count, 10_000)
        XCTAssertLessThan(elapsed, .seconds(3), "debug-build parse of 12k lines took \(elapsed)")
    }
}
