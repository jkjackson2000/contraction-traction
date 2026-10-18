import SwiftUI
import ContractionCore

/// The big round Start/Stop button. Coral with a slow pulse while
/// contracting, calm teal while resting.
struct TimerButton: View {
    let inProgress: ContractionRecord?
    let latestStart: Date?
    let now: Date
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let size: CGFloat = 232

    private var contracting: Bool { inProgress != nil }

    var body: some View {
        Button(action: action) {
            ZStack {
                if contracting && !reduceMotion {
                    PulseRing(color: Theme.contracting)
                }
                Circle()
                    .fill(Theme.fill(contracting: contracting).gradient)
                    .shadow(color: Theme.fill(contracting: contracting).opacity(0.35), radius: 20, y: 10)
                Circle()
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                label
                    .foregroundStyle(.white)
                    .padding(28)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: contracting)
        .accessibilityLabel(contracting ? "Stop contraction" : "Start contraction")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var label: some View {
        if let inProgress {
            VStack(spacing: 0) {
                Text("CONTRACTING")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .opacity(0.85)
                Text(Format.clock(now.timeIntervalSince(inProgress.start)))
                    .font(.system(size: 66, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Tap to stop")
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.85)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        } else {
            VStack(spacing: 6) {
                Text("Start")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                if let latestStart {
                    VStack(spacing: 0) {
                        Text(Format.clock(now.timeIntervalSince(latestStart)))
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                        Text("since last start")
                            .font(.caption.weight(.medium))
                    }
                    .opacity(0.9)
                } else {
                    Text("Tap when one begins")
                        .font(.subheadline.weight(.medium))
                        .opacity(0.9)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        }
    }

    private var accessibilityValue: String {
        if let inProgress {
            return "Contracting for \(Format.spoken(now.timeIntervalSince(inProgress.start)))"
        }
        if let latestStart {
            return "\(Format.spoken(now.timeIntervalSince(latestStart))) since last start"
        }
        return ""
    }
}

private struct PulseRing: View {
    let color: Color

    var body: some View {
        Circle()
            .stroke(color.opacity(0.55), lineWidth: 8)
            .phaseAnimator([false, true]) { ring, expanded in
                ring
                    .scaleEffect(expanded ? 1.16 : 1)
                    .opacity(expanded ? 0 : 0.9)
            } animation: { expanded in
                expanded ? .easeOut(duration: 1.8) : .linear(duration: 0)
            }
            .accessibilityHidden(true)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
