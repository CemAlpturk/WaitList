import SwiftUI
import WaitListCore

/// What a row can ask the list to do. The list owns confirmations and the undo toast.
struct ItemActions {
    var decide: (Item, Outcome) -> Void
    var extend: (Item) -> Void
    var edit: (Item) -> Void
    /// Asks for confirmation first if the item is undecided.
    var delete: (Item) -> Void
    var undo: (Item) -> Void
}

/// Menu items for an undecided item, shared by the `⋯` menu and the context menu.
struct UndecidedItemMenu: View {
    let item: Item
    let actions: ItemActions
    var includesDecide = true

    var body: some View {
        if includesDecide {
            Menu("Decide now") {
                Button("Skip it") { actions.decide(item, .skipped) }
                Button("Bought it") { actions.decide(item, .bought) }
            }
        }
        Button("Wait \(NotificationPlan.extendDays) more days") { actions.extend(item) }
        Divider()
        Button("Edit…") { actions.edit(item) }
        Button("Delete…", role: .destructive) { actions.delete(item) }
    }
}

// MARK: Ready to decide

/// A due item: what it is, how long it waited, and the two decision buttons.
struct DueRow: View {
    let item: Item
    let actions: ItemActions
    @Environment(ItemStore.self) private var store
    @Environment(AppSettings.self) private var settings

    /// The note, when it is plain text (a link gets the link icon instead).
    private var plainNote: String? {
        guard item.noteURL == nil, let note = item.note, !note.isEmpty else { return nil }
        return note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(item.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                        if let url = item.noteURL {
                            LinkButton(url: url)
                        }
                    }
                    HStack(spacing: 0) {
                        if let price = item.price {
                            Text(Format.price(price, currencyCode: settings.currencyCode))
                                .foregroundStyle(.secondary)
                            Text("  ·  ").foregroundStyle(.tertiary)
                        }
                        Text(Format.waited(item, now: store.now, calendar: store.calendar))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .lineLimit(1)
                    if let plainNote {
                        Text(plainNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                            .lineLimit(2)
                            .help(plainNote)
                    }
                }
                Spacer(minLength: 4)
                MoreMenu(itemName: item.name) {
                    UndecidedItemMenu(item: item, actions: actions, includesDecide: false)
                }
            }
            HStack(spacing: 8) {
                Button {
                    actions.decide(item, .skipped)
                } label: {
                    Text("Skip it").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .help("You don't need it. It goes to your history as money not spent.")

                Button {
                    actions.decide(item, .bought)
                } label: {
                    Text("Bought it").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("You still wanted it and bought it.")
            }
        }
        .padding(10)
        .card(tint: .saved)
        .contextMenu {
            UndecidedItemMenu(item: item, actions: actions)
        }
    }
}

// MARK: Waiting

/// A waiting item: name, price, time left and a thin progress bar.
struct WaitingRow: View {
    let item: Item
    let actions: ItemActions
    @Environment(ItemStore.self) private var store
    @Environment(AppSettings.self) private var settings

    /// Days waited / (waited + left), so the bar fills up as the decision gets closer.
    private var progress: Double {
        let waited = item.daysWaited(at: store.now, calendar: store.calendar)
        let left = item.daysLeft(at: store.now, calendar: store.calendar)
        let total = waited + left
        return total == 0 ? 1 : Double(waited) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(item.note ?? item.name)
                if let url = item.noteURL {
                    LinkButton(url: url)
                }
                Spacer(minLength: 6)
                if let price = item.price {
                    Text(Format.price(price, currencyCode: settings.currencyCode))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                MoreMenu(itemName: item.name) {
                    UndecidedItemMenu(item: item, actions: actions)
                }
            }
            HStack(spacing: 10) {
                Text(Format.timeLeft(item, now: store.now, calendar: store.calendar))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .frame(width: 56)
                    .accessibilityLabel("Waiting progress")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            UndecidedItemMenu(item: item, actions: actions)
        }
    }
}

// MARK: History

/// A decided item with its outcome.
struct HistoryRow: View {
    let item: Item
    let actions: ItemActions
    @Environment(ItemStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let url = item.noteURL {
                        LinkButton(url: url)
                    }
                }
                if let decidedAt = item.decidedAt {
                    Text(Format.day(decidedAt, now: store.now, calendar: store.calendar))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            if let price = item.price {
                Text(Format.price(price, currencyCode: settings.currencyCode))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let outcome = item.outcome {
                OutcomeBadge(outcome: outcome)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .help(item.note ?? item.name)
        .contextMenu {
            Button("Undo decision") { actions.undo(item) }
            Divider()
            Button("Delete", role: .destructive) { actions.delete(item) }
        }
    }
}
