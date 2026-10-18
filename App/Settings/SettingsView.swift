import ActivityKit
import SwiftUI
import ContractionCore

struct SettingsView: View {
    @Environment(ContractionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.patternRule, store: .shared) private var patternRule: PatternRule = .fiveOneOne
    @AppStorage(SettingsKey.keepScreenAwake, store: .shared) private var keepScreenAwake = true
    @AppStorage(SettingsKey.liveActivityEnabled, store: .shared) private var liveActivityEnabled = true
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Pattern", selection: $patternRule) {
                        ForEach(PatternRule.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Pattern note")
                } footer: {
                    Text("Shows a note when contractions have been about this many minutes apart, lasting about a minute, for about an hour. Informational only.")
                }

                Section {
                    Toggle("Keep screen awake", isOn: $keepScreenAwake)
                } footer: {
                    Text("The screen always stays on while a contraction is being timed. With this on, it also stays on between contractions while the app is open, until 2 hours after the last one.")
                }

                Section {
                    Toggle("Live Activity", isOn: $liveActivityEnabled)
                        .onChange(of: liveActivityEnabled) { _, enabled in
                            store.syncLiveActivity(allowStart: enabled && store.inProgress != nil)
                        }
                } footer: {
                    if ActivityAuthorizationInfo().areActivitiesEnabled {
                        Text("Shows the timer with a Start/Stop button on the Lock Screen and in the Dynamic Island. Ends after 2 hours without a contraction.")
                    } else {
                        Text("Live Activities are turned off for Contractions in the iOS Settings app.")
                    }
                }

                Section {
                    Button("Delete All Data", role: .destructive) { confirmDelete = true }
                        .disabled(store.records.isEmpty)
                } footer: {
                    Text("\(store.records.count) contraction\(store.records.count == 1 ? "" : "s") stored on this iPhone.")
                }

                Section("About") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Timing tool, not medical advice", systemImage: "heart.text.square")
                            .font(.headline)
                        Text(Disclaimer.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Private by design", systemImage: "lock")
                            .font(.headline)
                        Text("Nothing leaves your phone unless you share it. No accounts, no analytics, no network.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    LabeledContent("Version", value: Self.version)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete all contractions?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete All \(store.records.count)", role: .destructive) { store.deleteAll() }
            } message: {
                Text("This removes every contraction from this iPhone. It can't be undone.")
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
