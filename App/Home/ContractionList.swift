import SwiftUI
import ContractionCore

/// Summary (pattern, stats, chart) followed by contractions grouped by day,
/// newest first. `List` keeps 5,000 rows cheap.
struct ContractionList: View {
    @Environment(ContractionStore.self) private var store
    let onEdit: (ContractionRecord) -> Void

    var body: some View {
        List {
            if store.records.isEmpty {
                EmptyStateCard()
                    .plainRow()
            } else {
                SummaryView()
                    .plainRow()
            }

            ForEach(store.sections) { section in
                Section {
                    ForEach(section.records) { record in
                        Button { onEdit(record) } label: {
                            ContractionRow(record: record, interval: store.displayInterval(for: record.id))
                        }
                        .foregroundStyle(.primary)
                        .listRowBackground(Theme.card)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { store.delete([record.id]) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    DayHeader(day: section.day, count: section.records.count)
                }
            }

            // Room for the Undo toast.
            Color.clear.frame(height: 56).plainRow()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 4, for: .scrollContent)
    }
}

private extension View {
    func plainRow() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

private struct DayHeader: View {
    let day: Date
    let count: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)")
                .monospacedDigit()
                .accessibilityLabel("\(count) contractions")
        }
        .font(.footnote.weight(.semibold))
    }

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

struct ContractionRow: View {
    let record: ContractionRecord
    let interval: TimeInterval?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Capsule()
                .fill(record.isInProgress ? Theme.contracting : Theme.resting)
                .opacity(record.isApproximate ? 0.35 : 1)
                .frame(width: 4, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.start, format: .dateTime.hour().minute())
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                if !record.note.isEmpty {
                    Text(record.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                if let duration = record.duration {
                    Text(Format.duration(duration, approximate: record.isApproximate))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                } else {
                    Text("In progress")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.contracting)
                }
                if let interval {
                    Text("\(Format.interval(interval)) apart")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint("Opens editor")
    }

    private var spokenLabel: String {
        var parts = [record.start.formatted(date: .omitted, time: .shortened)]
        if let duration = record.duration {
            parts.append((record.isApproximate ? "lasted about " : "lasted ") + Format.spoken(duration))
        } else {
            parts.append("in progress")
        }
        if let interval { parts.append("\(Format.spoken(interval)) after the previous one") }
        if !record.note.isEmpty { parts.append("note: \(record.note)") }
        return parts.joined(separator: ", ")
    }
}

private struct EmptyStateCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.tap")
                .font(.title2)
                .foregroundStyle(Theme.resting)
            Text("Tap Start when a contraction begins, and again when it ends.")
                .font(.body)
                .multilineTextAlignment(.center)
            Text("Missed some? Use Log past to add them from memory.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20)
    }
}

// MARK: - Undo

struct UndoToast: View {
    @Environment(ContractionStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let undo = store.undo {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.resting)
                    Text(undo.message)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Button("Undo") { store.performUndo() }
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 6)
                        .frame(minHeight: 44)
                }
                .padding(.leading, 16)
                .padding(.trailing, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .task(id: undo.id) {
                    try? await Task.sleep(for: .seconds(5))
                    store.clearUndo(undo.id)
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: store.undo?.id)
    }
}
