import AppKit

/// Entry point. We drive the AppKit lifecycle directly instead of a SwiftUI `App`
/// because a menubar popover needs programmatic control (open from a notification,
/// badge the status item) that `MenuBarExtra` does not expose.
@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menubar only, no Dock icon
        app.run()
    }
}
