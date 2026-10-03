import Observation
import SwiftUI
import WaitListCore

/// The screens inside the popover.
enum Screen: Equatable {
    case list
    case add(editing: Item?)
    case settings
}

/// Which screen the popover shows. A shared object rather than view state so the menubar menu
/// ("Add Item…", "Settings…") and notification taps can switch screens too.
@Observable @MainActor
final class Router {
    var screen: Screen

    init(screen: Screen = .list) {
        self.screen = screen
    }

    func show(_ screen: Screen, animated: Bool = true) {
        guard screen != self.screen else { return }
        if animated {
            withAnimation(.snappy(duration: 0.25)) { self.screen = screen }
        } else {
            self.screen = screen
        }
    }
}

/// The popover content: one screen at a time, with a short slide when moving between them.
struct RootView: View {
    /// Fixed so the popover never resizes; snapshots may pass a taller size to review scrolled content.
    var size = StatusItemController.popoverSize
    /// Shows the list's undo toast for this decision on first appearance (snapshots).
    var initialDecision: RecentDecision?

    @Environment(Router.self) private var router
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack {
            switch router.screen {
            case .list:
                ListScreen(initialDecision: initialDecision)
                    .transition(.slideFade(from: .leading))
            case .add(let editing):
                AddItemScreen(editing: editing, defaultWaitDays: settings.defaultWaitDays)
                    .id(editing?.id)
                    .transition(.slideFade(from: .trailing))
            case .settings:
                SettingsScreen()
                    .transition(.slideFade(from: .trailing))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

extension AnyTransition {
    /// A short horizontal nudge plus fade: subtle, but shows direction.
    static func slideFade(from edge: HorizontalEdge) -> AnyTransition {
        .offset(x: edge == .leading ? -40 : 40).combined(with: .opacity)
    }
}

extension View {
    /// Injects everything the screens read from the environment.
    func waitListEnvironment(store: ItemStore, settings: AppSettings, services: AppServices,
                             router: Router) -> some View {
        environment(store)
            .environment(settings)
            .environment(services)
            .environment(router)
    }
}
