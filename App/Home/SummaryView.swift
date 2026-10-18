import Charts
import SwiftUI
import ContractionCore

/// Pattern banner, last-hour stats, and the recent timeline. Refreshes on a
/// timer because "last hour" moves with the clock.
struct SummaryView: View {
    @Environment(ContractionStore.self) private var store
    @AppStorage(SettingsKey.patternRule, store: .shared) private var patternRule: PatternRule = .fiveOneOne

    var body: some View {
        TimelineView(.periodic(from: .now, by: store.inProgress == nil ? 30 : 5)) { context in
            let now = context.date
            let recent = store.recent(since: now.addingTimeInterval(-TimelineChart.window))
            VStack(spacing: 12) {
                if patternRule != .off, patternRule.isMet(by: recent, now: now) {
                    PatternBanner(rule: patternRule)
                }
                StatsRow(stats: Stats.window(recent, now: now))
                let completed = recent.filter { !$0.isInProgress }
                if !completed.isEmpty {
                    TimelineChart(records: completed, now: now)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct PatternBanner: View {
    let rule: PatternRule

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.headline)
                .foregroundStyle(Theme.contracting)
            VStack(alignment: .leading, spacing: 4) {
                Text("This looks like \(rule.title)")
                    .font(.headline)
                Text("About \(Int((rule.maxInterval ?? 0) / 60)) minutes apart, lasting about a minute, for an hour. Follow your provider's instructions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.contracting.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct StatsRow: View {
    let stats: WindowStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last hour")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 0) {
                stat("Count", "\(stats.count)")
                Divider().frame(height: 36)
                stat("Avg length", stats.averageDuration.map { Format.duration($0.rounded()) } ?? "–")
                Divider().frame(height: 36)
                stat("Avg apart", stats.averageInterval.map { Format.interval($0.rounded()) } ?? "–")
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// One bar per contraction: x is when it started, height is how long it
/// lasted. Approximate entries are faded.
struct TimelineChart: View {
    static let window: TimeInterval = 2 * 3600

    let records: [ContractionRecord]
    let now: Date

    private var hasApproximate: Bool { records.contains(where: \.isApproximate) }
    private var maxDuration: Double { records.compactMap(\.duration).max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last 2 hours")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if hasApproximate {
                    Label("approximate", systemImage: "circle.fill")
                        .labelStyle(LegendLabelStyle())
                }
            }
            Chart(records) { record in
                BarMark(x: .value("Started", record.start),
                        y: .value("Seconds", record.duration ?? 0),
                        width: .fixed(7))
                    .foregroundStyle(Theme.contracting.opacity(record.isApproximate ? 0.35 : 1))
                    .clipShape(Capsule())
            }
            .chartXScale(domain: now.addingTimeInterval(-Self.window)...now)
            .chartYScale(domain: 0...max(120, maxDuration))
            .chartXAxis {
                AxisMarks(values: .stride(by: .minute, count: 30)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [60, 120, 180, 300, 600].filter { $0 <= max(120, maxDuration) }) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let seconds = value.as(Double.self) { Text("\(Int(seconds / 60))m") }
                    }
                }
            }
            .frame(height: 120)
            .accessibilityLabel("Timeline of \(records.count) contractions in the last 2 hours")
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct LegendLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .font(.system(size: 7))
                .foregroundStyle(Theme.contracting.opacity(0.35))
            configuration.title
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
