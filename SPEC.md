# Contraction Traction — v1 Spec

Free, fully local iPhone contraction timer. No accounts, servers, or
analytics. Partners share their logs as plain text over iMessage or AirDrop.
The receiver pastes the text in, reviews the merge, and confirms it.

The canonical contract for the data and algorithms is
`Packages/ContractionCore/Sources/ContractionCore/API.swift`. When this
document and that file disagree, the code wins.

## Identity

| | |
|---|---|
| Team | `MSXGHATPMF` (Jared Jackson, individual) |
| App bundle ID | `com.jaredjackson.ContractionTraction` |
| Live Activity widget | `com.jaredjackson.ContractionTraction.LiveActivity` |
| App Group | `group.com.jaredjackson.ContractionTraction` (shared SwiftData store, so the Live Activity Stop/Start intent and the app see the same data) |

## Goals

- Ship fast: the smallest app that is great to use during real labor.
- Fully local. The App Store privacy label is **Data Not Collected**.
- Partner backfill. When she uses my phone, or I time some while she
  sleeps, I paste my log into hers. Gaps get filled, and conflicts are her
  choice.
- Make it easy to log from memory. Approximate entries are first-class,
  because there is human error in both live and remembered timings.

## Non-goals (v1)

Accounts, cloud or iCloud sync, Apple Watch, home-screen widgets, HealthKit,
iPad layout, and localization.

## Platform

- SwiftUI, SwiftData, ActivityKit, and App Intents.
- iOS 17+, iPhone only. Swift Charts for the timeline.
- No third-party dependencies and no networking code.
- XcodeGen `project.yml`. Pure logic lives in the local SPM package
  `ContractionCore` (tested with `swift test`).

## Terms

| Term | Definition |
|---|---|
| Duration | `end − start` |
| Interval (frequency) | `start − previous.start` |
| Approximate | Entered from memory or estimated. Shown as `~58s`. |

## Data model

The app stores this SwiftData `@Model` and maps it 1:1 to
`ContractionRecord`:

- `id: UUID`
- `start: Date`, in whole seconds
- `duration: Double?`, where nil means in progress (at most one at a time)
- `isApproximate: Bool`
- `note: String`

Durations, intervals, and stats are always derived and never stored.

## Screens

### Timer (home)

- A large round **Start / Stop** button with a live timer. Its color shifts
  between *contracting* and *resting*.
- While resting, it shows the time since the last contraction started.
- Haptics on every tap.
- Last-hour stats: count, average duration, and average interval.
- A timeline of the last hour or two (Swift Charts): one bar per
  contraction, with bar length showing duration. Approximate bars are
  hatched or faded.
- A pattern banner when the chosen rule (5-1-1 by default) is met.
- The list is newest first and grouped by day. Each row shows the time,
  duration, interval, a `~` badge, and the note.
- Swipe to delete. Tap a row to edit it.
- An **Undo** toast for about 5 seconds after Stop, delete, add, or import.
- The screen stays awake while timing.

### Quick log (past contractions)

This needs to be the fastest path in the app. It opens from a prominent
"Log past" button and defaults to approximate.

- **When**: chips for *Just now, 2, 5, 10, 15, 30, 60 min ago*, plus a
  time picker.
- **Lasted about**: chips for *30s, 45s, 1m, 1m 30s, 2m*.
- **How many**: a stepper from 1 to 10. When it's above 1, an **every
  about** chip row appears (*3, 4, 5, 7, 10 min*), so "4 of them about every
  5 min, the last one 10 min ago" takes three taps
  (`QuickLog.series`).
- An optional note.
- An approximate toggle, on by default.
- **Add**, plus **Add & log another**.

### Edit sheet

- The start time (with seconds), the duration, the approximate toggle, the
  note, and Delete.
- Validation follows `Limits` (1 s to 10 min, at most 5 min in the future).

### Share

- `ShareLink` shares `LogText.export` (plain text) of all completed
  contractions, and nothing else.
- The text is readable as a note in iMessage, Notes, or anywhere else.
- The Share control is a menu with two items:
  - **Share as text…** (the default, for iMessage).
  - **AirDrop file…**, which sends the same text as a `.txt` file.
- The app declares itself an opener for `public.plain-text` (rank
  `Alternate`). On the receiving phone, AirDrop or Files then offers
  "Open with Contractions", which leads to Import Review prefilled with
  the text.

### Import (paste)

- Opened with an "Import" button.
- A SwiftUI `PasteButton` avoids the paste permission prompt. There is
  also an editable `TextEditor` for typing or fixing the text.
- A live count shows how many entries were recognized and how many lines
  were rejected.
- Then the **Review** step:
  - "8 new · 3 to resolve · 4 already in your list."
  - **New**: checked by default and toggleable per row, shown in time order.
  - **To resolve** (the same contraction tracked twice and different): a
    global segmented control (*Suggested / Keep mine / Use theirs*), with
    a per-row override. Each row shows both versions and the Δstart.
  - Confirm with **Import**. Undo restores the snapshot from before the
    import, including any rows overwritten with "use theirs".

### Live Activity and Dynamic Island

The Live Activity starts on the first Start and updates on every
Start/Stop. ContentState holds `phase` (contracting or resting),
`phaseStart`, the last duration, the last interval, and the last-hour
count.

- **Compact**: a phase-colored dot on the leading side, and a live
  `Text(timerInterval:)` on the trailing side.
- **Minimal**: a phase-colored dot with the timer.
- **Expanded**: a big live timer, the phase label, the last duration and
  interval, and a large **Start/Stop button** (a `LiveActivityIntent`
  toggles the contraction without opening the app).
- **Lock screen**: the same content as Expanded.
- **When it ends**: when the user taps End in the app, or automatically
  after 2 hours of rest. Set a `staleDate` and check on foreground.
- A Settings toggle controls the Live Activity (on by default).

### Settings

- Pattern rule: 5-1-1, 4-1-1, 3-1-1, or Off.
- Keep screen awake.
- Live Activity.
- Delete all data, with a confirmation step.
- About: the disclaimer, the privacy note, and the version number.

### First launch

One disclaimer screen: "Timing tool, not medical advice. Follow your
provider's instructions. In an emergency call 911." Then **Got it**.

## Share text format

The full grammar is in the `LogText` docs in `API.swift`. Example:

```
Contraction Traction log
12 contractions · Oct 18, 2:10 PM – 3:42 PM
Time zone: America/Chicago (UTC-05:00)
~ = approximate

2026-10-18 2:10:03 PM · 58s
2026-10-18 2:15:40 PM · ~1m 05s · back pain
```

The parser ignores everything except lines that start with a date. That
means a whole iMessage thread or a Notes page can be pasted in safely, and
it also accepts hand-typed lines like `2026-10-18 14:10 | ~1m`.

## Merge rules

The full definition is in the `Merge` docs in `API.swift`:

1. Incoming entries are deduplicated against each other first.
2. An incoming entry and an existing entry are candidates for a match when
   their ranges overlap, or when their starts are ≤ 45 s apart. The
   allowance widens to ≤ 120 s if either entry is approximate.
3. Entries are paired one-to-one, closest start first. This keeps two real
   back-to-back contractions from merging into one.
4. Nothing existing is ever deleted. Unmatched incoming entries are added.
   A matched pair that is identical is skipped silently.
5. For a matched pair that differs, the suggested choice is to keep the
   receiver's version, unless hers is approximate and the incoming one is
   exact. The user can override with *Keep mine* or *Use theirs*, either
   for all pairs or one row at a time.

## Pattern rule

Defined in `PatternRule.isMet` in `API.swift`. It requires at least 6
contractions covering 50 minutes or more, with the averages within the rule
and the pattern still current. The wording is informational only.

## App Store safety

- The privacy label is "Data Not Collected". `PrivacyInfo.xcprivacy` sets
  `NSPrivacyTracking = false`, collects no data types, and declares the
  required-reason API `NSPrivacyAccessedAPICategoryUserDefaults` with
  reason `CA92.1`.
- `ITSAppUsesNonExemptEncryption = NO`
- `NSSupportsLiveActivities = YES`
- The 1024×1024 app icon has no alpha.
- Category: Health & Fitness. Price: Free.
- The disclaimer appears in the app (first launch and About) and in the
  description.
- No network calls. No crash on an empty state, on a paste of garbage, or
  on 5,000 entries.
- Privacy policy and support pages live at `/docs` and are served by
  GitHub Pages.

## Tests

- `ContractionCore`: `swift test` covers the codec round-trip and lenient
  parsing, the merge cases (re-import, ±5–30 s offsets, back-to-back
  contractions, one incoming overlapping two existing, in-progress
  overlap, approximate tolerance, A→B→A round-trip, notes), the
  stats/interval math, the pattern boundaries, and `QuickLog`.
- The app builds for the simulator with no warnings in our code.
- Manual check on two phones: share through iMessage, paste, review,
  import, and undo. The Live Activity Stop button works from the Dynamic
  Island and the lock screen.

## Decisions log

- **Plain text instead of a file** (the user's call): it is readable,
  can be pasted into Notes or iMessage, and needs no document types.
  `PasteButton` avoids the permission prompt. Losing UUIDs is fine because
  matching is fuzzy, and round-trips match on time.
- **The merge never deletes.** "Use theirs" overwrites only the matched
  row, and the pre-import snapshot makes it undoable.
- **The App Group store** keeps the Live Activity intent consistent with
  the app no matter which process runs it.
- **Approximate is a flag, not a separate type.** It widens the matching
  allowance and steers the suggested conflict choice. Otherwise it behaves
  the same as any other entry.
