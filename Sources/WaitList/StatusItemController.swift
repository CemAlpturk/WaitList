import AppKit
import SwiftUI
import WaitListCore

/// The menubar icon: left click toggles the popover, right click (or control-click) shows a menu.
@MainActor
final class StatusItemController: NSObject {
    nonisolated static let popoverSize = NSSize(width: 340, height: 520)

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: ItemStore
    private let router: Router
    private lazy var menu: NSMenu = makeMenu()

    init(store: ItemStore, settings: AppSettings, services: AppServices, router: Router) {
        self.store = store
        self.router = router
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.makeIcon()
            button.imagePosition = .imageOnly
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        setBadge(0)

        let root = RootView()
            .waitListEnvironment(store: store, settings: settings, services: services, router: router)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.contentSize = Self.popoverSize
        popover.behavior = .transient
        popover.animates = true
    }

    /// Shows the number of items ready to decide next to the icon (nothing when zero).
    func setBadge(_ count: Int) {
        guard let button = statusItem.button else { return }
        if count > 0 {
            button.title = "\(count)"
            button.imagePosition = .imageLeading
            button.toolTip = count == 1 ? "WaitList: 1 item ready to decide" : "WaitList: \(count) items ready to decide"
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "WaitList"
        }
        button.setAccessibilityLabel(button.toolTip)
    }

    /// Opens the popover (switching to `screen` if given) and gives it keyboard focus.
    func showPopover(screen: Screen? = nil) {
        if let screen {
            router.show(screen, animated: popover.isShown)
        }
        store.refresh()
        guard let button = statusItem.button else { return }
        // An accessory app is not active by default; without this, text fields do not get keystrokes.
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        popover.performClose(nil)
    }

    // MARK: Clicks

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)
        if isSecondary {
            showMenu()
        } else if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showMenu() {
        closePopover()
        // Attaching the menu only for this click keeps left click free for the popover
        // and gives the native menubar highlight and positioning.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Open WaitList", #selector(openFromMenu)))
        menu.addItem(item("Add Item…", #selector(addFromMenu)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(settingsFromMenu)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit WaitList", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // Deferred so the menu has finished closing before the popover is anchored to the button.
    @objc private func openFromMenu() {
        Task { @MainActor in self.showPopover() }
    }

    @objc private func addFromMenu() {
        Task { @MainActor in self.showPopover(screen: .add(editing: nil)) }
    }

    @objc private func settingsFromMenu() {
        Task { @MainActor in self.showPopover(screen: .settings) }
    }

    // MARK: Icon

    /// The template glyph from the bundle, or the `hourglass` symbol if it is missing.
    private static func makeIcon() -> NSImage? {
        if let image = Bundle.main.image(forResource: "MenuBarIcon") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            image.accessibilityDescription = "WaitList"
            return image
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbol = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "WaitList")?
            .withSymbolConfiguration(configuration)
        symbol?.isTemplate = true
        return symbol
    }
}
