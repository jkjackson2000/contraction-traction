import SwiftUI
import ContractionCore

struct HomeView: View {
    @Environment(ContractionStore.self) private var store
    @Binding var importRequest: ImportRequest?
    @AppStorage(SettingsKey.keepScreenAwake, store: .shared) private var keepScreenAwake = true
    /// One sheet slot, so an opened file cleanly replaces whatever is up.
    @State private var sheet: HomeSheet?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TimerPanel { sheet = .quickLog }
                ContractionList { sheet = .edit($0) }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Contractions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { sheet = .settings } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { sheet = .importLog(nil) } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import")
                    ShareMenu()
                }
            }
            .overlay(alignment: .bottom) { UndoToast() }
        }
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case .quickLog: QuickLogSheet()
                case .settings: SettingsView()
                case .importLog(let request): ImportSheet(initialText: request?.text)
                case .edit(let record): EditSheet(original: record)
                }
            }
            .modifier(SaveErrorAlert(store: store))
        }
        .onChange(of: importRequest?.id, initial: true) {
            guard let request = importRequest else { return }
            importRequest = nil
            sheet = .importLog(request)
        }
        #if DEBUG
        .onAppear { runDemoScenario() }
        #endif
        .task(id: IdleKey(inProgress: store.inProgress?.id, latest: store.latestStart, keepAwake: keepScreenAwake)) {
            // Re-evaluated every 30 s so the screen may sleep once the
            // session goes idle.
            while !Task.isCancelled {
                UIApplication.shared.isIdleTimerDisabled =
                    store.inProgress != nil || (keepScreenAwake && store.isSessionActive())
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}

private enum HomeSheet: Identifiable {
    case quickLog, settings
    case importLog(ImportRequest?)
    case edit(ContractionRecord)

    var id: String {
        switch self {
        case .quickLog: "quickLog"
        case .settings: "settings"
        case .importLog(let request): "import-\(request?.id.uuidString ?? "")"
        case .edit(let record): "edit-\(record.id.uuidString)"
        }
    }
}

private struct IdleKey: Hashable {
    var inProgress: UUID?
    var latest: Date?
    var keepAwake: Bool
}

// MARK: - Timer panel

private struct TimerPanel: View {
    @Environment(ContractionStore.self) private var store
    let onLogPast: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            TimelineView(.periodic(from: store.inProgress?.start ?? store.latestStart ?? .now, by: 1)) { context in
                TimerButton(inProgress: store.inProgress, latestStart: store.latestStart, now: context.date) {
                    store.toggle()
                }
            }
            .sensoryFeedback(trigger: store.inProgress?.id) { old, new in
                new != nil ? .impact(weight: .heavy) : (old != nil ? .impact(weight: .medium) : nil)
            }

            HStack(spacing: 10) {
                Button(action: onLogPast) {
                    Label("Log past", systemImage: "clock.arrow.circlepath")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
                }
                .accessibilityHint("Add contractions from memory")

                if store.isLiveActivityActive && store.inProgress == nil {
                    Button { store.endLiveActivity() } label: {
                        Label("End session", systemImage: "xmark")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                    .accessibilityHint("Ends the Live Activity")
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Share

private struct ShareMenu: View {
    @Environment(ContractionStore.self) private var store
    @State private var showEmptyNote = false

    var body: some View {
        if store.completedCount > 0 {
            let text = store.exportText
            let file = LogFile(text: text, filename: LogFile.name(for: store.records.first { !$0.isInProgress }?.start))
            Menu {
                ShareLink(item: text, preview: SharePreview("Contraction log")) {
                    Label("Share as text…", systemImage: "text.bubble")
                }
                ShareLink(item: file, preview: SharePreview(file.filename)) {
                    Label("AirDrop file…", systemImage: "doc.text")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share log")
        } else {
            Button { showEmptyNote = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.tertiary)
            }
            .accessibilityLabel("Share log, nothing to share yet")
            .alert("Nothing to share yet", isPresented: $showEmptyNote) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Once you've timed or logged a contraction, you can share your log as text over Messages or AirDrop.")
            }
        }
    }
}

/// The same `LogText.export` text, as a .txt file for AirDrop.
struct LogFile: Transferable {
    let text: String
    let filename: String

    static func name(for lastStart: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d h-mm a"
        return "Contractions \(formatter.string(from: lastStart ?? .now)).txt"
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(file.filename)
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

// MARK: - Screenshot scenarios (Debug builds only)

#if DEBUG
/// `-demo empty|resting|list|bulk|timing|quicklog|import|partner` seeds sample data through
/// the store and opens a screen, for simulator screenshots.
private extension HomeView {
    func runDemoScenario() {
        guard let scenario = UserDefaults.standard.string(forKey: "demo") else { return }
        let now = Date.now
        store.deleteAll()
        guard scenario != "empty" else { return }

        // About 5 minutes apart for 70 minutes, ~1 minute long: meets 5-1-1.
        var seed: [ContractionRecord] = []
        let offsets: [(ago: Double, length: Double, approx: Bool, note: String)] = [
            (73, 48, false, ""), (68.5, 55, false, ""), (63, 52, true, ""), (58.5, 61, false, ""),
            (53.5, 58, false, "back pain"), (49, 64, false, ""), (44, 60, true, ""), (39.5, 66, false, ""),
            (34.5, 62, false, ""), (30, 71, false, "walked around"), (25, 65, false, ""), (20.5, 68, true, ""),
            (15.5, 72, false, ""), (11, 69, false, ""), (6, 75, false, "stronger"),
        ]
        for item in offsets {
            seed.append(ContractionRecord(start: now.addingTimeInterval(-item.ago * 60), duration: item.length,
                                          isApproximate: item.approx, note: item.note))
        }
        for hour in stride(from: 26.0, to: 22.0, by: -0.4) {
            seed.append(ContractionRecord(start: now.addingTimeInterval(-hour * 3600), duration: 40,
                                          isApproximate: true))
        }
        if scenario == "list" { seed = Array(seed.suffix(12)) }
        if scenario == "bulk" {
            seed = (0..<5000).map { (index: Int) -> ContractionRecord in
                let start = now.addingTimeInterval(Double(index) * -307 - 120)
                let note = index % 11 == 0 ? "note \(index)" : ""
                return ContractionRecord(start: start, duration: Double(40 + index % 40),
                                         isApproximate: index % 7 == 0, note: note)
            }
        }
        try? store.add(seed, now: now)

        switch scenario {
        case "timing":
            store.startContraction(at: now.addingTimeInterval(-42))
        case "quicklog":
            sheet = .quickLog
        case "import":
            var incoming = seed.suffix(6).enumerated().map { index, record in
                var copy = record
                copy.id = UUID()
                if index.isMultiple(of: 2) { copy.start = copy.start.addingTimeInterval(9); copy.isApproximate = false }
                return copy
            }
            incoming += QuickLog.series(mostRecentStart: now.addingTimeInterval(-80 * 60), count: 4,
                                        every: 300, duration: 45)
            sheet = .importLog(ImportRequest(text: LogText.export(incoming)))
        case "partner":
            // A partner's log of the same session: four earlier ones she
            // timed before I started, four identical, three timed a little
            // differently (one replaces my approximate entry).
            let today = Array(seed.prefix(offsets.count))
            func copy(_ index: Int, shift: Double = 0, length: Double? = nil, approx: Bool? = nil) -> ContractionRecord {
                let mine = today[index]
                return ContractionRecord(start: mine.start.addingTimeInterval(shift), duration: length ?? mine.duration,
                                         isApproximate: approx ?? mine.isApproximate, note: mine.note)
            }
            var incoming = [(92.8, 46.0), (88.1, 51.0), (83.4, 49.0), (78.2, 55.0)].map { ago, length in
                ContractionRecord(start: now.addingTimeInterval(-ago * 60), duration: length)
            }
            incoming += [copy(2, shift: -6, length: 57, approx: false), copy(5, shift: 7, length: 59),
                         copy(9, shift: 4, length: 68)]
            incoming += [10, 12, 13, 14].map { copy($0) }
            sheet = .importLog(ImportRequest(text: LogText.export(incoming.sorted { $0.start < $1.start })))
        default:
            break
        }
        store.clearUndo()
    }
}
#endif
