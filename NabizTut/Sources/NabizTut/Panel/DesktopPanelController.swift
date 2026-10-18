import AppKit
import SwiftUI

/// Borderless panel that lives on the desktop: above wallpaper and icons, below normal windows.
@MainActor
final class DesktopPanelController: NSObject, NSWindowDelegate {
    static let defaultWidth: CGFloat = 330

    private let controller: AppController
    private var panel: NSPanel?

    init(controller: AppController) {
        self.controller = controller
        super.init()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreFrame() }
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        if panel == nil { createPanel() }
        panel?.orderFront(nil)
        Preferences.shared.panelVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        Preferences.shared.panelVisible = false
        setEditing(false)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// Edit mode allows dragging and resizing; the panel is locked otherwise.
    func setEditing(_ editing: Bool) {
        controller.state.panelEditing = editing
        guard let panel else { return }
        if editing {
            panel.styleMask.insert(.resizable)
            // Lift above other windows while editing so it can be grabbed.
            panel.level = .floating
            panel.orderFrontRegardless()
        } else {
            panel.styleMask.remove(.resizable)
            panel.level = DesktopPanelController.desktopLevel
            saveFrame()
        }
    }

    private static var desktopLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    private func createPanel() {
        let panel: NSPanel = NSPanel(contentRect: defaultFrame(), styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        panel.level = DesktopPanelController.desktopLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Movable at all times through the header's drag area; background dragging stays off so rows remain clickable.
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = CGSize(width: 260, height: 120)
        panel.delegate = self

        let root: PanelView = PanelView(state: controller.state, actions: PanelActions(
            openDetail: { [weak self] id in self?.controller.openDetail?(id) },
            openSettings: { [weak self] in self?.controller.openSettings?(.monitors(nil)) },
            refreshAll: { [weak self] in self?.controller.refreshAll() },
            finishEditing: { [weak self] in self?.setEditing(false) }
        ))
        let hosting: NSHostingView<PanelView> = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        restoreFrame()
    }

    private func defaultFrame() -> NSRect {
        let visible: NSRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rows: Int = max(2, min(10, controller.state.monitors.count))
        let height: CGFloat = 56 + CGFloat(rows) * 46 + 12
        return NSRect(x: visible.maxX - DesktopPanelController.defaultWidth - 24,
                      y: visible.maxY - height - 24, width: DesktopPanelController.defaultWidth, height: height)
    }

    /// Frames are remembered per screen arrangement, so docking/undocking a display restores the right spot.
    private var screenKey: String {
        NSScreen.screens.map { NSStringFromRect($0.frame) }.joined(separator: "|")
    }

    private func restoreFrame() {
        guard let panel else { return }
        var frame: NSRect = Preferences.shared.panelFrame(for: screenKey) ?? defaultFrame()
        // Keep it on screen if the arrangement changed.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) { frame = defaultFrame() }
        panel.setFrame(frame, display: true)
    }

    private func saveFrame() {
        guard let panel else { return }
        Preferences.shared.setPanelFrame(panel.frame, for: screenKey)
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { saveFrame() }
}
