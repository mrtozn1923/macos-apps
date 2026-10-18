import AppKit
import SwiftUI

/// Makes the app a regular (Dock + Cmd-Tab) app while any of its windows is open.
@MainActor
enum ActivationPolicy {
    private static var openWindows: Int = 0

    static func windowOpened() {
        openWindows += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func windowClosed() {
        openWindows = max(0, openWindows - 1)
        if openWindows == 0 { NSApp.setActivationPolicy(.accessory) }
    }
}

@MainActor
final class DetailWindowController: NSWindowController, NSWindowDelegate {
    private static var open: [UUID: DetailWindowController] = [:]
    private let monitorID: UUID

    static func show(monitorID: UUID, controller: AppController) {
        if let existing = open[monitorID] {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window: NSWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
                                        styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                        backing: .buffered, defer: false)
        window.minSize = NSSize(width: 620, height: 520)
        window.isReleasedWhenClosed = false
        window.title = controller.state.monitors.first { $0.id == monitorID }?.displayName ?? "NabızTut"
        window.contentViewController = NSHostingController(rootView: DetailView(
            monitorID: monitorID, state: controller.state, history: controller.history,
            actions: DetailActions(
                checkNow: { controller.scheduler.checkNow(monitorID) },
                edit: { controller.openSettings?(.monitors(monitorID)) },
                setPaused: { controller.setPaused(monitorID, $0) }
            )))
        window.setContentSize(NSSize(width: 760, height: 640))
        let windowController: DetailWindowController = DetailWindowController(window: window, monitorID: monitorID)
        window.delegate = windowController
        open[monitorID] = windowController
        window.center()
        ActivationPolicy.windowOpened()
        windowController.showWindow(nil)
    }

    static func closeAll(for monitorID: UUID) {
        open[monitorID]?.window?.close()
    }

    private init(window: NSWindow, monitorID: UUID) {
        self.monitorID = monitorID
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        DetailWindowController.open[monitorID] = nil
        ActivationPolicy.windowClosed()
    }
}
