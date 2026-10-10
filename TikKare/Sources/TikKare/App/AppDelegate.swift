import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var overlay: OverlayController?
    private var scrollSession: ScrollCaptureController?
    private var isStarting: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBar = MenuBarController(
            onCapture: { [weak self] mode in
                // Let the menu close before the screen is frozen.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.startCapture(mode) }
            },
            onSettings: { [weak self] in
                SettingsWindowController.show { self?.menuBar?.rebuild() }
            }
        )

        HotkeyManager.shared.onTrigger = { [weak self] mode in self?.startCapture(mode) }
        HotkeyManager.shared.registerAll()

        // Trigger the Screen Recording prompt early so the first capture just works.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    func startCapture(_ mode: CaptureMode) {
        if let scrollSession {
            // Pressing any capture hotkey during a scrolling capture finishes it.
            scrollSession.finish()
            return
        }
        guard overlay == nil, !isStarting else { return }
        guard Permissions.ensureScreenRecording() else { return }
        isStarting = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.isStarting = false }
            let screens: [FrozenScreen]
            do {
                screens = try await ScreenCapturer.captureAllScreens()
            } catch {
                Exporter.showError(error)
                return
            }
            guard !screens.isEmpty else { return }
            self.presentOverlay(mode: mode, screens: screens)
        }
    }

    private func presentOverlay(mode: CaptureMode, screens: [FrozenScreen]) {
        let purpose: OverlayController.Purpose
        switch mode {
        case .area:
            purpose = .annotate
        case .fullScreen:
            purpose = .fullScreen
        case .ocr:
            purpose = .selectRegion { selection in
                guard let image = selection.image else { return }
                Task { await AppDelegate.recognizeText(in: image) }
            }
        case .scrolling:
            purpose = .selectRegion { [weak self] selection in
                self?.startScrolling(selection)
            }
        }
        let controller: OverlayController = OverlayController(purpose: purpose, frozenScreens: screens) { [weak self] in
            self?.overlay = nil
        }
        overlay = controller
        controller.show()
    }

    private func startScrolling(_ selection: RegionSelection) {
        let session: ScrollCaptureController = ScrollCaptureController(selection: selection) { [weak self] in
            self?.scrollSession = nil
        }
        scrollSession = session
        // Wait for the overlay to disappear so the first frame shows the live content.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { session.start() }
    }

    private static func recognizeText(in image: CGImage) async {
        do {
            let text: String = try await TextRecognizer.recognize(image)
            guard !text.isEmpty else {
                HUD.show(L("No text found"), symbol: "text.magnifyingglass")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            let preview: String = text.replacingOccurrences(of: "\n", with: " ")
            HUD.show(L("Text copied: %@", String(preview.prefix(60))), symbol: "text.viewfinder")
        } catch {
            Exporter.showError(error)
        }
    }
}
