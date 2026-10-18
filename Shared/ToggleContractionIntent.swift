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

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = ContractionStore.shared
        // Another process may have written since this one last looked.
        store.refreshFromDisk()
        store.toggle()
        store.clearUndo()
        await store.waitForLiveActivity()
        return .result()
    }
}
