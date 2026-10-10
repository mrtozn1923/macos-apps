import AppKit
import SwiftUI

/// Button that records the next key combination pressed and stores it for a capture mode.
struct HotkeyRecorder: NSViewRepresentable {
    let mode: CaptureMode
    let onChange: () -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button: RecorderButton = RecorderButton(mode: mode)
        button.onChange = onChange
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.refreshTitle()
    }
}

@MainActor
final class RecorderButton: NSButton {
    private let mode: CaptureMode
    private var monitor: Any?
    var onChange: (() -> Void)?

    init(mode: CaptureMode) {
        self.mode = mode
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(toggleRecording)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshTitle() {
        guard monitor == nil else { return }
        title = Preferences.shared.hotkey(for: mode)?.displayString ?? L("No shortcut")
    }

    @objc private func toggleRecording() {
        if monitor != nil {
            stopRecording()
            return
        }
        title = L("Press keys…")
        HotkeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch Int(event.keyCode) {
            case 53: // Escape cancels
                self.stopRecording()
            case 51, 117: // Delete clears
                Preferences.shared.setHotkey(nil, for: self.mode)
                self.stopRecording()
            default:
                guard let combo = KeyCombo(event: event) else {
                    NSSound.beep()
                    return nil
                }
                Preferences.shared.setHotkey(combo, for: self.mode)
                self.stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotkeyManager.shared.registerAll()
        refreshTitle()
        onChange?()
    }
}
