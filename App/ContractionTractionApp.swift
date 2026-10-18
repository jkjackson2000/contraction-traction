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
                if hasSeenDisclaimer {
                    HomeView(importRequest: $importRequest)
                } else {
                    DisclaimerView { withAnimation { hasSeenDisclaimer = true } }
                }
            }
            .environment(store)
            .tint(.accentColor)
            .onOpenURL { url in
                // A .txt log arriving via AirDrop, Files, or Messages.
                importRequest = ImportRequest(text: IncomingFile.read(url))
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
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
}
