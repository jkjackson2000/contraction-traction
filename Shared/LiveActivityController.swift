import ActivityKit
import Foundation

/// Thin wrapper over ActivityKit. The store decides *what* the activity
/// should show (`Target`); this type only reconciles the system with it.
@MainActor
enum LiveActivityController {
    typealias State = ContractionActivityAttributes.ContentState

    /// Rest longer than this ends the session's Live Activity.
    static let idleTimeout: TimeInterval = 2 * 3600

    struct Target {
        var state: State
        var staleDate: Date?
    }

    static var current: Activity<ContractionActivityAttributes>? {
        Activity<ContractionActivityAttributes>.activities.first {
            $0.activityState != .ended && $0.activityState != .dismissed
        }
    }

    /// Updates, starts (only when `allowStart`), or ends the activity so it
    /// matches `target`. Returns whether an activity is live afterwards.
    @discardableResult
    static func apply(_ target: Target?, allowStart: Bool) async -> Bool {
        let live = Activity<ContractionActivityAttributes>.activities.filter {
            $0.activityState != .ended && $0.activityState != .dismissed
        }
        guard let target else {
            for activity in live {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return false
        }

        let content = ActivityContent(state: target.state, staleDate: target.staleDate)
        if let activity = live.first {
            await activity.update(content)
            for extra in live.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
            return true
        }

        guard allowStart, ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        do {
            _ = try Activity.request(attributes: ContractionActivityAttributes(),
                                     content: content, pushType: nil)
            return true
        } catch {
            // Not allowed right now (e.g. requested from the background). The
            // next Start from the app tries again.
            return false
        }
    }
}
