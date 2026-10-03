import AppKit
import SwiftUI
import UserNotifications
import WaitListCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let dataLocation: DataLocation
    private let notifications = NotificationController()
    private let router = Router()

    private var settings: AppSettings?
    private var store: ItemStore?
    private var services: AppServices?
    private var statusItem: StatusItemController?
    private var refreshTimer: Timer?
    /// Fires just after the next waiting item becomes due, so the badge and list update on time.
    private var dueTimer: Timer?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(dataLocation: DataLocation) {
        self.dataLocation = dataLocation
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Must be set before didFinishLaunching returns, or a notification tap that launched the app is lost.
        UNUserNotificationCenter.current().delegate = notifications
        installMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A WAITLIST_DATA_FILE run keeps its settings (and @AppStorage) in a separate suite.
        let defaults = dataLocation.makeSettingsDefaults()
        let settings = AppSettings(defaults: defaults)
        let (store, notice) = Self.makeStore(location: dataLocation, settings: settings)
        let services = AppServices.live(dataFileURL: dataLocation.fileURL, notice: notice,
                                        notifications: notifications)
        let statusItem = StatusItemController(store: store, settings: settings, services: services, router: router,
                                              defaults: defaults)
        self.settings = settings
        self.store = store
        self.services = services
        self.statusItem = statusItem

        notifications.registerCategory()
        notifications.attach(store: store, settings: settings) { [weak self] in
            self?.openPopover()
        }
        store.onChange = { [weak self] in
            self?.storeDidChange()
        }
        // init never calls onChange, so do one pass now: schedules notifications and sets the badge.
        store.refresh()
        notifications.requestAuthorization()
        installObservers()
        startRefreshTimer()
    }

    /// Double-clicking the app in Finder while it runs opens the popover.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openPopover()
        return false
    }

    /// Opens the popover for a notification tap or a reopen: on the list, unless an Add/Edit form is open.
    func openPopover() {
        statusItem?.showPopover(screen: Self.screenToShowOnOpen(from: router.screen))
    }

    /// The screen to switch to when the app is brought up from outside (notification tap, reopen): the list,
    /// or nil to stay where the user is when an Add/Edit form is open, so a half-typed item is not thrown away.
    nonisolated static func screenToShowOnOpen(from current: Screen) -> Screen? {
        if case .add = current { return nil }
        return .list
    }

    // MARK: Private

    private func storeDidChange() {
        guard let store else { return }
        notifications.reschedule()
        statusItem?.setBadge(store.due.count)
        armDueTimer(for: store)
    }

    private func refreshNow() {
        store?.refresh()
    }

    /// One-shot timer for the earliest waiting item (+1 s), re-armed after every change.
    private func armDueTimer(for store: ItemStore) {
        dueTimer?.invalidate()
        dueTimer = nil
        guard let next = store.waiting.first?.decideAt else { return }
        let timer = Timer(fire: next.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNow() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        dueTimer = timer
    }

    /// The system time zone changed: decisions keep their local time of day (09:00 stays 09:00 here).
    private func timeZoneDidChange() {
        NSTimeZone.resetSystemTimeZone()
        guard let store, let settings else { return }
        store.refresh()
        store.retimeUndecided(to: settings.notificationTime)
    }

    /// Builds the store for the chosen data location. Returns an app-level notice to show, if any.
    private static func makeStore(location: DataLocation, settings: AppSettings) -> (ItemStore, String?) {
        switch location {
        case .standard(let url):
            return (ItemStore(persistence: FileItemPersistence(fileURL: url), settings: settings), nil)
        case .override(let url):
            // Settings come from the debug suite here, so the real "already migrated" flag is never touched.
            let store = ItemStore(persistence: FileItemPersistence(fileURL: url), settings: settings,
                                  legacyImport: { _, _ in .none })
            return (store, nil)
        case .unavailable(let reason):
            let store = withoutLegacyImport(settings) {
                ItemStore(persistence: InMemoryItemPersistence(), settings: settings, legacyImport: { _, _ in .none })
            }
            let notice = "WaitList can't open its data folder (\(reason)). "
                + "You can keep using it, but nothing you add will be kept after you quit."
            return (store, notice)
        }
    }

    /// Runs `body` with legacy import disabled and restores the "already migrated" flag afterwards,
    /// so an in-memory session never marks 1.x items as imported into the real data.
    private static func withoutLegacyImport(_ settings: AppSettings, _ body: () -> ItemStore) -> ItemStore {
        let wasMigrated = settings.hasMigratedLegacyItems
        let store = body()
        settings.hasMigratedLegacyItems = wasMigrated
        return store
    }

    /// Time moves on while the app sits in the menubar; refresh whenever it may have jumped.
    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let local = NotificationCenter.default
        let refreshing: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.didWakeNotification),
            (local, .NSCalendarDayChanged),
            (local, .NSSystemClockDidChange),
        ]
        for (center, name) in refreshing {
            observe(name, on: center) { $0.refreshNow() }
        }
        observe(.NSSystemTimeZoneDidChange, on: local) { $0.timeZoneDidChange() }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter,
                         _ action: @escaping @MainActor (AppDelegate) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    private func startRefreshTimer() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNow() }
        }
        timer.tolerance = 10
        // .common so it also fires while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// An accessory app has no visible menu bar, but text fields still need Edit menu key equivalents
    /// (⌘X/⌘C/⌘V/⌘A/⌘Z) to reach them, and ⌘Q should quit while the popover has focus.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "WaitList")
        appMenu.addItem(withTitle: "Quit WaitList", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }
}
