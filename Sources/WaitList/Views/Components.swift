import AppKit
import SwiftUI
import WaitListCore

// MARK: Colors

extension Color {
    /// Green for "skipped" and money saved. Darker in light mode so small text stays readable.
    static let saved = Color(nsColor: NSColor(name: "WaitList.saved") { appearance in
        appearance.isDark ? .systemGreen : NSColor(srgbRed: 0.10, green: 0.52, blue: 0.22, alpha: 1)
    })

    /// Blue for "bought" and money spent.
    static let spent = Color(nsColor: NSColor(name: "WaitList.spent") { appearance in
        appearance.isDark ? .systemBlue : NSColor(srgbRed: 0.05, green: 0.40, blue: 0.85, alpha: 1)
    })

    /// Background of grouped cards: a faint wash, matching grouped Form sections in both appearances.
    static let card = Color.primary.opacity(0.025)
    /// Hairline around cards.
    static let cardBorder = Color(nsColor: .separatorColor)
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

// MARK: Layout helpers

extension View {
    /// A rounded card; `tint` gives a faint colored fill instead of the neutral one.
    func card(tint: Color? = nil, cornerRadius: CGFloat = 10) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background {
            if let tint {
                shape.fill(tint.opacity(0.07))
            } else {
                shape.fill(Color.card)
            }
        }
        .overlay {
            shape.strokeBorder(tint.map { $0.opacity(0.25) } ?? Color.cardBorder, lineWidth: 1)
        }
    }
}

/// Quiet small-caps title for a list section, with an optional count.
struct SectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.callout.weight(.semibold).smallCaps())
                .foregroundStyle(.secondary)
            if let count {
                Text("\(count)")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Title bar for the Add/Edit and Settings screens: a back button on the left, centered title.
struct ScreenHeader: View {
    let title: String
    let backTitle: String
    var showsChevron = true
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        if showsChevron {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                        }
                        Text(backTitle)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
                .keyboardShortcut(.cancelAction)
                .help(showsChevron ? "Back (Esc)" : "Cancel (Esc)")
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }
}

/// Warning shown for store errors and app notices. Long messages collapse to three lines.
struct NoticeBanner: View {
    let message: String
    let onDismiss: () -> Void
    @State private var expanded = false

    private var isLong: Bool { message.count > 150 }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(message)
                    .font(.caption)
                    .lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(message)
                if isLong {
                    Button(expanded ? "Show less" : "Show more") {
                        withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(10)
        .card(tint: .orange, cornerRadius: 8)
    }
}

/// Small link icon that opens the item's URL in the browser.
struct LinkButton: View {
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            Image(systemName: "link")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(url.absoluteString)
        .accessibilityLabel("Open link")
    }
}

/// "Skipped" / "Bought" capsule for history rows.
struct OutcomeBadge: View {
    let outcome: Outcome

    private var color: Color { outcome == .skipped ? .saved : .spent }

    var body: some View {
        Text(outcome == .skipped ? "Skipped" : "Bought")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
            .fixedSize()
    }
}

/// The `⋯` button that opens an item's action menu.
struct MoreMenu<Content: View>: View {
    let itemName: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel("More actions for \(itemName)")
    }
}

/// A label above a form control, with an optional validation message below.
struct FormField<Content: View>: View {
    let label: String
    var message: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            content()
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
        }
    }
}
