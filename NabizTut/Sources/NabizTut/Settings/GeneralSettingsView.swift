import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    let controller: AppController

    @State private var opacity: Double = Preferences.shared.panelOpacity
    @State private var sound: Bool = Preferences.shared.soundEnabled
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var notificationsAllowed: Bool = true

    var body: some View {
        Form {
            Section(L("Desktop panel")) {
                LabeledContent(L("Opacity")) {
                    Slider(value: $opacity, in: 0.3...1)
                        .frame(maxWidth: 240)
                        .onChange(of: opacity) { _, value in
                            Preferences.shared.panelOpacity = value
                            controller.state.panelOpacity = value
                        }
                }
                Text(L("Drag the panel by its top bar to move it. To resize, choose “Resize panel…” from the menu bar icon."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Alerts")) {
                Toggle(L("Play a sound when a site goes down"), isOn: $sound)
                    .onChange(of: sound) { _, value in Preferences.shared.soundEnabled = value }
                if !notificationsAllowed {
                    HStack {
                        Label(L("Notifications are turned off for NabızTut."), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(L("Open System Settings")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
            Section(L("General")) {
                Toggle(L("Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in setLaunchAtLogin(value) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                LabeledContent(L("Data folder")) {
                    Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.monitorsFile]) }
                }
            }
        }
        .formStyle(.grouped)
        .task { notificationsAllowed = await controller.notifier.refreshAuthorization() }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = L("Could not change: %@", error.localizedDescription)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
