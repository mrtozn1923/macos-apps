import AppKit

/// Current tool, color and stroke width. Shared by the toolbar and canvas, and carried into the editor window.
@MainActor
final class ToolState {
    static let presetColors: [NSColor] = [
        NSColor(srgbRed: 0.96, green: 0.23, blue: 0.21, alpha: 1), // red
        NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1), // orange
        NSColor(srgbRed: 1.00, green: 0.84, blue: 0.04, alpha: 1), // yellow
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1), // green
        NSColor(srgbRed: 0.00, green: 0.48, blue: 1.00, alpha: 1), // blue
        NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1), // purple
        NSColor(srgbRed: 0.08, green: 0.08, blue: 0.08, alpha: 1), // black
        NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1), // white
    ]

    static var presetColorNames: [String] {
        ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Black", "White"].map { L($0) }
    }

    var tool: Tool = .arrow { didSet { notify() } }

    var color: NSColor { didSet { notify() } }

    var width: StrokeWidth {
        didSet {
            Preferences.shared.lastWidth = width
            notify()
        }
    }

    private var observers: [UUID: () -> Void] = [:]

    init() {
        let index: Int = Preferences.shared.lastColorIndex
        color = ToolState.presetColors[min(max(index, 0), ToolState.presetColors.count - 1)]
        width = Preferences.shared.lastWidth
    }

    func selectPreset(_ index: Int) {
        guard ToolState.presetColors.indices.contains(index) else { return }
        Preferences.shared.lastColorIndex = index
        color = ToolState.presetColors[index]
    }

    @discardableResult
    func observe(_ handler: @escaping () -> Void) -> UUID {
        let id: UUID = UUID()
        observers[id] = handler
        return id
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func notify() {
        for handler in observers.values { handler() }
    }
}
