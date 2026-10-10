import AppKit

enum Tool: String, CaseIterable {
    case arrow
    case rectangle
    case ellipse
    case pen
    case line
    case text
    case highlighter
    case blur
    case number

    var title: String {
        switch self {
        case .arrow: return L("Arrow (A)")
        case .rectangle: return L("Rectangle (R)")
        case .ellipse: return L("Ellipse (E)")
        case .pen: return L("Pen (P)")
        case .line: return L("Line (L)")
        case .text: return L("Text (T)")
        case .highlighter: return L("Highlighter (H)")
        case .blur: return L("Blur (B)")
        case .number: return L("Number (N)")
        }
    }

    var symbolName: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .pen: return "pencil.tip"
        case .line: return "line.diagonal"
        case .text: return "textformat"
        case .highlighter: return "highlighter"
        case .blur: return "checkerboard.rectangle"
        case .number: return "1.circle"
        }
    }

    var shortcut: Character {
        switch self {
        case .arrow: return "a"
        case .rectangle: return "r"
        case .ellipse: return "e"
        case .pen: return "p"
        case .line: return "l"
        case .text: return "t"
        case .highlighter: return "h"
        case .blur: return "b"
        case .number: return "n"
        }
    }
}

enum StrokeWidth: Int, CaseIterable {
    case small = 0
    case medium = 1
    case large = 2

    var value: CGFloat {
        switch self {
        case .small: return 2
        case .medium: return 4
        case .large: return 8
        }
    }

    var title: String {
        switch self {
        case .small: return L("Thin")
        case .medium: return L("Medium")
        case .large: return L("Thick")
        }
    }
}

/// One drawn element. All geometry is in image points with a top-left origin.
struct Annotation: Identifiable {
    enum Kind {
        case arrow(CGPoint, CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case pen([CGPoint])
        case line(CGPoint, CGPoint)
        case text(String, CGPoint, CGFloat)
        case highlighter([CGPoint])
        case blur(CGRect)
        case number(Int, CGPoint)
    }

    let id: UUID
    var kind: Kind
    var color: NSColor
    var width: CGFloat

    init(kind: Kind, color: NSColor, width: CGFloat) {
        self.id = UUID()
        self.kind = kind
        self.color = color
        self.width = width
    }

    static func textFont(size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func textFontSize(for width: CGFloat) -> CGFloat {
        12 + width * 3
    }

    static func badgeRadius(for width: CGFloat) -> CGFloat {
        11 + width * 1.5
    }
}

extension CGRect {
    init(corner a: CGPoint, corner b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
