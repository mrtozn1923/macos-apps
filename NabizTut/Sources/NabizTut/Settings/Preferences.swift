import AppKit

@MainActor
final class Preferences {
    static let shared: Preferences = Preferences()

    private let defaults: UserDefaults = .standard

    var soundEnabled: Bool {
        get { defaults.object(forKey: "soundEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "soundEnabled") }
    }

    /// Panel background opacity, 0.3 … 1.0.
    var panelOpacity: Double {
        get { defaults.object(forKey: "panelOpacity") as? Double ?? 0.85 }
        set { defaults.set(min(1, max(0.3, newValue)), forKey: "panelOpacity") }
    }

    var panelVisible: Bool {
        get { defaults.object(forKey: "panelVisible") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "panelVisible") }
    }

    /// Saved panel frame for a given screen arrangement key.
    func panelFrame(for key: String) -> NSRect? {
        guard let string = defaults.string(forKey: "panelFrame.\(key)") else { return nil }
        let rect: NSRect = NSRectFromString(string)
        return rect.isEmpty ? nil : rect
    }

    func setPanelFrame(_ frame: NSRect, for key: String) {
        defaults.set(NSStringFromRect(frame), forKey: "panelFrame.\(key)")
    }
}
