import SwiftUI
import WaitListCore

/// The main screen: items ready to decide, items waiting, and the history.
struct ListScreen: View {
    @Environment(ItemStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router
    @AppStorage("historyExpanded") private var historyExpanded = false

    @State private var pendingDelete: Item?
    @State private var confirmingClearHistory = false
    @State private var recentDecision: RecentDecision?

    /// `initialDecision` shows the undo toast right away (snapshots).
    init(initialDecision: RecentDecision? = nil) {
        _recentDecision = State(initialValue: initialDecision)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            banners
            if store.items.isEmpty {
                emptyState
            } else {
                content
                Divider()
                footer
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { item in
            Button("Delete", role: .destructive) { delete(item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            if item.isDecided {
                Text("It's removed from your history and your saved and spent totals. This can't be undone.")
            } else {
                Text("You haven't decided on it yet. This can't be undone.")
            }
        }
        .confirmationDialog("Clear History?", isPresented: $confirmingClearHistory, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                withAnimation(.snappy) { store.clearHistory() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes ^[\(store.history.count) decided item](inflect: true). Your saved and spent totals start over.")
        }
    }

    // MARK: Header and banners

    private var header: some View {
        HStack(spacing: 4) {
            Text("WaitList")
                .font(.headline)
            Spacer()
            Button {
                router.show(.settings)
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 14, weight: .medium))
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 44)
    }

    @ViewBuilder
    private var banners: some View {
        let messages = [services.notice, store.lastError?.message].compactMap { $0 }
        if !messages.isEmpty {
            VStack(spacing: 6) {
                if let notice = services.notice {
                    NoticeBanner(message: notice) { services.notice = nil }
                }
                if let error = store.lastError {
                    NoticeBanner(message: error.message) { store.clearError() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                let due = store.due
                let waiting = store.waiting
                if !due.isEmpty {
                    section("Ready to decide", count: due.count) {
                        VStack(spacing: 8) {
                            ForEach(due) { item in
                                DueRow(item: item, actions: actions)
                            }
                        }
                    }
                }
                if !waiting.isEmpty {
                    section("Waiting", count: waiting.count) {
                        VStack(spacing: 0) {
                            ForEach(Array(waiting.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider().padding(.horizontal, 10) }
                                WaitingRow(item: item, actions: actions)
                            }
                        }
                        .card()
                    }
                }
                if due.isEmpty && waiting.isEmpty {
                    allDecided
                }
                if !store.history.isEmpty {
                    history
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 14)
        }
        .overlay(alignment: .bottom) {
            if let recentDecision {
                DecisionToast(decision: recentDecision) {
                    undo(recentDecision)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: recentDecision.id) {
                    AccessibilityNotification.Announcement(recentDecision.announcement(currencyCode: settings.currencyCode))
                        .post()
                    try? await Task.sleep(for: .seconds(6))
                    guard !Task.isCancelled else { return }
                    withAnimation(.snappy) { self.recentDecision = nil }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, count: Int,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader(title: title, count: count)
                .padding(.leading, 4)
            content()
        }
    }

    /// Shown when there is history but nothing undecided.
    private var allDecided: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("All decided")
                    .font(.body.weight(.medium))
                Text(addPrompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .card()
    }

    private var history: some View {
        DisclosureGroup(isExpanded: $historyExpanded) {
            VStack(alignment: .trailing, spacing: 6) {
                VStack(spacing: 0) {
                    ForEach(Array(store.history.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.horizontal, 10) }
                        HistoryRow(item: item, actions: actions)
                    }
                }
                .card()
                Button("Clear History…") { confirmingClearHistory = true }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
            }
        } label: {
            HistorySummary()
        }
        .disclosureGroupStyle(SectionDisclosureStyle())
    }

    // MARK: Empty state and footer

    /// How WaitList works, in one line, for the empty and all-decided states.
    private var addPrompt: String {
        // A no-break space keeps "14 days" on one line.
        let days = Format.days(settings.defaultWaitDays).replacingOccurrences(of: " ", with: "\u{00A0}")
        return "Add something you're tempted to buy. In \(days), WaitList asks if you still want it."
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing waiting", systemImage: "hourglass")
        } description: {
            Text(addPrompt)
        } actions: {
            Button("Add Item", action: showAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("n", modifiers: .command)
                .help("Add Item (⌘N)")
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Button(action: showAdd) {
                Label("Add Item", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: .command)
            .help("Add Item (⌘N)")
            Spacer()
            let saved = store.totalSaved
            if saved > 0 {
                Text("Saved \(Format.price(saved, currencyCode: settings.currencyCode))")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.saved)
                    .lineLimit(1)
                    .help("What you didn't spend by skipping")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Actions

    private var actions: ItemActions {
        ItemActions(
            decide: decide,
            extend: { item in
                withAnimation(.snappy) { store.extend(item.id, byDays: NotificationPlan.extendDays) }
            },
            edit: { item in router.show(.add(editing: item)) },
            delete: { item in pendingDelete = item },
            undo: { item in
                withAnimation(.snappy) {
                    store.undoDecision(item.id)
                    if recentDecision?.itemID == item.id { recentDecision = nil }
                }
            })
    }

    private func showAdd() {
        router.show(.add(editing: nil))
    }

    private func decide(_ item: Item, _ outcome: Outcome) {
        withAnimation(.snappy) {
            store.decide(item.id, outcome)
            recentDecision = RecentDecision(itemID: item.id, name: item.name, price: item.price, outcome: outcome)
        }
    }

    private func undo(_ decision: RecentDecision) {
        withAnimation(.snappy) {
            store.undoDecision(decision.itemID)
            recentDecision = nil
        }
    }

    private func delete(_ item: Item) {
        withAnimation(.snappy) { store.delete(item.id) }
        if recentDecision?.itemID == item.id { recentDecision = nil }
    }
}

// MARK: - History summary

/// "Saved 1 340 kr · Spent 220 kr", or counts when nothing had a price.
private struct HistorySummary: View {
    @Environment(ItemStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 6) {
            SectionHeader(title: "History", count: store.history.count)
            Spacer(minLength: 8)
            summary
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private var summary: Text {
        let saved = store.totalSaved
        let spent = store.totalSpent
        let code = settings.currencyCode
        let separator = Text("  ·  ").foregroundStyle(.tertiary)

        if saved == 0 && spent == 0 {
            var parts: [String] = []
            if store.skippedCount > 0 { parts.append("\(store.skippedCount) skipped") }
            if store.boughtCount > 0 { parts.append("\(store.boughtCount) bought") }
            return Text(parts.joined(separator: " · ")).foregroundStyle(.secondary)
        }
        let savedText = Text("Saved \(Format.price(saved, currencyCode: code))")
            .fontWeight(.semibold)
            .foregroundStyle(Color.saved)
        let spentText = Text("Spent \(Format.price(spent, currencyCode: code))")
            .foregroundStyle(.secondary)
        if saved > 0 && spent > 0 {
            return Text("\(savedText)\(separator)\(spentText)")
        }
        return saved > 0 ? savedText : spentText
    }
}

/// Disclosure with the whole header clickable and the chevron after the title.
private struct SectionDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: 10)
                    configuration.label
                }
                .padding(.leading, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(configuration.isExpanded ? "Collapse history" : "Expand history")
            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
    }
}

// MARK: - Undo toast

/// The last decision made in the list, offered for undo for a few seconds.
struct RecentDecision: Equatable {
    let id = UUID()
    let itemID: UUID
    let name: String
    let price: Decimal?
    let outcome: Outcome

    /// "1 899 kr saved" for a skipped item with a price, otherwise nil.
    func savedText(currencyCode: String) -> String? {
        guard outcome == .skipped, let price, price > 0 else { return nil }
        return "\(Format.price(price, currencyCode: currencyCode)) saved"
    }

    /// What VoiceOver says when the toast appears.
    func announcement(currencyCode: String) -> String {
        let verb = outcome == .skipped ? "Skipped" : "Bought"
        let saved = savedText(currencyCode: currencyCode).map { ", \($0)" } ?? ""
        return "\(verb) \(name)\(saved). Undo with Command-Z."
    }
}

/// "Skipped “Mechanical keyboard”" over "1 899 kr saved", with Undo. Only the name truncates.
private struct DecisionToast: View {
    let decision: RecentDecision
    let onUndo: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: decision.outcome == .skipped ? "checkmark.circle.fill" : "bag.fill")
                .foregroundStyle(decision.outcome == .skipped ? Color.saved : Color.spent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                // The quotes stay visible when a long name truncates.
                HStack(spacing: 0) {
                    Text(decision.outcome == .skipped ? "Skipped “" : "Bought “")
                        .fixedSize()
                    Text(decision.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("”")
                        .fixedSize()
                }
                .font(.callout)
                if let saved = decision.savedText(currencyCode: settings.currencyCode) {
                    Text(saved)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.saved)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            Button("Undo", action: onUndo)
                .buttonStyle(.borderless)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo (⌘Z)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.cardBorder.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}
