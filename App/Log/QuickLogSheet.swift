import SwiftUI
import ContractionCore

/// The fastest path in the app: log one or a run of contractions from
/// memory. Defaults (just now, about 1 minute, approximate) mean a single
/// tap on Add logs one.
struct QuickLogSheet: View {
    @Environment(ContractionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum When: Hashable {
        case minutesAgo(Int)
        case custom
    }

    @State private var when: When = .minutesAgo(0)
    @State private var customTime = Date.now
    @State private var duration: TimeInterval = 60
    @State private var count = 1
    @State private var every: TimeInterval = 300
    @State private var note = ""
    @State private var approximate = true
    @State private var errorMessage: String?
    @State private var addedMessage: String?
    @State private var addedCount = 0

    private static let whenOptions: [ChipOption<When>] = [
        .init("Just now", .minutesAgo(0)), .init("2 min", .minutesAgo(2)),
        .init("5 min", .minutesAgo(5)), .init("10 min", .minutesAgo(10)),
        .init("15 min", .minutesAgo(15)), .init("30 min", .minutesAgo(30)),
        .init("1 hr", .minutesAgo(60)), .init("Pick time…", .custom),
    ]
    private static let durationOptions: [ChipOption<TimeInterval>] = [
        .init("30s", 30), .init("45s", 45), .init("1m", 60), .init("1m 30s", 90), .init("2m", 120),
    ]
    private static let everyOptions: [ChipOption<TimeInterval>] = [
        .init("3 min", 180), .init("4 min", 240), .init("5 min", 300), .init("7 min", 420), .init("10 min", 600),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    section(count > 1 ? "How long ago did the last one start?" : "How long ago did it start?") {
                        ChipPicker(options: Self.whenOptions, selection: $when)
                        if when == .custom {
                            DatePicker("Started at", selection: $customTime, in: ...Date.now,
                                       displayedComponents: [.date, .hourAndMinute])
                                .padding(.top, 4)
                        }
                    }

                    section("Lasted about") {
                        ChipPicker(options: Self.durationOptions, selection: $duration)
                    }

                    section("How many?") {
                        CountStepper(count: $count)
                        if count > 1 {
                            Text("Every about")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                            ChipPicker(options: Self.everyOptions, selection: $every)
                        }
                    }

                    section("Note") {
                        TextField("Optional, e.g. back pain", text: $note)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .submitLabel(.done)
                    }

                    Toggle(isOn: $approximate) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Approximate")
                                .font(.body.weight(.medium))
                            Text("From memory. Shown with ~.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
                .animation(.smooth(duration: 0.25), value: count > 1)
                .animation(.smooth(duration: 0.25), value: when)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { actions }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Log past")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: addedCount)
            .onChange(of: InputKey(when: when, duration: duration, count: count, every: every)) {
                errorMessage = nil
                addedMessage = nil
            }
        }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.contracting)
            } else if let addedMessage {
                Label(addedMessage, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.resting)
            } else {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button { add(another: true) } label: {
                    Text("Add & log another")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

                Button { add(another: false) } label: {
                    Text(count > 1 ? "Add \(count)" : "Add")
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: Logic

    /// "When" is the start of the most recent one, nudged so it has ended
    /// by now.
    private func mostRecentStart(now: Date) -> Date {
        let chosen: Date
        switch when {
        case .minutesAgo(let minutes): chosen = now.addingTimeInterval(-Double(minutes) * 60)
        case .custom: chosen = customTime
        }
        return min(chosen, now.addingTimeInterval(-duration))
    }

    private func makeRecords(now: Date) -> [ContractionRecord] {
        QuickLog.series(mostRecentStart: mostRecentStart(now: now), count: count, every: every,
                        duration: duration,
                        note: note.trimmingCharacters(in: .whitespacesAndNewlines))
            .map { record in
                var record = record
                record.isApproximate = approximate
                return record
            }
    }

    private var summary: String {
        let records = makeRecords(now: .now)
        guard let first = records.first, let last = records.last else { return "" }
        let length = Format.duration(duration, approximate: approximate)
        let lastTime = last.start.formatted(date: .omitted, time: .shortened)
        if records.count == 1 { return "1 contraction at \(lastTime), \(length)." }
        let firstTime = first.start.formatted(date: .omitted, time: .shortened)
        return "\(records.count) contractions, \(length) each, \(firstTime) – \(lastTime)."
    }

    private func add(another: Bool) {
        let records = makeRecords(now: .now)
        do {
            try store.add(records)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        errorMessage = nil
        addedCount += 1
        if another {
            addedMessage = records.count == 1 ? "Added 1. Log another." : "Added \(records.count). Log another."
            count = 1
            note = ""
        } else {
            dismiss()
        }
    }
}

private struct InputKey: Equatable {
    var when: QuickLogSheet.When
    var duration: TimeInterval
    var count: Int
    var every: TimeInterval
}

/// Large −/+ stepper (the system Stepper's targets are small).
private struct CountStepper: View {
    @Binding var count: Int
    let range = 1...10

    var body: some View {
        HStack(spacing: 16) {
            stepButton("minus", enabled: count > range.lowerBound) { count -= 1 }
            Text("\(count)")
                .font(.system(.title, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 44)
                .contentTransition(.numericText())
            stepButton("plus", enabled: count < range.upperBound) { count += 1 }
            Spacer()
        }
        .animation(.snappy, value: count)
        .accessibilityRepresentation {
            Stepper("How many: \(count)", value: $count, in: range)
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .frame(width: 52, height: 52)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}
