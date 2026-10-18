// Plain-text share format: export and lenient parse. See `LogText` in
// API.swift for the grammar.
//
// Implementation notes:
// - Calendar math is done by hand (days-from-civil) against
//   `TimeZone.secondsFromGMT(for:)`, so nothing depends on the machine's
//   locale, calendar, or time zone, and parsing 10k lines stays fast.
// - The parser is a hand-written scanner over Unicode scalars: no regex, no
//   force unwraps, bounded digit runs (no integer overflow on garbage).
// - Wall-clock times that occur twice (the DST fall-back hour) cannot be read
//   back unambiguously from `h:mm:ss a` alone, so export appends the UTC
//   offset to those lines only (`2026-11-01 1:10:00 AM -06:00 · 58s`), which
//   the documented per-line offset rule parses. Every other line keeps the
//   documented format. For hand-typed repeated times without an offset, the
//   parser takes the earliest reading not before the previous entry.

import Foundation

enum LogTextImpl {

    // MARK: - Export

    static func export(_ records: [ContractionRecord], timeZone: TimeZone) -> String {
        let done = sortedByStart(records.filter { !$0.isInProgress && unixSeconds($0.start) != nil })

        var lines = ["Contraction Traction log"]
        var summary = "\(done.count) contraction\(done.count == 1 ? "" : "s")"
        if let first = done.first, let last = done.last {
            summary += " · " + rangeText(from: first.start, to: last.start, in: timeZone)
        }
        lines.append(summary)
        let offset = timeZone.secondsFromGMT(for: done.first?.start ?? Date())
        lines.append("Time zone: \(timeZone.identifier) (UTC\(offsetText(offset)))")
        lines.append("~ = approximate")

        if !done.isEmpty {
            lines.append("")
            for record in done {
                lines.append(entryLine(record, in: timeZone))
            }
        }
        return lines.joined(separator: "\n")
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0s" }
        let n = Int(min(max(seconds.rounded(), 0), 1_000_000_000))
        if n < 60 { return "\(n)s" }
        return "\(n / 60)m \(pad2(n % 60))s"
    }

    /// Note as exported and as compared during merge: newlines become spaces,
    /// surrounding whitespace trimmed.
    static func normalizedNote(_ note: String) -> String {
        var out = ""
        out.reserveCapacity(note.utf8.count)
        for ch in note {
            out.append(ch.isNewline ? " " : ch)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func entryLine(_ record: ContractionRecord, in tz: TimeZone) -> String {
        let t = civil(record.start, in: tz)
        var line = "\(pad4(t.year))-\(pad2(t.month))-\(pad2(t.day)) "
            + "\(hour12(t.hour)):\(pad2(t.minute)):\(pad2(t.second)) \(t.hour < 12 ? "AM" : "PM")"
        if utcCandidates(local: t.local, in: tz).instants.count > 1 {
            line += " \(offsetText(t.local - t.utc))"
        }
        line += " · \(record.isApproximate ? "~" : "")\(formatDuration(record.duration ?? 0))"
        let note = normalizedNote(record.note)
        if !note.isEmpty { line += " · \(note)" }
        return line
    }

    private static let monthAbbreviations = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "Oct 18, 2:10 PM – 3:42 PM", or with both dates when the days differ.
    private static func rangeText(from: Date, to: Date, in tz: TimeZone) -> String {
        let a = civil(from, in: tz)
        let b = civil(to, in: tz)
        func day(_ t: CivilTime) -> String { "\(monthAbbreviations[t.month - 1]) \(t.day)" }
        func time(_ t: CivilTime) -> String { "\(hour12(t.hour)):\(pad2(t.minute)) \(t.hour < 12 ? "AM" : "PM")" }
        let sameDay = a.year == b.year && a.month == b.month && a.day == b.day
        if sameDay && a.hour == b.hour && a.minute == b.minute {
            return "\(day(a)), \(time(a))"
        }
        return sameDay
            ? "\(day(a)), \(time(a)) – \(time(b))"
            : "\(day(a)), \(time(a)) – \(day(b)), \(time(b))"
    }

    /// "+05:30" / "-05:00" / "+00:00".
    private static func offsetText(_ seconds: Int) -> String {
        let minutes = abs(seconds) / 60
        return "\(seconds < 0 ? "-" : "+")\(pad2(minutes / 60)):\(pad2(minutes % 60))"
    }

    private static func hour12(_ h: Int) -> Int { h % 12 == 0 ? 12 : h % 12 }
    private static func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
    private static func pad4(_ n: Int) -> String {
        let s = "\(n)"
        return n >= 0 && s.count < 4 ? String(repeating: "0", count: 4 - s.count) + s : s
    }

    // MARK: - Civil time

    struct CivilTime {
        var year, month, day, hour, minute, second: Int
        /// Seconds since 1970 of the instant, and of the wall clock read as UTC.
        var utc, local: Int
    }

    /// Whole seconds since 1970, or nil for dates that cannot be represented.
    static func unixSeconds(_ date: Date) -> Int? {
        let t = date.timeIntervalSince1970
        guard t.isFinite, abs(t) < 1e14 else { return nil }
        return Int(t.rounded(.down))
    }

    private static func civil(_ date: Date, in tz: TimeZone) -> CivilTime {
        let utc = unixSeconds(date) ?? 0
        let local = utc + tz.secondsFromGMT(for: date)
        let days = floorDiv(local, 86_400)
        let sod = local - days * 86_400
        let (y, m, d) = civilFromDays(days)
        return CivilTime(year: y, month: m, day: d,
                         hour: sod / 3600, minute: sod % 3600 / 60, second: sod % 60,
                         utc: utc, local: local)
    }

    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        a >= 0 ? a / b : -((-a + b - 1) / b)
    }

    // Howard Hinnant's proleptic Gregorian algorithms.
    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civilFromDays(_ days: Int) -> (Int, Int, Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400
        return (m <= 2 ? y + 1 : y, m, d)
    }

    private static func daysInMonth(_ year: Int, _ month: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Every instant whose wall clock in `tz` reads `local` (seconds since
    /// 1970 as if the wall clock were UTC), ascending: one normally, two in a
    /// fall-back hour, none in a spring-forward gap. Also returns the offsets
    /// probed, earliest first.
    private static func utcCandidates(local: Int, in tz: TimeZone) -> (instants: [Int], offsets: [Int]) {
        var offsets: [Int] = []
        for probe in [local - 86_400, local, local + 86_400] {
            let o = tz.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(probe)))
            if !offsets.contains(o) { offsets.append(o) }
        }
        var instants: [Int] = []
        for o in offsets {
            let utc = local - o
            if tz.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(utc))) == o,
               !instants.contains(utc) {
                instants.append(utc)
            }
        }
        return (instants.sorted(), offsets)
    }

    /// UTC seconds for a wall-clock time. A repeated time takes the earliest
    /// reading ≥ `notBefore` (keeps a sorted log sorted), else the earliest.
    /// A skipped time (spring-forward gap) reads with the offset in effect
    /// before the transition, i.e. it moves forward.
    static func resolve(local: Int, in tz: TimeZone, notBefore: Int?) -> Int {
        let (instants, offsets) = utcCandidates(local: local, in: tz)
        guard let earliest = instants.first else { return local - offsets[0] }
        guard instants.count > 1, let notBefore else { return earliest }
        return instants.first(where: { $0 >= notBefore }) ?? earliest
    }

    // MARK: - Parse

    static func parse(_ text: String, defaultTimeZone: TimeZone, now: Date) -> ParseResult {
        var accepted: [ContractionRecord] = []
        var rejected: [String] = []
        var zone = defaultTimeZone
        var previousStart: Int?
        let latestStart = now.timeIntervalSince1970 + Limits.futureTolerance

        for line in text.split(whereSeparator: { $0.isNewline }) {
            let s = Array(line.unicodeScalars)
            var scanner = Scanner(s)
            scanner.skipLeadingJunk()

            guard scanner.looksDated() else {
                if let header = scanner.timeZoneHeader() {
                    zone = header.zone ?? defaultTimeZone
                    previousStart = nil
                }
                continue
            }

            guard let entry = scanner.entry() else {
                rejected.append(String(line).trimmingCharacters(in: .whitespacesAndNewlines))
                continue
            }
            let local = daysFromCivil(entry.year, entry.month, entry.day) * 86_400
                + entry.hour * 3600 + entry.minute * 60 + entry.second
            let utc = entry.offset.map { local - $0 }
                ?? resolve(local: local, in: zone, notBefore: previousStart)
            let duration = TimeInterval(entry.duration)
            guard TimeInterval(utc) <= latestStart,
                  duration >= Limits.minDuration, duration <= Limits.maxDuration else {
                rejected.append(String(line).trimmingCharacters(in: .whitespacesAndNewlines))
                continue
            }
            previousStart = utc
            accepted.append(ContractionRecord(start: Date(timeIntervalSince1970: TimeInterval(utc)),
                                              duration: duration,
                                              isApproximate: entry.approximate,
                                              note: entry.note))
        }
        return ParseResult(records: sortedByStart(accepted), rejectedLines: rejected)
    }

    /// Sorted by start; equal starts keep their input order.
    static func sortedByStart(_ records: [ContractionRecord]) -> [ContractionRecord] {
        records.enumerated()
            .sorted { a, b in
                a.element.start != b.element.start ? a.element.start < b.element.start : a.offset < b.offset
            }
            .map(\.element)
    }

    // MARK: - Scanner

    struct Entry {
        var year, month, day, hour, minute, second: Int
        var offset: Int?
        var duration: Int
        var approximate: Bool
        var note: String
    }

    struct Header {
        /// nil when neither the identifier nor the offset could be read.
        var zone: TimeZone?
    }

    private struct Scanner {
        let s: [Unicode.Scalar]
        var i = 0

        init(_ s: [Unicode.Scalar]) { self.s = s }

        // MARK: Character classes

        private func v(_ k: Int) -> UInt32 { k < s.count ? s[k].value : 0 }
        private var atEnd: Bool { i >= s.count }

        private static func isDigit(_ c: UInt32) -> Bool { c >= 0x30 && c <= 0x39 }
        private static func isLetter(_ c: UInt32) -> Bool {
            (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
        }
        private static func lower(_ c: UInt32) -> UInt32 { c >= 0x41 && c <= 0x5A ? c + 32 : c }
        /// Horizontal whitespace except tab (tab is a field separator).
        private static func isSpace(_ c: UInt32) -> Bool {
            c == 0x20 || c == 0xA0 || c == 0x202F || (c >= 0x2000 && c <= 0x200A)
                || c == 0x205F || c == 0x3000 || c == 0x1680
        }
        /// Zero-width and bidi marks that copy/paste can carry along.
        private static func isInvisible(_ c: UInt32) -> Bool {
            c == 0xFEFF || (c >= 0x200B && c <= 0x200F) || c == 0x2060
                || (c >= 0x202A && c <= 0x202E) || (c >= 0x2066 && c <= 0x2069)
        }
        /// `·` `•` `|` tab, plus look-alikes (`∙` `⋅` `・` `｜`).
        private static func isSeparator(_ c: UInt32) -> Bool {
            c == 0xB7 || c == 0x2022 || c == 0x7C || c == 0x09
                || c == 0x2219 || c == 0x22C5 || c == 0x30FB || c == 0xFF5C
        }
        /// `-` and the dashes smart punctuation substitutes.
        private static func isDash(_ c: UInt32) -> Bool {
            c == 0x2D || (c >= 0x2010 && c <= 0x2015) || c == 0x2212
        }
        private static func isColon(_ c: UInt32) -> Bool { c == 0x3A || c == 0xFF1A || c == 0x2236 }
        private static func isTilde(_ c: UInt32) -> Bool {
            c == 0x7E || c == 0x223C || c == 0x2248 || c == 0xFF5E || c == 0x2053
        }

        /// Skips spaces and invisible marks; returns how many real spaces.
        @discardableResult
        private mutating func skipSpaces() -> Int {
            var spaces = 0
            while !atEnd {
                let c = v(i)
                if Self.isSpace(c) { spaces += 1 } else if !Self.isInvisible(c) { break }
                i += 1
            }
            return spaces
        }

        mutating func skipLeadingJunk() {
            while !atEnd, Self.isSpace(v(i)) || Self.isInvisible(v(i)) || v(i) == 0x09 { i += 1 }
        }

        /// A digit run of `min...max` digits (the whole run must fit).
        private mutating func digits(_ minCount: Int, _ maxCount: Int) -> Int? {
            var k = i
            var value = 0
            while k < s.count, Self.isDigit(v(k)) {
                if k - i >= maxCount { return nil }
                value = value * 10 + Int(v(k) - 0x30)
                k += 1
            }
            guard k - i >= minCount else { return nil }
            i = k
            return value
        }

        private mutating func letters() -> String {
            var out = ""
            while !atEnd, Self.isLetter(v(i)) {
                out.unicodeScalars.append(Unicode.Scalar(Self.lower(v(i))) ?? " ")
                i += 1
            }
            return out
        }

        private func restString(from k: Int) -> String {
            var view = String.UnicodeScalarView()
            if k < s.count { view.append(contentsOf: s[k...]) }
            return String(view).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // MARK: Lines

        /// `yyyy-M`: the line is meant as an entry, so failures are reported.
        func looksDated() -> Bool {
            var k = i
            while k < i + 4 { if !Self.isDigit(v(k)) { return false }; k += 1 }
            return Self.isDash(v(k)) && Self.isDigit(v(k + 1))
        }

        /// `Time zone: <identifier> (UTC±HH:MM)`; either part may be missing.
        mutating func timeZoneHeader() -> Header? {
            for c in "time".unicodeScalars {
                guard Self.lower(v(i)) == c.value else { return nil }
                i += 1
            }
            skipSpaces()
            if Self.isDash(v(i)) { i += 1 }
            for c in "zone".unicodeScalars {
                guard Self.lower(v(i)) == c.value else { return nil }
                i += 1
            }
            skipSpaces()
            guard Self.isColon(v(i)) else { return nil }
            i += 1
            skipSpaces()
            let idStart = i
            while !atEnd, !Self.isSpace(v(i)), v(i) != 0x28 /* ( */ { i += 1 }
            var idView = String.UnicodeScalarView()
            idView.append(contentsOf: s[idStart..<i].filter { !Self.isInvisible($0.value) })
            let identifier = String(idView)

            // Prefer the offset after the identifier ("Etc/GMT+5" is UTC-5).
            let offset = utcOffset(from: i) ?? utcOffset(from: idStart)
            var zone = identifier.isEmpty ? nil : TimeZone(identifier: identifier)
            if zone == nil, let offset { zone = TimeZone(secondsFromGMT: offset) }
            return Header(zone: zone)
        }

        /// First `UTC±H[H][:MM]` / `GMT±…` (or bare `UTC`) at or after `k`.
        private func utcOffset(from start: Int) -> Int? {
            var k = start
            while k + 2 < s.count {
                let a = Self.lower(v(k)), b = Self.lower(v(k + 1)), c = Self.lower(v(k + 2))
                let isUTC = a == 0x75 && b == 0x74 && c == 0x63
                let isGMT = a == 0x67 && b == 0x6D && c == 0x74
                if isUTC || isGMT {
                    var probe = Scanner(s)
                    probe.i = k + 3
                    probe.skipSpaces()
                    let sign = probe.v(probe.i)
                    if sign == 0x2B || Self.isDash(sign) {
                        probe.i += 1
                        guard let magnitude = probe.offsetMagnitude(allowHoursOnly: true) else { return nil }
                        return sign == 0x2B ? magnitude : -magnitude
                    }
                    if !Self.isLetter(sign) && !Self.isDigit(sign) { return 0 }
                }
                k += 1
            }
            return nil
        }

        /// The rest of a dated line; nil means reject.
        mutating func entry() -> Entry? {
            // Date: yyyy-M[M]-d[d]
            guard let year = digits(4, 4), Self.isDash(v(i)) else { return nil }
            i += 1
            guard let month = digits(1, 2), Self.isDash(v(i)) else { return nil }
            i += 1
            guard let day = digits(1, 2) else { return nil }
            guard (1...12).contains(month), day >= 1,
                  day <= LogTextImpl.daysInMonth(year, month) else { return nil }

            // Date/time separator: `T` or whitespace (incl. tab).
            if v(i) == 0x54 || v(i) == 0x74 {
                i += 1
            } else {
                let before = i
                while !atEnd, Self.isSpace(v(i)) || Self.isInvisible(v(i)) || v(i) == 0x09 { i += 1 }
                guard i > before else { return nil }
            }

            // Time: H[H]:mm[:ss[.fff]] [AM|PM]
            guard var hour = digits(1, 2), Self.isColon(v(i)) else { return nil }
            i += 1
            guard let minute = digits(2, 2) else { return nil }
            var second = 0
            if Self.isColon(v(i)) {
                i += 1
                guard let ss = digits(2, 2) else { return nil }
                second = ss
                if v(i) == 0x2E, Self.isDigit(v(i + 1)) {   // fractional seconds, truncated
                    i += 1
                    while Self.isDigit(v(i)) { i += 1 }
                }
            }
            guard minute < 60, second < 60 else { return nil }
            if let pm = meridiem() {
                guard (1...12).contains(hour) else { return nil }
                hour = hour % 12 + (pm ? 12 : 0)
            } else {
                guard hour < 24 else { return nil }
            }

            let offset = lineOffset()

            // Time/duration separator.
            guard let explicitSeparator = fieldSeparator(allowBareSpace: true) else { return nil }

            // A unitless number after bare whitespace is too likely to be chat
            // text ("2:10 PM 10 - 12 min apart"); require `s`/`m`/`:` there.
            guard let parsedDuration = durationField(allowBareSeconds: explicitSeparator) else { return nil }
            let (duration, approximate) = parsedDuration

            // Duration/note separator, or end of line.
            let spaces = skipSpaces()
            var note = ""
            if !atEnd {
                if Self.isSeparator(v(i)) {
                    note = restString(from: i + 1)
                } else if Self.isDash(v(i)), spaces > 0, i + 1 >= s.count || Self.isSpace(v(i + 1)) {
                    note = restString(from: i + 1)
                } else {
                    return nil
                }
            }
            return Entry(year: year, month: month, day: day, hour: hour, minute: minute,
                         second: second, offset: offset, duration: duration,
                         approximate: approximate, note: note)
        }

        /// AM/PM, a.m./p.m., any case, optionally after whitespace.
        private mutating func meridiem() -> Bool? {
            let saved = i
            skipSpaces()
            let c = Self.lower(v(i))
            guard c == 0x61 || c == 0x70 else { i = saved; return nil }
            var k = i + 1
            if v(k) == 0x2E { k += 1 }
            guard Self.lower(v(k)) == 0x6D else { i = saved; return nil }
            k += 1
            if v(k) == 0x2E { k += 1 }
            guard !Self.isLetter(v(k)), !Self.isDigit(v(k)) else { i = saved; return nil }
            i = k
            return c == 0x70
        }

        /// `Z`, `±HH:MM`, or `±HHMM` right after the time (spaces allowed).
        private mutating func lineOffset() -> Int? {
            let saved = i
            skipSpaces()
            let c = v(i)
            if c == 0x5A || c == 0x7A, !Self.isLetter(v(i + 1)), !Self.isDigit(v(i + 1)) {
                i += 1
                return 0
            }
            if c == 0x2B || Self.isDash(c), Self.isDigit(v(i + 1)) {
                i += 1
                if let magnitude = offsetMagnitude(allowHoursOnly: false) {
                    return c == 0x2B ? magnitude : -magnitude
                }
            }
            i = saved
            return nil
        }

        /// Offset after its sign: `HH:MM` or `HHMM`; also `H`/`HH` alone when
        /// `allowHoursOnly`. Seconds, or nil (position restored).
        private mutating func offsetMagnitude(allowHoursOnly: Bool) -> Int? {
            let start = i
            var run = 0
            while Self.isDigit(v(i + run)) { run += 1 }
            func digit(_ k: Int) -> Int { Int(v(k) - 0x30) }
            var hours = 0
            var minutes = 0
            if run == 4 {
                hours = digit(i) * 10 + digit(i + 1)
                minutes = digit(i + 2) * 10 + digit(i + 3)
                i += 4
            } else if run == 2 || (run == 1 && allowHoursOnly) {
                hours = run == 2 ? digit(i) * 10 + digit(i + 1) : digit(i)
                i += run
                if Self.isColon(v(i)) {
                    i += 1
                    guard let mm = digits(2, 2) else { i = start; return nil }
                    minutes = mm
                } else if !allowHoursOnly {
                    i = start
                    return nil
                }
            } else {
                return nil
            }
            guard hours <= 18, minutes < 60 else { i = start; return nil }
            return hours * 3600 + minutes * 60
        }

        /// A field separator with optional whitespace around it; a spaced dash
        /// also counts. Plain whitespace counts when `allowBareSpace`. Returns
        /// true for an explicit separator, false for bare whitespace, nil if
        /// there is none.
        private mutating func fieldSeparator(allowBareSpace: Bool) -> Bool? {
            let spaces = skipSpaces()
            var explicit = true
            if Self.isSeparator(v(i)) {
                i += 1
            } else if Self.isDash(v(i)), spaces > 0, Self.isSpace(v(i + 1)) {
                i += 1
            } else if allowBareSpace && spaces > 0 {
                explicit = false
            } else {
                return nil
            }
            while !atEnd, Self.isSpace(v(i)) || Self.isInvisible(v(i)) || v(i) == 0x09 { i += 1 }
            return explicit
        }

        /// `58s`, `1m`, `1m 05s`, `1m5s`, `1 min 5 sec`, `1:05`, `90` (only
        /// when `allowBareSeconds`); `~` prefix.
        private mutating func durationField(allowBareSeconds: Bool) -> (Int, Bool)? {
            var approximate = false
            if Self.isTilde(v(i)) {
                approximate = true
                i += 1
                skipSpaces()
            }
            guard let a = digits(1, 6) else { return nil }
            let afterNumber = i
            skipSpaces()

            if Self.isColon(v(i)) {
                i += 1
                guard let b = digits(2, 2), b < 60 else { return nil }
                return (a * 60 + b, approximate)
            }
            let unit = letters()
            if unit.isEmpty {
                guard allowBareSeconds else { return nil }
                i = afterNumber
                return (a, approximate)
            }
            if Self.secondUnits.contains(unit) { return (a, approximate) }
            guard Self.minuteUnits.contains(unit) else { return nil }

            let afterMinutes = i
            skipSpaces()
            guard let b = digits(1, 2) else {
                i = afterMinutes
                return (a * 60, approximate)
            }
            let afterSeconds = i
            skipSpaces()
            let secondUnit = letters()
            if secondUnit.isEmpty {
                i = afterSeconds
            } else if !Self.secondUnits.contains(secondUnit) {
                return nil
            }
            guard b < 60 else { return nil }
            return (a * 60 + b, approximate)
        }

        private static let secondUnits: Set<String> = ["s", "sec", "secs", "second", "seconds"]
        private static let minuteUnits: Set<String> = ["m", "min", "mins", "minute", "minutes"]
    }
}
