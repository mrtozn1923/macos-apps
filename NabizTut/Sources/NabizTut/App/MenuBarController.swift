import AppKit
import Observation

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: AppController
    private let panel: DesktopPanelController

    init(controller: AppController, panel: DesktopPanelController) {
        self.controller = controller
        self.panel = panel
        super.init()
        let menu: NSMenu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        observeState()
    }

    /// Re-tints the icon whenever the overall state changes.
    private func observeState() {
        withObservationTracking {
            updateIcon(controller.state.overall)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeState() }
        }
    }

    private func updateIcon(_ overall: OverallState) {
        let color: NSColor
        switch overall {
        case .allUp: color = .systemGreen
        case .warning: color = .systemYellow
        case .down: color = .systemRed
        case .offline, .empty: color = .secondaryLabelColor
        }
        let configuration: NSImage.SymbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image: NSImage? = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "NabızTut")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = overall == .offline || overall == .empty
        statusItem.button?.image = image
        statusItem.button?.toolTip = "NabızTut"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state: AppState = controller.state

        let header: NSMenuItem = NSMenuItem(title: summary(state), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if !state.monitors.isEmpty { menu.addItem(.separator()) }

        for monitor in state.sortedMonitors {
            let status: MonitorStatus = state.status(for: monitor.id)
            let effective: MonitorState = state.offline ? .unknown : state.effectiveState(monitor)
            let latency: String = effective == .down ? (status.reason ?? L("Down")) : DurationFormatter.latency(status.lastResult?.latencyMs)
            let item: NSMenuItem = NSMenuItem(title: "\(monitor.displayName)  —  \(latency)",
                                              action: #selector(openMonitor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = monitor.id
            item.image = MenuBarController.dot(effective)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        add(menu, L("Check now"), #selector(checkNow), "r")
        add(menu, panel.isVisible ? L("Hide panel") : L("Show panel"), #selector(togglePanel), "")
        let edit: NSMenuItem = add(menu, controller.state.panelEditing ? L("Finish editing panel") : L("Resize panel…"),
                                   #selector(editPanel), "")
        edit.isEnabled = true
        menu.addItem(.separator())
        add(menu, L("Add site…"), #selector(addSite), "n")
        add(menu, L("Settings…"), #selector(openSettings), ",")
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Quit NabızTut"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item: NSMenuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func summary(_ state: AppState) -> String {
        switch state.overall {
        case .offline: return L("Offline — checks paused")
        case .empty: return state.monitors.isEmpty ? L("No monitors yet") : L("All monitors paused")
        default: return L("%ld/%ld up", state.upCount, state.activeMonitors.count)
        }
    }

    private static func dot(_ state: MonitorState) -> NSImage {
        let color: NSColor
        switch state {
        case .up: color = .systemGreen
        case .warning: color = .systemYellow
        case .down: color = .systemRed
        case .paused, .unknown: color = .systemGray
        }
        return NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    @objc private func openMonitor(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        controller.openDetail?(id)
    }

    @objc private func checkNow() { controller.refreshAll() }
    @objc private func togglePanel() { panel.toggle() }

    @objc private func editPanel() {
        if !panel.isVisible { panel.show() }
        panel.setEditing(!controller.state.panelEditing)
    }

    @objc private func addSite() { controller.openSettings?(.newMonitor) }
    @objc private func openSettings() { controller.openSettings?(.monitors(nil)) }
}
