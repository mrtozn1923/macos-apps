import AppKit

enum CanvasAction {
    case copy
    case save
    case saveAs
    case cancel
    case openEditor
    case zoomIn
    case zoomOut
    case zoomReset
}

/// Draws a document and turns mouse/keyboard input into annotations.
/// The view's coordinate space equals image points (flipped, top-left origin).
@MainActor
final class CanvasView: NSView, NSTextFieldDelegate {
    let document: AnnotationDocument
    let toolState: ToolState

    var onAction: ((CanvasAction) -> Void)?
    /// Called the first time an annotation is drawn (overlay hides resize handles).
    var onFirstEdit: (() -> Void)?

    private var dragStart: CGPoint?
    private var activeID: UUID?
    private var textField: NSTextField?
    private var editingTextID: UUID?
    private var editingTextOrigin: CGPoint = .zero
    private var editingFontSize: CGFloat = 16
    private var toolObserver: UUID?
    private var documentObserver: UUID?

    init(document: AnnotationDocument, toolState: ToolState) {
        self.document = document
        self.toolState = toolState
        super.init(frame: CGRect(origin: .zero, size: document.pointSize))
        documentObserver = document.observe { [weak self] in self?.needsDisplay = true }
        toolObserver = toolState.observe { [weak self] in
            guard let self else { return }
            if self.toolState.tool != .text { self.commitText() }
            self.applyStyleToTextField()
            self.window?.invalidateCursorRects(for: self)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: toolState.tool == .text ? .iBeam : .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .high
        AnnotationRenderer.draw(document, in: ctx, hiding: editingTextID)
    }

    func teardown() {
        if let toolObserver { toolState.removeObserver(toolObserver) }
        toolObserver = nil
        if let documentObserver { document.removeObserver(documentObserver) }
        documentObserver = nil
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point: CGPoint = clamp(convert(event.locationInWindow, from: nil))

        switch toolState.tool {
        case .text:
            commitText()
            if let existing = textAnnotation(at: point) {
                beginEditingText(existing)
            } else {
                beginNewText(at: point)
            }
        case .number:
            commitText()
            let annotation: Annotation = Annotation(kind: .number(document.nextNumber, point),
                                                    color: toolState.color, width: toolState.width.value)
            document.add(annotation)
            onFirstEdit?()
        default:
            commitText()
            dragStart = point
            activeID = nil
            if toolState.tool == .pen || toolState.tool == .highlighter {
                startAnnotation(at: point, current: point, shift: false)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point: CGPoint = clamp(convert(event.locationInWindow, from: nil))
        let shift: Bool = event.modifierFlags.contains(.shift)

        guard let id = activeID, var annotation = document.annotations.first(where: { $0.id == id }) else {
            // Wait for a small movement so plain clicks do not create empty shapes.
            if hypot(point.x - start.x, point.y - start.y) > 2 {
                startAnnotation(at: start, current: point, shift: shift)
            }
            return
        }
        annotation.kind = updatedKind(annotation.kind, start: start, current: point, shift: shift)
        document.update(annotation)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        activeID = nil
    }

    private func startAnnotation(at start: CGPoint, current: CGPoint, shift: Bool) {
        let kind: Annotation.Kind
        switch toolState.tool {
        case .arrow: kind = .arrow(start, start)
        case .rectangle: kind = .rectangle(CGRect(origin: start, size: .zero))
        case .ellipse: kind = .ellipse(CGRect(origin: start, size: .zero))
        case .line: kind = .line(start, start)
        case .pen: kind = .pen([start])
        case .highlighter: kind = .highlighter([start])
        case .blur: kind = .blur(CGRect(origin: start, size: .zero))
        case .text, .number: return
        }
        var annotation: Annotation = Annotation(kind: kind, color: toolState.color, width: toolState.width.value)
        annotation.kind = updatedKind(kind, start: start, current: current, shift: shift)
        document.add(annotation)
        activeID = annotation.id
        onFirstEdit?()
    }

    private func updatedKind(_ kind: Annotation.Kind, start: CGPoint, current: CGPoint, shift: Bool) -> Annotation.Kind {
        switch kind {
        case .arrow: return .arrow(start, shift ? snapAngle(from: start, to: current) : current)
        case .line: return .line(start, shift ? snapAngle(from: start, to: current) : current)
        case .rectangle: return .rectangle(rect(from: start, to: current, square: shift))
        case .ellipse: return .ellipse(rect(from: start, to: current, square: shift))
        case .blur: return .blur(rect(from: start, to: current, square: shift))
        case .pen(var points):
            points.append(current)
            return .pen(points)
        case .highlighter(var points):
            if shift, let first = points.first {
                // Shift draws a straight horizontal marker stroke.
                return .highlighter([first, CGPoint(x: current.x, y: first.y)])
            }
            points.append(current)
            return .highlighter(points)
        case .text, .number:
            return kind
        }
    }

    private func rect(from a: CGPoint, to b: CGPoint, square: Bool) -> CGRect {
        guard square else { return CGRect(corner: a, corner: b) }
        let side: CGFloat = max(abs(b.x - a.x), abs(b.y - a.y))
        let end: CGPoint = CGPoint(x: a.x + (b.x >= a.x ? side : -side), y: a.y + (b.y >= a.y ? side : -side))
        return CGRect(corner: a, corner: end)
    }

    private func snapAngle(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx: CGFloat = b.x - a.x
        let dy: CGFloat = b.y - a.y
        let length: CGFloat = hypot(dx, dy)
        let step: CGFloat = .pi / 4
        let angle: CGFloat = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: a.x + cos(angle) * length, y: a.y + sin(angle) * length)
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    // MARK: - Text

    private func textAnnotation(at point: CGPoint) -> Annotation? {
        for annotation in document.annotations.reversed() {
            if case .text(let string, let origin, let size) = annotation.kind {
                let box: CGRect = CGRect(origin: origin, size: AnnotationRenderer.textSize(string, fontSize: size))
                if box.insetBy(dx: -4, dy: -4).contains(point) { return annotation }
            }
        }
        return nil
    }

    private func beginNewText(at point: CGPoint) {
        editingTextID = nil
        editingFontSize = Annotation.textFontSize(for: toolState.width.value)
        let lineHeight: CGFloat = AnnotationRenderer.textSize("Ag", fontSize: editingFontSize).height
        editingTextOrigin = CGPoint(x: point.x, y: point.y - lineHeight / 2)
        showTextField(text: "", color: toolState.color)
    }

    private func beginEditingText(_ annotation: Annotation) {
        guard case .text(let string, let origin, let size) = annotation.kind else { return }
        editingTextID = annotation.id
        editingTextOrigin = origin
        editingFontSize = size
        showTextField(text: string, color: annotation.color)
        needsDisplay = true
    }

    private func showTextField(text: String, color: NSColor) {
        let field: NSTextField = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Annotation.textFont(size: editingFontSize)
        field.textColor = color
        field.delegate = self
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        addSubview(field)
        textField = field
        layoutTextField()
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: text.utf16.count, length: 0)
    }

    private func applyStyleToTextField() {
        guard let field = textField else { return }
        field.textColor = toolState.color
        if editingTextID == nil {
            editingFontSize = Annotation.textFontSize(for: toolState.width.value)
            field.font = Annotation.textFont(size: editingFontSize)
        }
        layoutTextField()
    }

    private func layoutTextField() {
        guard let field = textField else { return }
        let size: CGSize = AnnotationRenderer.textSize(field.stringValue + "  ", fontSize: editingFontSize)
        // NSTextField's cell adds a 2pt horizontal inset.
        field.frame = CGRect(x: editingTextOrigin.x - 2, y: editingTextOrigin.y,
                             width: max(size.width + 8, 40), height: size.height)
    }

    func controlTextDidChange(_ obj: Notification) {
        layoutTextField()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) {
            commitText()
            return true
        }
        return false
    }

    /// Finishes any in-progress text edit, turning it into (or updating) an annotation.
    func commitText() {
        guard let field = textField else { return }
        let string: String = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let color: NSColor = field.textColor ?? toolState.color
        textField = nil
        field.delegate = nil
        field.removeFromSuperview()

        if let id = editingTextID, var existing = document.annotations.first(where: { $0.id == id }) {
            if string.isEmpty {
                document.remove(id: id, recordUndo: true)
            } else {
                document.checkpoint()
                existing.kind = .text(string, editingTextOrigin, editingFontSize)
                existing.color = color
                document.update(existing)
            }
        } else if !string.isEmpty {
            document.add(Annotation(kind: .text(string, editingTextOrigin, editingFontSize),
                                    color: color, width: toolState.width.value))
            onFirstEdit?()
        }
        editingTextID = nil
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let flags: NSEvent.ModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars: String = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags.contains(.command) {
            switch (chars, flags.contains(.shift)) {
            case ("z", false): document.undo()
            case ("z", true): document.redo()
            case ("c", _): onAction?(.copy)
            case ("s", false): onAction?(.save)
            case ("s", true): onAction?(.saveAs)
            case ("e", _): onAction?(.openEditor)
            case ("=", _), ("+", _): onAction?(.zoomIn)
            case ("-", _): onAction?(.zoomOut)
            case ("0", _): onAction?(.zoomReset)
            default: super.keyDown(with: event)
            }
            return
        }

        switch Int(event.keyCode) {
        case 53: // Escape
            onAction?(.cancel)
            return
        case 36, 76: // Return, Enter
            onAction?(.copy)
            return
        default:
            break
        }

        if let char = chars.first, let tool = Tool.allCases.first(where: { $0.shortcut == char }) {
            toolState.tool = tool
            return
        }
        if let digit = Int(chars), (1...ToolState.presetColors.count).contains(digit) {
            toolState.selectPreset(digit - 1)
            return
        }
        super.keyDown(with: event)
    }
}
