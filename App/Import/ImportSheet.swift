import SwiftUI
import ContractionCore

/// Step 1: paste (or open a file) and see what was recognized.
struct ImportSheet: View {
    /// Prefilled text from an opened .txt file; jumps to Review when it
    /// contains at least one entry.
    var initialText: String?

    @Environment(ContractionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var parsed = ParseResult(records: [], rejectedLines: [])
    /// The text `parsed` came from, so each change is parsed only once.
    @State private var parsedText = ""
    @State private var plan: ImportPlan?
    @State private var showReview = false
    @State private var didLoadInitial = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Paste a log shared from Contraction Traction on another phone. You'll review everything before it's added.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        PasteButton(payloadType: String.self) { strings in
                            let pasted = strings.joined(separator: "\n")
                            Task { @MainActor in text = pasted }
                        }
                        .buttonBorderShape(.capsule)
                        .labelStyle(.titleAndIcon)
                        Spacer()
                        if !text.isEmpty {
                            Button("Clear", role: .destructive) { text = "" }
                                .font(.subheadline.weight(.medium))
                        }
                    }

                    TextEditor(text: $text)
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 220)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("2026-10-18 2:10:03 PM · 58s\n2026-10-18 2:15:40 PM · ~1m 05s")
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityLabel("Log text")

                    status

                    if !parsed.rejectedLines.isEmpty {
                        DisclosureGroup("Skipped lines") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(parsed.rejectedLines.prefix(50).enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                if parsed.rejectedLines.count > 50 {
                                    Text("and \(parsed.rejectedLines.count - 50) more")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button(action: review) {
                    Text("Continue")
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(parsed.records.isEmpty)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showReview) {
                if let plan {
                    ImportReviewView(plan: plan) { dismiss() }
                }
            }
            .task(id: text) {
                // Debounce typing. Continue parses right away if this hasn't yet.
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                parseIfNeeded()
            }
            .onAppear(perform: loadInitial)
        }
    }

    @ViewBuilder
    private var status: some View {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyView()
        } else if parsed.records.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("No contractions recognized", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
                Text("Lines need to start with a date and time, then a duration, like 2026-10-18 14:10 | ~1m. Everything else is ignored.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            let skipped = parsed.rejectedLines.count
            Label("\(parsed.records.count) recognized" + (skipped > 0 ? " · \(skipped) line\(skipped == 1 ? "" : "s") skipped" : ""),
                  systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.resting)
        }
    }

    private func loadInitial() {
        guard !didLoadInitial else { return }
        didLoadInitial = true
        guard let initialText else { return }
        text = initialText
        parseIfNeeded()
        if !parsed.records.isEmpty { review() }
    }

    private func parseIfNeeded() {
        guard parsedText != text else { return }
        parsed = LogText.parse(text)
        parsedText = text
    }

    private func review() {
        // In case the debounce hasn't caught up yet.
        parseIfNeeded()
        guard !parsed.records.isEmpty else { return }
        plan = Merge.plan(existing: store.records, incoming: parsed.records)
        showReview = true
    }
}
