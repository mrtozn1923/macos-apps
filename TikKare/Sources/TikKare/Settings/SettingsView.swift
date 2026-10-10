import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var saveFolder: URL = Preferences.shared.saveFolder
    @State private var playSound: Bool = Preferences.shared.playSound
    @State private var copyOnSave: Bool = Preferences.shared.copyOnSave
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var failedModes: [CaptureMode] = []
    @State private var loginError: String?

    var onHotkeysChanged: () -> Void = {}

    var body: some View {
        Form {
            Section("Shortcuts") {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    LabeledContent(mode.title) {
                        VStack(alignment: .trailing, spacing: 2) {
                            HotkeyRecorder(mode: mode) {
                                failedModes = HotkeyManager.shared.registerAll()
                                onHotkeysChanged()
                            }
                            if failedModes.contains(mode) {
                                Text("In use by another app")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                Text("Click and press new keys to change. ⌫ clears the shortcut, Esc cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Saving") {
                LabeledContent("Folder") {
                    HStack {
                        Text(saveFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Change…", action: chooseFolder)
                        Button {
                            try? FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(saveFolder)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Show folder in Finder")
                    }
                }
                Toggle("Also copy to clipboard when saving", isOn: $copyOnSave)
                    .onChange(of: copyOnSave) { _, value in Preferences.shared.copyOnSave = value }
            }

            Section("General") {
                Toggle("Capture sound", isOn: $playSound)
                    .onChange(of: playSound) { _, value in Preferences.shared.playSound = value }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in setLaunchAtLogin(value) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            failedModes = HotkeyManager.shared.registerAll()
        }
    }

    private func chooseFolder() {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = saveFolder
        panel.prompt = L("Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Preferences.shared.saveFolder = url
        saveFolder = url
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = L("Could not change: %@", error.localizedDescription)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?

    static func show(onHotkeysChanged: @escaping () -> Void) {
        if shared == nil {
            let hosting: NSHostingController<SettingsView> = NSHostingController(rootView: SettingsView(onHotkeysChanged: onHotkeysChanged))
            let window: NSWindow = NSWindow(contentViewController: hosting)
            window.title = L("TıkKare Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            let controller: SettingsWindowController = SettingsWindowController(window: window)
            window.delegate = controller
            shared = controller
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        shared?.window?.center()
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.shared = nil
        if NSApp.windows.filter({ $0.isVisible && $0 !== window && $0.styleMask.contains(.titled) }).isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
