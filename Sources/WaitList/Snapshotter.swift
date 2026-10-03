import AppKit
import SwiftUI
import WaitListCore

/// `--snapshot <dir>`: renders every screen with sample data in light and dark mode to
/// `<dir>/<name>-<light|dark>.png` at 2x. No notifications, no real data, no windows on screen.
@MainActor
enum Snapshotter {
    enum Scenario: String, CaseIterable {
        case listFull = "list-full"
        case listWaitingOnly = "list-waiting-only"
        case listHistory = "list-history"
        case listEmpty = "list-empty"
        case listError = "list-error"
        case listUndo = "list-undo"
        case add = "add"
        case addCustom = "add-custom"
        case edit = "edit"
        case settings = "settings"
        // Review aids, taller than the popover so content below the fold is visible.
        case listFullTall = "list-full-tall"
        case settingsTall = "settings-tall"

        var size: NSSize {
            switch self {
            case .listFullTall: return NSSize(width: 340, height: 1_180)
            case .settingsTall: return NSSize(width: 340, height: 1_000)
            default: return StatusItemController.popoverSize
            }
        }
    }

    private static let scale: CGFloat = 2

    static func run(into directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = SampleData.makeDefaults()
        defer { SampleData.discard(defaults) }

        for scenario in Scenario.allCases {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let url = directory.appendingPathComponent("\(scenario.rawValue)-\(suffix).png")
                try render(scenario, appearance: appearance, defaults: defaults, to: url)
                print(url.path)
            }
        }
    }

    private static func render(_ scenario: Scenario, appearance: NSAppearance.Name, defaults: UserDefaults,
                               to url: URL) throws {
        let calendar = Calendar.current
        let now = SampleData.referenceNow(calendar: calendar)
        // Every scenario starts from factory settings (default wait 14 days, etc.).
        SampleData.reset(defaults)
        let settings = AppSettings(defaults: defaults)
        defaults.set(scenario == .listHistory || scenario == .listFullTall, forKey: "historyExpanded")

        let store: ItemStore
        var screen = Screen.list
        var services = AppServices.preview(dataFileURL: sampleDataFileURL)
        var initialDecision: RecentDecision?
        switch scenario {
        case .listFull, .listFullTall, .add, .addCustom:
            store = SampleData.store(.full, settings: settings, now: now, calendar: calendar)
            if scenario == .add || scenario == .addCustom { screen = .add(editing: nil) }
            // A default that is not a preset opens the add screen on "Custom".
            if scenario == .addCustom { settings.defaultWaitDays = 21 }
        case .listUndo:
            // Just skipped the first due item: the toast offers undo.
            store = SampleData.store(.full, settings: settings, now: now, calendar: calendar)
            if let item = store.due.first {
                store.decide(item.id, .skipped)
                initialDecision = RecentDecision(itemID: item.id, name: item.name, price: item.price,
                                                 outcome: .skipped)
            }
        case .listWaitingOnly:
            store = SampleData.store(.waitingOnly, settings: settings, now: now, calendar: calendar)
        case .listHistory:
            store = SampleData.store(.historyOnly, settings: settings, now: now, calendar: calendar)
        case .listEmpty:
            store = SampleData.store(.empty, settings: settings, now: now, calendar: calendar)
        case .listError:
            store = SampleData.store(.few, settings: settings, now: now, calendar: calendar,
                                     failingSave: CocoaError(.fileWriteOutOfSpace))
            store.add(name: "Camera strap", price: 349, note: nil, waitDays: 14)
        case .edit:
            store = SampleData.store(.full, settings: settings, now: now, calendar: calendar)
            screen = .add(editing: store.waiting.last)
        case .settings, .settingsTall:
            store = SampleData.store(.full, settings: settings, now: now, calendar: calendar)
            screen = .settings
            services = AppServices.preview(dataFileURL: sampleDataFileURL, permission: .denied)
        }

        let router = Router(screen: screen)
        let size = scenario.size
        let root = RootView(size: size, initialDecision: initialDecision)
            .waitListEnvironment(store: store, settings: settings, services: services, router: router)
            .defaultAppStorage(defaults)
            .background(Color(nsColor: .windowBackgroundColor))

        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = SnapshotWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hostingView

        hostingView.layoutSubtreeIfNeeded()
        // Let SwiftUI settle: tasks, deferred layout and AppKit-backed controls.
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        hostingView.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw SnapshotError("could not allocate a bitmap")
        }
        rep.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw SnapshotError("could not encode \(url.lastPathComponent)")
        }
        try png.write(to: url, options: .atomic)
        window.contentView = nil
        window.close()
    }

    private static var sampleDataFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WaitList/items.json")
    }

    struct SnapshotError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}

/// Pretends to be key so controls draw in their active state (tinted prominent buttons, switches,
/// progress bars). The process is never activated, so the user's focus is not stolen.
private final class SnapshotWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    override var canBecomeKey: Bool { true }

    /// Undocumented: AppKit asks the window this to decide whether controls draw active.
    /// Snapshot-only; if a future macOS stops asking, snapshots just show inactive-looking controls.
    @objc func hasKeyAppearance() -> Bool { true }
}
