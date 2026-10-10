import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onCapture: (CaptureMode) -> Void
    private let onSettings: () -> Void

    init(onCapture: @escaping (CaptureMode) -> Void, onSettings: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onSettings = onSettings
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "TıkKare")
        rebuild()
    }

    func rebuild() {
        let menu: NSMenu = NSMenu()
        menu.delegate = self
        for mode in CaptureMode.allCases {
            let item: NSMenuItem = NSMenuItem(title: mode.title, action: #selector(capture(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            if let combo = Preferences.shared.hotkey(for: mode) {
                let (key, flags): (String, NSEvent.ModifierFlags) = combo.menuKeyEquivalent
                item.keyEquivalent = key
                item.keyEquivalentModifierMask = flags
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let folder: NSMenuItem = NSMenuItem(title: L("Open Save Folder"), action: #selector(openFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)

        let settings: NSMenuItem = NSMenuItem(title: L("Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Quit TıkKare"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild()
    }

    @objc private func capture(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = CaptureMode(rawValue: raw) else { return }
        onCapture(mode)
    }

    @objc private func openFolder() {
        let folder: URL = Preferences.shared.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func showSettings() {
        onSettings()
    }
}
