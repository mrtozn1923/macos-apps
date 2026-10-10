import AppKit

@MainActor
enum Permissions {
    /// Returns true when Screen Recording is granted; otherwise explains how to grant it.
    static func ensureScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        // Triggers the system prompt the first time and registers TıkKare in the privacy list.
        if CGRequestScreenCaptureAccess() { return true }

        let alert: NSAlert = NSAlert()
        alert.messageText = L("Screen recording permission required")
        alert.informativeText = L("To take screenshots, allow TıkKare in System Settings › Privacy & Security › Screen & System Audio Recording. You may need to restart TıkKare after granting permission.")
        alert.addButton(withTitle: L("Open Settings"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }
}
