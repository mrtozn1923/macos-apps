import AppKit
import Carbon.HIToolbox

enum CaptureMode: String, CaseIterable, Codable {
    case area
    case fullScreen
    case scrolling
    case ocr

    var title: String {
        switch self {
        case .area: return L("Area / Window")
        case .fullScreen: return L("Full Screen")
        case .scrolling: return L("Scrolling Capture")
        case .ocr: return L("Capture Text (OCR)")
        }
    }

    var defaultHotkey: KeyCombo {
        let mods: UInt32 = UInt32(optionKey | shiftKey)
        switch self {
        case .area: return KeyCombo(keyCode: UInt32(kVK_ANSI_1), modifiers: mods)
        case .fullScreen: return KeyCombo(keyCode: UInt32(kVK_ANSI_2), modifiers: mods)
        case .scrolling: return KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: mods)
        case .ocr: return KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: mods)
        }
    }
}

@MainActor
final class Preferences {
    static let shared: Preferences = Preferences()

    private let defaults: UserDefaults = .standard

    private enum Key {
        static let saveFolder = "saveFolder"
        static let playSound = "playSound"
        static let copyOnSave = "copyOnSave"
        static let lastColor = "lastColor"
        static let lastWidth = "lastWidth"
        static func hotkey(_ mode: CaptureMode) -> String { "hotkey.\(mode.rawValue)" }
    }

    var saveFolder: URL {
        get {
            if let path = defaults.string(forKey: Key.saveFolder) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures/Screenshots", isDirectory: true)
        }
        set { defaults.set(newValue.path, forKey: Key.saveFolder) }
    }

    var playSound: Bool {
        get { defaults.object(forKey: Key.playSound) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.playSound) }
    }

    var copyOnSave: Bool {
        get { defaults.object(forKey: Key.copyOnSave) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.copyOnSave) }
    }

    var lastColorIndex: Int {
        get { defaults.object(forKey: Key.lastColor) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: Key.lastColor) }
    }

    var lastWidth: StrokeWidth {
        get { StrokeWidth(rawValue: defaults.integer(forKey: Key.lastWidth)) ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: Key.lastWidth) }
    }

    func hotkey(for mode: CaptureMode) -> KeyCombo? {
        let key: String = Key.hotkey(mode)
        guard let data = defaults.data(forKey: key) else { return mode.defaultHotkey }
        // Empty data means the user cleared the shortcut.
        if data.isEmpty { return nil }
        return (try? JSONDecoder().decode(KeyCombo.self, from: data)) ?? mode.defaultHotkey
    }

    func setHotkey(_ combo: KeyCombo?, for mode: CaptureMode) {
        let key: String = Key.hotkey(mode)
        if let combo, let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: key)
        } else {
            defaults.set(Data(), forKey: key)
        }
    }
}
