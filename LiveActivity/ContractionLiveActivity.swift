import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ContractionWidgets: WidgetBundle {
    var body: some Widget {
        ContractionLiveActivity()
    }
}

struct ContractionLiveActivity: Widget {
    typealias State = ContractionActivityAttributes.ContentState

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ContractionActivityAttributes.self) { context in
            LockScreenView(state: context.state, isStale: context.isStale)
                .activitySystemActionForegroundColor(Theme.color(contracting: context.state.isContracting))
        } dynamicIsland: { context in
            let state = context.state
            let tint = Theme.color(contracting: state.isContracting)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PhaseLabel(state: state, isStale: context.isStale)
                        .padding(.leading, 6)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: state.timerRange, countsDown: false)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(tint)
                        .frame(maxWidth: 140, alignment: .trailing)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .center, spacing: 12) {
                        LastStats(state: state)
                        Spacer(minLength: 0)
                        ToggleButton(state: state)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Circle()
                    .fill(tint)
                    .frame(width: 12, height: 12)
                    .padding(.leading, 2)
                    .accessibilityLabel(state.isContracting ? "Contracting" : "Resting")
            } compactTrailing: {
                Text(timerInterval: state.timerRange, countsDown: false)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 50, alignment: .trailing)
            } minimal: {
                ZStack {
                    Circle().strokeBorder(tint, lineWidth: 2.5)
                    Text(timerInterval: state.timerRange, countsDown: false)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                        .padding(4)
                }
            }
            .keylineTint(tint)
        }
    }
}

// MARK: - Pieces

private struct PhaseLabel: View {
    let state: ContractionActivityAttributes.ContentState
    var isStale = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state.isContracting ? "waveform.path" : "leaf.fill")
                .font(.footnote.weight(.bold))
            VStack(alignment: .leading, spacing: 0) {
                Text(state.isContracting ? "Contracting" : "Resting")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(Theme.color(contracting: state.isContracting))
    }

    private var subtitle: String {
        if state.isContracting { return "Duration" }
        return isStale ? "No contractions lately" : "Since last start"
    }
}

private struct LastStats: View {
    let state: ContractionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            stat("Last", state.lastDuration.map { Format.duration($0) } ?? "–", symbol: "timer")
            stat("Every", state.lastInterval.map(Format.interval) ?? "–", symbol: "arrow.left.and.right")
            stat("Last hour", "\(state.lastHourCount)", symbol: "clock")
        }
        .font(.footnote)
    }

    private func stat(_ title: String, _ value: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(title).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ToggleButton: View {
    let state: ContractionActivityAttributes.ContentState

    var body: some View {
        Button(intent: ToggleContractionIntent()) {
            Label(state.isContracting ? "Stop" : "Start",
                  systemImage: state.isContracting ? "stop.fill" : "play.fill")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(Theme.fill(contracting: state.isContracting), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isContracting ? "Stop contraction" : "Start contraction")
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let state: ContractionActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                PhaseLabel(state: state, isStale: isStale)
                Text(timerInterval: state.timerRange, countsDown: false)
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                LastStats(state: state)
            }
            Spacer(minLength: 0)
            ToggleButton(state: state)
        }
        .padding(18)
    }
}

// MARK: - Previews

#Preview("Lock Screen", as: .content, using: ContractionActivityAttributes()) {
    ContractionLiveActivity()
} contentStates: {
    ContractionActivityAttributes.ContentState(phase: .contracting, phaseStart: .now.addingTimeInterval(-42),
                                               lastDuration: 58, lastInterval: 312, lastHourCount: 7)
    ContractionActivityAttributes.ContentState(phase: .resting, phaseStart: .now.addingTimeInterval(-195),
                                               lastDuration: 64, lastInterval: 298, lastHourCount: 8)
}
