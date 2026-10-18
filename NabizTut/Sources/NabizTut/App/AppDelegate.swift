import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller: AppController = AppController()
    private var panel: DesktopPanelController?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        controller.openDetail = { [weak self] id in
            guard let self else { return }
            DetailWindowController.show(monitorID: id, controller: self.controller)
        }
        controller.openSettings = { [weak self] route in
            guard let self else { return }
            SettingsWindowController.show(route, controller: self.controller)
        }

        let panel: DesktopPanelController = DesktopPanelController(controller: controller)
        self.panel = panel
        menuBar = MenuBarController(controller: controller, panel: panel)

        controller.start()
        if Preferences.shared.panelVisible { panel.show() }
        // First launch: nothing to monitor yet, so open the form right away.
        if controller.state.monitors.isEmpty {
            controller.openSettings?(.newMonitor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
