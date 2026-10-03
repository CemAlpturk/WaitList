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
        let settings = AppSettings()
        let (store, notice) = Self.makeStore(location: dataLocation, settings: settings)
        let services = AppServices.live(dataFileURL: dataLocation.fileURL, notice: notice,
                                        notifications: notifications)
        let statusItem = StatusItemController(store: store, settings: settings, services: services, router: router)
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

    /// Opens the popover on the list (used by notification taps).
    func openPopover(screen: Screen = .list) {
        statusItem?.showPopover(screen: screen)
    }

    // MARK: Private

    private func storeDidChange() {
        guard let store else { return }
        notifications.reschedule(store: store)
        statusItem?.setBadge(store.due.count)
    }

    private func refreshNow() {
        store?.refresh()
    }

    /// Builds the store for the chosen data location. Returns an app-level notice to show, if any.
    private static func makeStore(location: DataLocation, settings: AppSettings) -> (ItemStore, String?) {
        switch location {
        case .standard(let url):
            return (ItemStore(persistence: FileItemPersistence(fileURL: url), settings: settings), nil)
        case .override(let url):
            let store = withoutLegacyImport(settings) {
                ItemStore(persistence: FileItemPersistence(fileURL: url), settings: settings,
                          legacyItems: { _, _ in [] })
            }
            return (store, nil)
        case .unavailable(let reason):
            let store = withoutLegacyImport(settings) {
                ItemStore(persistence: InMemoryItemPersistence(), settings: settings, legacyItems: { _, _ in [] })
            }
            let notice = "WaitList can't open its data folder (\(reason)). "
                + "You can keep using it, but nothing you add will be kept after you quit."
            return (store, notice)
        }
    }

    /// Runs `body` with legacy import disabled and restores the "already migrated" flag afterwards,
    /// so a test file or an in-memory session never marks 1.x items as imported into the real data.
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
        let names: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.didWakeNotification),
            (local, .NSCalendarDayChanged),
            (local, .NSSystemClockDidChange),
            (local, .NSSystemTimeZoneDidChange),
        ]
        for (center, name) in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshNow() }
            }
            observers.append((center, token))
        }
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
