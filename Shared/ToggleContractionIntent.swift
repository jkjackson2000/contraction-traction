import AppIntents
import Foundation

/// Start/Stop from the Dynamic Island and Lock Screen without opening the
/// app. Compiled into both targets; the system runs `perform` in the app's
/// process (launching it in the background if needed). Everything goes
/// through the shared App Group store, so it also works if it runs elsewhere.
struct ToggleContractionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start or Stop Contraction"
    static let description = IntentDescription("Starts timing a contraction, or stops the one in progress.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    /// What the button showed when tapped. Acting on that, rather than
    /// toggling, keeps a double tap or a stale Lock Screen from starting a
    /// phantom contraction.
    @Parameter(title: "Start")
    var shouldStart: Bool

    init(shouldStart: Bool) {
        self.shouldStart = shouldStart
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = ContractionStore.shared
        guard store.loadError == nil else { throw ValidationError(message: "Couldn't open your saved contractions.") }
        // Another process may have written since this one last looked.
        store.refreshFromDisk()
        if shouldStart && store.inProgress == nil {
            store.startContraction()
        } else if !shouldStart && store.inProgress != nil {
            store.stopContraction()
        } else {
            // Already in the requested state: just bring the activity up to date.
            store.syncLiveActivity()
        }
        store.clearUndo()
        await store.waitForLiveActivity()
        return .result()
    }
}
