import SwiftUI

@main
struct ContractionTractionApp: App {
    @State private var store = ContractionStore.shared
    @State private var importRequest: ImportRequest?
    @AppStorage(SettingsKey.hasSeenDisclaimer, store: .shared) private var hasSeenDisclaimer = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let loadError = store.loadError {
                    StoreErrorView(detail: loadError)
                } else if hasSeenDisclaimer {
                    HomeView(importRequest: $importRequest)
                } else {
                    DisclaimerView { withAnimation { hasSeenDisclaimer = true } }
                }
            }
            .environment(store)
            .tint(.accentColor)
            .modifier(SaveErrorAlert(store: store))
            .onOpenURL { url in
                // A .txt log arriving via AirDrop, Files, or Messages.
                do {
                    importRequest = ImportRequest(text: try IncomingFile.read(url))
                } catch {
                    importRequest = ImportRequest(text: "", error: error.localizedDescription)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, store.loadError == nil else { return }
                // The Live Activity intent may have changed data while we
                // were away; this also ends an activity idle for 2 hours.
                store.refreshFromDisk()
                store.syncLiveActivity()
            }
        }
    }
}

/// Text to open the Import sheet with (from an opened file).
struct ImportRequest: Identifiable {
    let id = UUID()
    let text: String
    let error: String?

    init(text: String, error: String? = nil) {
        self.text = text
        self.error = error
    }
}

/// Shows `ContractionStore.lastError`. Attached at the root and inside the
/// Home sheets, because an alert can't present from under a sheet.
struct SaveErrorAlert: ViewModifier {
    let store: ContractionStore

    func body(content: Content) -> some View {
        content.alert("Couldn't save", isPresented: Binding(get: { store.lastError != nil },
                                                            set: { if !$0 { store.clearError() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

/// Shown instead of the app when the saved store won't open, so nobody
/// carries on timing into an empty list that may not be saved.
private struct StoreErrorView: View {
    let detail: String

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.contracting)
                    .accessibilityHidden(true)
                Text("Couldn't open your saved contractions")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("Nothing has been deleted. Close Contractions and open it again. If this keeps happening, free up some storage on your iPhone and try again.")
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .multilineTextAlignment(.center)
            .padding(28)
            .padding(.top, 60)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
