import AppKit

MainActor.assumeIsolated {
    let app: NSApplication = NSApplication.shared
    let delegate: AppDelegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
}
