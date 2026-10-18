import Foundation
import Observation
import SwiftData
import ContractionCore

/// Contractions on one calendar day, newest first.
struct DaySection: Identifiable {
    let day: Date
    var records: [ContractionRecord]
    var id: Date { day }
}

/// What Undo puts back: rows to remove and rows to restore (upserted by id).
/// Covers stop (restore the in-progress row), delete (re-insert), add
/// (remove), and import (remove additions, restore overwritten rows).
struct UndoAction: Identifiable {
    let id = UUID()
    let message: String
    fileprivate let remove: [UUID]
    fileprivate let restore: [ContractionRecord]
}

struct ValidationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The single place that mutates contractions. The UI, the Live Activity
/// intent, and the Live Activity itself all go through here, so they never
/// drift. Views read the derived, value-typed `records`/`sections`.
@MainActor
@Observable
final class ContractionStore {
    static let shared = ContractionStore()

    /// Newest first.
    private(set) var records: [ContractionRecord] = []
    private(set) var inProgress: ContractionRecord?
    /// Start-to-previous-start, from `Stats.intervals`.
    private(set) var intervals: [UUID: TimeInterval] = [:]
    private(set) var sections: [DaySection] = []
    private(set) var completedCount = 0
    private(set) var undo: UndoAction?
    private(set) var isLiveActivityActive = false

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var context: ModelContext
    @ObservationIgnored private var models: [UUID: Contraction] = [:]
    @ObservationIgnored private var exportCache: String?
    @ObservationIgnored private var activityTask: Task<Void, Never>?

    init(inMemory: Bool = false) {
        container = Self.makeContainer(inMemory: inMemory)
        context = ModelContext(container)
        context.autosaveEnabled = false
        isLiveActivityActive = LiveActivityController.current != nil
        reload()
    }

    // MARK: Reading

    /// Time the "since last start" clock counts from.
    var latestStart: Date? { records.first?.start }

    /// Records with start ≥ `cutoff`, oldest first. Cheap: `records` is
    /// sorted newest first, so this only walks the recent prefix.
    func recent(since cutoff: Date) -> [ContractionRecord] {
        Array(records.prefix { $0.start >= cutoff }.reversed())
    }

    /// Plain-text share of every completed contraction (cached until the
    /// next change).
    var exportText: String {
        if let exportCache { return exportCache }
        let text = LogText.export(records.reversed().filter { !$0.isInProgress })
        exportCache = text
        return text
    }

    /// True while timing or within the idle window after the last start.
    func isSessionActive(now: Date = .now) -> Bool {
        if inProgress != nil { return true }
        guard let last = records.first else { return false }
        return now.timeIntervalSince(last.end ?? last.start) < LiveActivityController.idleTimeout
    }

    static func validationProblem(_ record: ContractionRecord, now: Date = .now) -> String? {
        if record.start > now.addingTimeInterval(Limits.futureTolerance) {
            return "Start can't be more than \(Int(Limits.futureTolerance / 60)) minutes in the future."
        }
        if let duration = record.duration {
            if duration < Limits.minDuration {
                return "A contraction needs to last at least \(Int(Limits.minDuration)) second."
            }
            if duration > Limits.maxDuration {
                return "A contraction can last at most \(Int(Limits.maxDuration / 60)) minutes."
            }
        }
        return nil
    }

    // MARK: Timing

    func toggle(at date: Date = .now) {
        if inProgress == nil {
            startContraction(at: date)
        } else {
            stopContraction(at: date)
        }
    }

    func startContraction(at date: Date = .now) {
        guard inProgress == nil else { return }
        insert(ContractionRecord(start: date, duration: nil))
        commit(undo: nil, allowActivityStart: true)
    }

    func stopContraction(at date: Date = .now) {
        guard let current = inProgress, let model = models[current.id] else { return }
        let elapsed = date.timeIntervalSince(current.start).rounded()
        var stopped = current
        stopped.duration = min(max(elapsed, Limits.minDuration), Limits.maxDuration)
        // Left running past the limit: keep it, but it is an estimate now.
        if elapsed > Limits.maxDuration { stopped.isApproximate = true }
        model.apply(stopped)
        commit(undo: UndoAction(message: "Saved · \(Format.duration(stopped.duration ?? 0, approximate: stopped.isApproximate))",
                                remove: [], restore: [current]))
    }

    // MARK: Editing

    /// Adds completed contractions (quick log). Throws on the first invalid one.
    func add(_ new: [ContractionRecord], now: Date = .now) throws {
        guard !new.isEmpty else { return }
        for record in new {
            guard record.duration != nil else { throw ValidationError(message: "Only completed contractions can be added.") }
            if let problem = Self.validationProblem(record, now: now) { throw ValidationError(message: problem) }
        }
        new.forEach(insert)
        let message = new.count == 1
            ? "Added \(Format.duration(new[0].duration ?? 0, approximate: new[0].isApproximate))"
            : "Added \(new.count) contractions"
        commit(undo: UndoAction(message: message, remove: new.map(\.id), restore: []))
    }

    func update(_ record: ContractionRecord, now: Date = .now) throws {
        guard let model = models[record.id] else { return }
        if let problem = Self.validationProblem(record, now: now) { throw ValidationError(message: problem) }
        var record = record
        // Only the row already in progress may stay open-ended.
        if record.isInProgress && !model.record.isInProgress { record.duration = model.duration }
        record.note = record.note.replacingOccurrences(of: "\n", with: " ")
        model.apply(record)
        commit(undo: nil)
    }

    func delete(_ ids: [UUID]) {
        let removed = ids.compactMap { models[$0] }
        guard !removed.isEmpty else { return }
        let snapshot = removed.map(\.record)
        removed.forEach(context.delete)
        commit(undo: UndoAction(message: removed.count == 1 ? "Deleted" : "Deleted \(removed.count)",
                                remove: [], restore: snapshot))
    }

    /// Applies a reviewed import: inserts `additions`, overwrites the rows
    /// in `replacements` (by id). Undo restores the pre-import state.
    func applyImport(additions: [ContractionRecord], replacements: [ContractionRecord]) {
        var originals: [ContractionRecord] = []
        for replacement in replacements {
            // Never overwrite a contraction that is being timed right now
            // (the plan may predate a Start from the Live Activity).
            guard let model = models[replacement.id], !model.record.isInProgress else { continue }
            originals.append(model.record)
            model.apply(replacement)
        }
        let newRows = additions.filter { models[$0.id] == nil && !$0.isInProgress }
        newRows.forEach(insert)
        guard !newRows.isEmpty || !originals.isEmpty else { return }
        var parts: [String] = []
        if !newRows.isEmpty { parts.append("Imported \(newRows.count)") }
        if !originals.isEmpty { parts.append("updated \(originals.count)") }
        commit(undo: UndoAction(message: parts.joined(separator: " · ").capitalizedFirst,
                                remove: newRows.map(\.id), restore: originals))
    }

    func deleteAll() {
        try? context.delete(model: Contraction.self)
        commit(undo: nil)
    }

    // MARK: Undo

    func performUndo() {
        guard let action = undo else { return }
        for id in action.remove {
            if let model = models[id] { context.delete(model) }
        }
        for record in action.restore {
            // Never end up with two contractions in progress.
            if record.isInProgress, let current = inProgress, current.id != record.id { continue }
            if let model = models[record.id] {
                model.apply(record)
            } else {
                insert(record)
            }
        }
        commit(undo: nil)
    }

    func clearUndo(_ id: UndoAction.ID? = nil) {
        if id == nil || undo?.id == id { undo = nil }
    }

    // MARK: Sync

    /// Re-reads the shared store (another process, e.g. the Live Activity
    /// intent, may have changed it).
    func refreshFromDisk() {
        context = ModelContext(container)
        context.autosaveEnabled = false
        reload()
    }

    /// Brings the Live Activity in line with the data and settings. Updates
    /// are chained so they apply in order.
    func syncLiveActivity(allowStart: Bool = false, now: Date = .now) {
        let target = activityTarget(now: now)
        let previous = activityTask
        activityTask = Task {
            await previous?.value
            isLiveActivityActive = await LiveActivityController.apply(target, allowStart: allowStart)
        }
    }

    func endLiveActivity() {
        let previous = activityTask
        activityTask = Task {
            await previous?.value
            isLiveActivityActive = await LiveActivityController.apply(nil, allowStart: false)
        }
    }

    func waitForLiveActivity() async {
        await activityTask?.value
    }

    // MARK: Private

    private func insert(_ record: ContractionRecord) {
        let model = Contraction(record)
        context.insert(model)
        models[record.id] = model
    }

    private func commit(undo newUndo: UndoAction?, allowActivityStart: Bool = false) {
        do {
            try context.save()
        } catch {
            context.rollback()
        }
        reload()
        undo = newUndo
        syncLiveActivity(allowStart: allowActivityStart)
    }

    private func reload() {
        let descriptor = FetchDescriptor<Contraction>(sortBy: [SortDescriptor(\.start, order: .reverse)])
        let fetched = (try? context.fetch(descriptor)) ?? []
        models = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        records = fetched.map(\.record)
        inProgress = records.first(where: \.isInProgress)
        completedCount = records.reduce(0) { $0 + ($1.isInProgress ? 0 : 1) }
        intervals = records.isEmpty ? [:] : Stats.intervals(records.reversed())
        sections = Self.groupByDay(records)
        exportCache = nil
    }

    private func activityTarget(now: Date) -> LiveActivityController.Target? {
        guard UserDefaults.shared.liveActivityEnabled, let latest = records.first else { return nil }
        let lastHourCount = Stats.window(recent(since: now.addingTimeInterval(-3600)), now: now).count

        if let current = inProgress {
            let lastCompleted = records.first { !$0.isInProgress }
            return .init(state: .init(phase: .contracting, phaseStart: current.start,
                                      lastDuration: lastCompleted?.duration,
                                      lastInterval: intervals[current.id],
                                      lastHourCount: lastHourCount),
                         staleDate: nil)
        }

        let restingSince = latest.end ?? latest.start
        guard now.timeIntervalSince(restingSince) < LiveActivityController.idleTimeout else { return nil }
        return .init(state: .init(phase: .resting, phaseStart: latest.start,
                                  lastDuration: latest.duration,
                                  lastInterval: intervals[latest.id],
                                  lastHourCount: lastHourCount),
                     staleDate: restingSince.addingTimeInterval(LiveActivityController.idleTimeout))
    }

    private static func groupByDay(_ records: [ContractionRecord]) -> [DaySection] {
        let calendar = Calendar.current
        var sections: [DaySection] = []
        for record in records {
            let day = calendar.startOfDay(for: record.start)
            if sections.last?.day == day {
                sections[sections.count - 1].records.append(record)
            } else {
                sections.append(DaySection(day: day, records: [record]))
            }
        }
        return sections
    }

    private static func makeContainer(inMemory: Bool) -> ModelContainer {
        let schema = Schema([Contraction.self])
        var configurations: [ModelConfiguration] = []
        if !inMemory {
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) != nil {
                configurations.append(ModelConfiguration("Contractions", schema: schema,
                                                         groupContainer: .identifier(AppGroup.id),
                                                         cloudKitDatabase: .none))
            }
            // Unsigned builds (no App Group entitlement) fall back to the
            // app's own container rather than failing to launch.
            configurations.append(ModelConfiguration("Contractions", schema: schema,
                                                     groupContainer: .none, cloudKitDatabase: .none))
        }
        configurations.append(ModelConfiguration("Contractions", schema: schema,
                                                 isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        for configuration in configurations {
            if let container = try? ModelContainer(for: schema, configurations: configuration) {
                return container
            }
        }
        fatalError("Could not create a model container")
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
