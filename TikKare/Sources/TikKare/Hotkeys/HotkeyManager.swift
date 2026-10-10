import AppKit
import Carbon.HIToolbox

/// Registers system-wide hotkeys through Carbon (no Accessibility permission required).
@MainActor
final class HotkeyManager {
    static let shared: HotkeyManager = HotkeyManager()

    var onTrigger: ((CaptureMode) -> Void)?

    private var refs: [CaptureMode: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x4B535431 // 'KST1'

    private init() {
        installHandler()
    }

    /// Registers every mode from preferences. Returns modes that failed to register.
    @discardableResult
    func registerAll() -> [CaptureMode] {
        var failed: [CaptureMode] = []
        for mode in CaptureMode.allCases {
            if !register(Preferences.shared.hotkey(for: mode), for: mode) {
                failed.append(mode)
            }
        }
        return failed
    }

    @discardableResult
    func register(_ combo: KeyCombo?, for mode: CaptureMode) -> Bool {
        unregister(mode)
        guard let combo else { return true }
        let id: EventHotKeyID = EventHotKeyID(signature: signature, id: UInt32(index(of: mode)))
        var ref: EventHotKeyRef?
        let status: OSStatus = RegisterEventHotKey(combo.keyCode, combo.modifiers, id,
                                                   GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[mode] = ref
        return true
    }

    func unregister(_ mode: CaptureMode) {
        if let ref = refs.removeValue(forKey: mode) {
            UnregisterEventHotKey(ref)
        }
    }

    /// Temporarily disables all hotkeys (used while recording a new shortcut).
    func suspend() {
        for mode in CaptureMode.allCases { unregister(mode) }
    }

    private func index(of mode: CaptureMode) -> Int {
        CaptureMode.allCases.firstIndex(of: mode) ?? 0
    }

    fileprivate func handle(id: UInt32) {
        let modes: [CaptureMode] = CaptureMode.allCases
        guard Int(id) < modes.count else { return }
        onTrigger?(modes[Int(id)])
    }

    private func installHandler() {
        var spec: EventTypeSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                                eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID: EventHotKeyID = EventHotKeyID()
            let status: OSStatus = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                                     EventParamType(typeEventHotKeyID), nil,
                                                     MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id: UInt32 = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotkeyManager.shared.handle(id: id) }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &handlerRef)
    }
}
