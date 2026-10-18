import AppKit
import UserNotifications

/// Posts macOS notifications and plays the alert sound.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private(set) var authorized: Bool = false
    private let alertSound: NSSound? = NSSound(named: "Sosumi") ?? NSSound(named: "Basso")

    func requestAuthorization() {
        let center: UNUserNotificationCenter = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.authorized = granted }
        }
    }

    func refreshAuthorization() async -> Bool {
        let settings: UNNotificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        return authorized
    }

    func post(_ event: StatusEvent, monitor: Monitor) {
        guard monitor.notify else { return }
        let content: UNMutableNotificationContent = UNMutableNotificationContent()
        switch event {
        case .wentDown(let reason):
            content.title = L("%@ is down", monitor.displayName)
            content.body = reason
            playAlert()
        case .recovered(let downtime):
            content.title = L("%@ is up again", monitor.displayName)
            content.body = L("Outage lasted %@", DurationFormatter.short(downtime))
        case .sslExpiring(let expiry):
            content.title = L("%@: SSL certificate expiring", monitor.displayName)
            content.body = L("Expires on %@", expiry.formatted(date: .long, time: .omitted))
        case .needsConfirmation:
            return
        }
        // Sound is played by the app (only for outages), so the notification itself stays silent.
        let request: UNNotificationRequest = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func playAlert() {
        guard Preferences.shared.soundEnabled else { return }
        alertSound?.stop()
        alertSound?.play()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
