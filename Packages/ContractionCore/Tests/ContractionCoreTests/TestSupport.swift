import Foundation
@testable import ContractionCore

// Explicit zones everywhere: tests must never depend on the machine's
// locale or time zone.
enum TZ {
    static let chicago = TimeZone(identifier: "America/Chicago")!
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    static let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    static let london = TimeZone(identifier: "Europe/London")!
    static let lordHowe = TimeZone(identifier: "Australia/Lord_Howe")!
    static let utc = TimeZone(secondsFromGMT: 0)!
}

/// Wall-clock time in `tz`, built with Foundation's Calendar (independent of
/// the hand-written calendar math under test).
func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0,
        _ tz: TimeZone = TZ.chicago) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = tz
    return calendar.date(from: DateComponents(year: year, month: month, day: day,
                                              hour: hour, minute: minute, second: second))!
}

func rec(_ start: Date, _ duration: TimeInterval?, approx: Bool = false, note: String = "") -> ContractionRecord {
    ContractionRecord(start: start, duration: duration, isApproximate: approx, note: note)
}

/// The fields that must survive a round trip (ids are fresh on parse).
struct Fields: Equatable, CustomStringConvertible {
    var start: Date
    var duration: TimeInterval?
    var approx: Bool
    var note: String

    init(_ r: ContractionRecord) {
        start = r.start
        duration = r.duration
        approx = r.isApproximate
        note = r.note
    }

    var description: String { "\(start) \(duration.map { "\($0)" } ?? "nil") \(approx ? "~" : "") \(note)" }
}

/// Deterministic PRNG so fuzz tests are reproducible.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
