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

    /// Background of grouped cards: a faint system fill that stays visible in both appearances.
    static let card = Color(nsColor: .quaternarySystemFill)
    /// Hairline around cards.
    static let cardBorder = Color(nsColor: .separatorColor)
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

// MARK: Wait presets

/// The waiting periods offered as one-click choices (Add screen, Settings › Default wait).
enum WaitPresets {
    static let days = [7, 14, 30, 90]
}

// MARK: Layout helpers

extension View {
    /// A rounded card; `tint` gives a faint colored fill (`tintOpacity`) instead of the neutral one.
    func card(tint: Color? = nil, tintOpacity: Double = 0.07, cornerRadius: CGFloat = 10) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background {
            if let tint {
                shape.fill(tint.opacity(tintOpacity))
            } else {
                shape.fill(Color.card)
            }
        }
        .overlay {
            shape.strokeBorder(tint.map { $0.opacity(0.25) } ?? Color.cardBorder, lineWidth: 1)
        }
    }
}

/// Quiet title for a list section, with an optional count.
struct SectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if let count {
                Text("\(count)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Title bar for the Add/Edit and Settings screens: centered title, and a "‹ Back" button (Esc)
/// on the left when `onBack` is set.
struct ScreenHeader: View {
    let title: String
    var onBack: (() -> Void)?

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let onBack {
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                            Text("Back")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                    .keyboardShortcut(.cancelAction)
                    .help("Back (Esc)")
                    Spacer()
                }
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
                .frame(width: 20, height: 20)
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
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .frame(minWidth: 56)
            .background(Capsule().fill(color.opacity(0.10)))
            .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
            .fixedSize()
    }
}

/// Thin neutral bar for how much of the wait is over. Drawn rather than a tinted `ProgressView`:
/// the AppKit bar renders a gray tint near-black in light mode and track-colored in dark mode.
struct WaitProgressBar: View {
    /// 0...1.
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            let fraction = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if fraction > 0 {
                    Capsule().fill(.secondary)
                        .frame(width: max(geometry.size.height, geometry.size.width * fraction))
                }
            }
        }
        .frame(height: 4)
    }
}

/// The `⋯` button that opens an item's action menu. The glyph sits at the trailing edge of a
/// larger hit area, so it lines up with prices and controls below it.
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
                .frame(width: 28, height: 22, alignment: .trailing)
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

// MARK: Multi-line text field

extension Color {
    /// Fill of a rounded-border text field: white in light mode, a light wash in dark mode.
    fileprivate static let fieldBackground = Color(nsColor: NSColor(name: "WaitList.fieldBackground") { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.10) : .textBackgroundColor
    })
    /// Hairline around a rounded-border text field.
    fileprivate static let fieldBorder = Color(nsColor: NSColor(name: "WaitList.fieldBorder") { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0, alpha: 0.18)
    })
}

extension View {
    /// The rounded-border look for a `TextField(axis: .vertical)`. The system `.roundedBorder` style stays
    /// one line tall on macOS, wrapping text out of sight; this one grows with the field's line limit.
    func multilineFieldStyle(isFocused: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return textFieldStyle(.plain)
            .padding(.horizontal, 11)
            .padding(.vertical, 3)
            .frame(minHeight: 22)
            .background(shape.fill(Color.fieldBackground))
            .overlay(shape.strokeBorder(Color.fieldBorder, lineWidth: 1))
            .overlay {
                if isFocused {
                    shape.inset(by: -3)
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                }
            }
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
