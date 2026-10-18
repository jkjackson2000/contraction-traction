import SwiftUI
import ContractionCore

struct EditSheet: View {
    let original: ContractionRecord

    @Environment(ContractionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Start, to the minute (DatePicker has no seconds) plus a seconds field.
    @State private var startMinute: Date
    @State private var startSecond: Int
    @State private var durationMinutes: Int
    @State private var durationSeconds: Int
    @State private var isApproximate: Bool
    @State private var note: String
    @State private var saveError: String?

    init(original: ContractionRecord) {
        self.original = original
        let calendar = Calendar.current
        let second = calendar.component(.second, from: original.start)
        _startMinute = State(initialValue: original.start.addingTimeInterval(-Double(second)))
        _startSecond = State(initialValue: second)
        let duration = Int(original.duration ?? 60)
        _durationMinutes = State(initialValue: duration / 60)
        _durationSeconds = State(initialValue: duration % 60)
        _isApproximate = State(initialValue: original.isApproximate)
        _note = State(initialValue: original.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Started") {
                    DatePicker("Time", selection: $startMinute, displayedComponents: [.date, .hourAndMinute])
                    Picker("Seconds", selection: $startSecond) {
                        ForEach(0..<60, id: \.self) { Text(String(format: ":%02d", $0)).tag($0) }
                    }
                }

                Section {
                    if original.isInProgress {
                        LabeledContent("Lasted") {
                            Text("In progress").foregroundStyle(Theme.contracting)
                        }
                    } else {
                        HStack(spacing: 0) {
                            Picker("Minutes", selection: $durationMinutes) {
                                ForEach(0...Int(Limits.maxDuration / 60), id: \.self) { Text("\($0) min").tag($0) }
                            }
                            Picker("Seconds", selection: $durationSeconds) {
                                ForEach(0..<60, id: \.self) { Text("\($0) sec").tag($0) }
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 140)
                        .accessibilityElement(children: .contain)
                    }
                } header: {
                    Text("Lasted")
                }

                Section {
                    Toggle("Approximate", isOn: $isApproximate)
                } footer: {
                    Text("Entered from memory or estimated. Shown with ~.")
                }

                Section("Note") {
                    TextField("Optional", text: $note)
                }

                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.contracting)
                    }
                }

                Section {
                    Button("Delete Contraction", role: .destructive) {
                        store.delete([original.id])
                        if store.lastError == nil { dismiss() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: edited) { saveError = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(problem != nil)
                }
            }
        }
    }

    private var edited: ContractionRecord {
        let minute = Calendar.current.dateInterval(of: .minute, for: startMinute)?.start ?? startMinute
        return ContractionRecord(
            id: original.id,
            start: minute.addingTimeInterval(Double(startSecond)),
            duration: original.isInProgress ? nil : Double(durationMinutes * 60 + durationSeconds),
            isApproximate: isApproximate,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var problem: String? {
        saveError ?? ContractionStore.validationProblem(edited)
    }

    private func save() {
        do {
            try store.update(edited)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
