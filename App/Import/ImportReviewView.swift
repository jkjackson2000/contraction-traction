import SwiftUI
import ContractionCore

/// Step 2: review the merge plan. New entries can be deselected; matched
/// pairs that differ are resolved globally or per row. Nothing existing is
/// ever deleted, and Undo restores the pre-import state.
struct ImportReviewView: View {
    let plan: ImportPlan
    let onDone: () -> Void

    @Environment(ContractionStore.self) private var store
    @State private var selectedAdditions: Set<UUID>
    @State private var choice: GlobalChoice = .suggested
    @State private var overrides: [UUID: MatchResolution] = [:]
    /// Set on the first tap so a double tap can't apply the import twice.
    @State private var isImporting = false
    @State private var errorMessage: String?
    private let additions: [ContractionRecord]

    enum GlobalChoice: String, CaseIterable, Identifiable {
        case suggested, keepMine, useTheirs
        var id: Self { self }
        var title: String {
            switch self {
            case .suggested: "Suggested"
            case .keepMine: "Keep mine"
            case .useTheirs: "Use theirs"
            }
        }
    }

    init(plan: ImportPlan, onDone: @escaping () -> Void) {
        self.plan = plan
        self.onDone = onDone
        additions = plan.additions.sorted { $0.start < $1.start }
        _selectedAdditions = State(initialValue: Set(plan.additions.map(\.id)))
    }

    var body: some View {
        List {
            Section {
                Text(summary)
                    .font(.headline)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }

            if additions.isEmpty && plan.matches.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.resting)
                        Text("Everything is already in your list")
                            .font(.headline)
                        Text("There's nothing new to add.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }

            if !additions.isEmpty {
                Section {
                    ForEach(additions) { record in
                        Toggle(isOn: binding(for: record.id)) {
                            RecordSummary(record: record)
                        }
                    }
                } header: {
                    HStack {
                        Text("New")
                        Spacer()
                        Button(selectedAdditions.count == additions.count ? "Select none" : "Select all") {
                            selectedAdditions = selectedAdditions.count == additions.count ? [] : Set(additions.map(\.id))
                        }
                        .font(.footnote.weight(.semibold))
                        .textCase(nil)
                    }
                }
            }

            if !plan.matches.isEmpty {
                Section {
                    Picker("Resolve all", selection: $choice) {
                        ForEach(GlobalChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: choice) { overrides = [:] }

                    ForEach(plan.matches) { match in
                        MatchRow(match: match, resolution: resolutionBinding(for: match))
                    }
                } header: {
                    Text("To resolve")
                } footer: {
                    Text("The same contraction was timed on both phones, differently. Tap a version to choose it. Suggested keeps yours unless yours is approximate and theirs was timed.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.contracting)
                        .multilineTextAlignment(.center)
                }
                Button(action: importNow) {
                    Text(buttonTitle)
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(isImporting)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Logic

    private var summary: String {
        var parts = ["\(plan.additions.count) new",
                     "\(plan.matches.count) to resolve",
                     "\(plan.identicalCount) already in your list"]
        if plan.collapsedIncomingCount > 0 {
            parts.append("\(plan.collapsedIncomingCount) duplicate\(plan.collapsedIncomingCount == 1 ? "" : "s") in the text")
        }
        return parts.joined(separator: " · ")
    }

    private func resolution(for match: ImportPlan.Match) -> MatchResolution {
        // A contraction being timed right now always stays as is.
        if match.existing.isInProgress { return .keepMine }
        if let override = overrides[match.id] { return override }
        switch choice {
        case .suggested: return match.suggested
        case .keepMine: return .keepMine
        case .useTheirs: return .useTheirs
        }
    }

    private var updateCount: Int {
        plan.matches.filter { resolution(for: $0) == .useTheirs }.count
    }

    private var buttonTitle: String {
        let adding = selectedAdditions.count, updating = updateCount
        if adding == 0 && updating == 0 { return "Done" }
        var parts: [String] = []
        if adding > 0 { parts.append("Add \(adding)") }
        if updating > 0 { parts.append("Update \(updating)") }
        return "Import · " + parts.joined(separator: ", ")
    }

    private func importNow() {
        guard !isImporting else { return }
        isImporting = true
        let chosen = plan.additions.filter { selectedAdditions.contains($0.id) }
        let replacements = plan.matches
            .filter { resolution(for: $0) == .useTheirs }
            .map { Merge.apply(.useTheirs, to: $0) }
        do {
            try store.applyImport(additions: chosen, replacements: replacements)
        } catch {
            errorMessage = error.localizedDescription
            isImporting = false
            return
        }
        onDone()
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding {
            selectedAdditions.contains(id)
        } set: { isOn in
            if isOn { selectedAdditions.insert(id) } else { selectedAdditions.remove(id) }
        }
    }

    private func resolutionBinding(for match: ImportPlan.Match) -> Binding<MatchResolution> {
        Binding { resolution(for: match) } set: { overrides[match.id] = $0 }
    }
}

private struct RecordSummary: View {
    let record: ContractionRecord
    var showsDate = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(record.start, format: .dateTime.hour().minute().second())
                    .monospacedDigit()
                Text(record.duration.map { Format.duration($0, approximate: record.isApproximate) } ?? "In progress")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.subheadline)
            if showsDate {
                Text(record.start, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !record.note.isEmpty {
                Text(record.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct MatchRow: View {
    let match: ImportPlan.Match
    @Binding var resolution: MatchResolution

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(match.existing.start, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(delta)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                version("Mine", match.existing, .keepMine)
                version("Theirs", match.incoming, .useTheirs)
            }
        }
        .padding(.vertical, 4)
    }

    private var delta: String {
        let seconds = match.startDelta.rounded()
        if seconds == 0 { return "Same start" }
        return "Δ start \(seconds > 0 ? "+" : "−")\(LogText.formatDuration(abs(seconds)))"
    }

    private func version(_ title: String, _ record: ContractionRecord, _ value: MatchResolution) -> some View {
        let selected = resolution == value
        return Button { resolution = value } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(title).font(.caption.weight(.bold))
                    if match.suggested == value {
                        Text("Suggested")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                }
                RecordSummary(record: record, showsDate: false)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(record.start.formatted(date: .omitted, time: .standard)), \(record.duration.map { Format.spoken($0) } ?? "in progress")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
