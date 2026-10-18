import ActivityKit
import Foundation

struct ContractionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case contracting, resting
        }

        var phase: Phase
        /// The instant the live timer counts up from. Contracting: the start
        /// of the contraction in progress. Resting: the start of the most
        /// recent contraction, matching the app's "since last start".
        var phaseStart: Date
        /// Duration of the most recent completed contraction.
        var lastDuration: TimeInterval?
        /// Start-to-start interval of the most recent contraction.
        var lastInterval: TimeInterval?
        /// Completed contractions in the last hour.
        var lastHourCount: Int

        var isContracting: Bool { phase == .contracting }

        /// `Text(timerInterval:)` needs a closed range; a day is plenty.
        var timerRange: ClosedRange<Date> { phaseStart...phaseStart.addingTimeInterval(24 * 3600) }
    }
}
