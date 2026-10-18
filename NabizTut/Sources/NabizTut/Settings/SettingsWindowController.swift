import AppKit
import SwiftUI

enum SettingsRoute {
    case general
    case monitors(UUID?)
    case newMonitor
}

/// Selection shared between the window controller and the SwiftUI view, so routes can change an open window.
@Observable
@MainActor
final class SettingsNavigation {
    enum Tab: Hashable { case monitors, general }

    var tab: Tab = .monitors
    var selectedID: UUID?
    /// Unsaved new monitor shown in the form.
    var newDraft: Monitor?
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?
    private let navigation: SettingsNavigation

    static func show(_ route: SettingsRoute, controller: AppController) {
        let instance: SettingsWindowController = shared ?? make(controller: controller)
        shared = instance
        instance.apply(route, controller: controller)
        if instance.window?.isVisible != true { ActivationPolicy.windowOpened() }
        instance.showWindow(nil)
        instance.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func make(controller: AppController) -> SettingsWindowController {
        let navigation: SettingsNavigation = SettingsNavigation()
        let window: NSWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                                        styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                        backing: .buffered, defer: false)
        window.title = L("NabızTut Settings")
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(controller: controller, navigation: navigation))
        window.setContentSize(NSSize(width: 860, height: 600))
        window.center()
        let instance: SettingsWindowController = SettingsWindowController(window: window, navigation: navigation)
        window.delegate = instance
        return instance
    }

    private init(window: NSWindow, navigation: SettingsNavigation) {
        self.navigation = navigation
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func apply(_ route: SettingsRoute, controller: AppController) {
        switch route {
        case .general:
            navigation.tab = .general
        case .monitors(let id):
            navigation.tab = .monitors
            navigation.newDraft = nil
            navigation.selectedID = id ?? navigation.selectedID ?? controller.state.monitors.first?.id
        case .newMonitor:
            navigation.tab = .monitors
            navigation.selectedID = nil
            navigation.newDraft = Monitor()
        }
    }

    func windowWillClose(_ notification: Notification) {
        ActivationPolicy.windowClosed()
    }
}

struct SettingsView: View {
    let controller: AppController
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            MonitorListView(controller: controller, navigation: navigation)
                .tabItem { Label(L("Monitors"), systemImage: "waveform.path.ecg") }
                .tag(SettingsNavigation.Tab.monitors)
            GeneralSettingsView(controller: controller)
                .tabItem { Label(L("General"), systemImage: "gearshape") }
                .tag(SettingsNavigation.Tab.general)
        }
        .padding(12)
    }
}
