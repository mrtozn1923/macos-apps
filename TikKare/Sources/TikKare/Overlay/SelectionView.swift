import AppKit

/// Content of one overlay window: frozen screen, dimming, window highlight, selection and its handles.
/// Uses the window's (non-flipped) coordinates, which equal the screen's frame shifted to origin.
@MainActor
final class SelectionView: NSView {
    let frozen: FrozenScreen
    weak var controller: OverlayController?

    private(set) var selection: CGRect?
    private(set) var selectedWindowID: CGWindowID?
    private var hoveredWindow: WindowInfo?
    private var dragStart: CGPoint?
    private var activeHandle: Handle?
    private var handleOriginalSelection: CGRect = .zero
    private var isMoving: Bool = false
    private var lastDragPoint: CGPoint = .zero
    private var spaceHeld: Bool = false
    private var trackingArea: NSTrackingArea?

    /// When true the selection is being annotated and its interior belongs to the canvas.
    var isEditing: Bool = false { didSet { needsDisplay = true } }
    /// Resize handles are only offered until the first annotation is drawn.
    var showsHandles: Bool = false {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private static let handleSize: CGFloat = 8
    /// Grab band around the selection edge used to move it: this far outside / inside the edge.
    private static let moveBandOutside: CGFloat = 8
    private static let moveBandInside: CGFloat = 4

    init(frozen: FrozenScreen) {
        self.frozen = frozen
        super.init(frame: CGRect(origin: .zero, size: frozen.screen.frame.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area: NSTrackingArea = NSTrackingArea(rect: bounds,
                                                  options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        guard showsHandles, let selection else { return }
        let outer: CGRect = selection.insetBy(dx: -SelectionView.moveBandOutside, dy: -SelectionView.moveBandOutside)
        let band: CGFloat = SelectionView.moveBandOutside + SelectionView.moveBandInside
        let edges: [CGRect] = [
            CGRect(x: outer.minX, y: outer.maxY - band, width: outer.width, height: band),
            CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: band),
            CGRect(x: outer.minX, y: outer.minY, width: band, height: outer.height),
            CGRect(x: outer.maxX - band, y: outer.minY, width: band, height: outer.height),
        ]
        for edge in edges { addCursorRect(edge, cursor: .openHand) }
        for (_, rect) in handleRects(for: selection) { addCursorRect(rect.insetBy(dx: -5, dy: -5), cursor: .crosshair) }
    }

    // MARK: - Selection state

    func setSelection(_ rect: CGRect?, windowID: CGWindowID? = nil) {
        selection = rect.map { $0.intersection(bounds).integral }
        selectedWindowID = windowID
        hoveredWindow = nil
        needsDisplay = true
    }

    func clearSelection() {
        setSelection(nil)
        isEditing = false
        showsHandles = false
    }

    /// Converts a view-local rect to AppKit global coordinates.
    func globalRect(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: frozen.screen.frame.minX, dy: frozen.screen.frame.minY)
    }

    // MARK: - Mouse

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Handles straddle the canvas edge; route them to this view instead of the canvas.
        let local: CGPoint = convert(point, from: superview)
        if showsHandles, handle(at: local) != nil || isInMoveBand(local) { return self }
        return super.hitTest(point)
    }

    override func mouseMoved(with event: NSEvent) {
        guard selection == nil, dragStart == nil, controller?.allowsWindowPick == true else { return }
        let global: CGPoint = NSEvent.mouseLocation
        let window: WindowInfo? = controller?.windows.first(where: { $0.frame.contains(global) })
        if window?.id != hoveredWindow?.id {
            hoveredWindow = window
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point: CGPoint = convert(event.locationInWindow, from: nil)

        if showsHandles, let selection, let handle = handle(at: point) {
            activeHandle = handle
            handleOriginalSelection = selection
            dragStart = point
            return
        }
        if showsHandles, let selection, isInMoveBand(point) {
            isMoving = true
            handleOriginalSelection = selection
            dragStart = point
            NSCursor.closedHand.set()
            return
        }
        // Clicking outside an annotated selection does nothing, so work is never lost by accident.
        if let controller, !controller.canRestartSelection { return }

        controller?.selectionWillRestart(in: self)
        dragStart = point
        lastDragPoint = point
        activeHandle = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point: CGPoint = convert(event.locationInWindow, from: nil)

        if isMoving {
            selection = moved(handleOriginalSelection, by: CGPoint(x: point.x - start.x, y: point.y - start.y))
            selectedWindowID = nil
            controller?.selectionIsResizing(in: self)
            needsDisplay = true
            return
        }
        if let handle = activeHandle {
            selection = resized(handleOriginalSelection, handle: handle, to: point).intersection(bounds).integral
            selectedWindowID = nil
            controller?.selectionIsResizing(in: self)
            needsDisplay = true
            return
        }
        guard hypot(point.x - start.x, point.y - start.y) > 2 || selection != nil else { return }
        hoveredWindow = nil
        selectedWindowID = nil
        if spaceHeld, let current = selection {
            // Holding Space while drawing moves the selection instead of resizing it (like macOS).
            let delta: CGPoint = CGPoint(x: point.x - lastDragPoint.x, y: point.y - lastDragPoint.y)
            let shifted: CGRect = moved(current, by: delta)
            dragStart = CGPoint(x: start.x + shifted.minX - current.minX, y: start.y + shifted.minY - current.minY)
            selection = shifted
        } else {
            selection = CGRect(corner: start, corner: point).intersection(bounds).integral
        }
        lastDragPoint = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            activeHandle = nil
            isMoving = false
            window?.invalidateCursorRects(for: self)
        }
        guard dragStart != nil else { return }

        if selection == nil, let hovered = hoveredWindow {
            let local: CGRect = hovered.frame.offsetBy(dx: -frozen.screen.frame.minX, dy: -frozen.screen.frame.minY)
            let fullyVisible: Bool = bounds.contains(local)
            setSelection(local, windowID: fullyVisible ? hovered.id : nil)
        }
        guard let selection, selection.width >= 4, selection.height >= 4 else {
            self.selection = nil
            needsDisplay = true
            return
        }
        controller?.selectionDidFinish(in: self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            controller?.cancel()
            return
        }
        if event.keyCode == 49 { // Space
            spaceHeld = true
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spaceHeld = false
            return
        }
        super.keyUp(with: event)
    }

    // MARK: - Moving

    private func isInMoveBand(_ point: CGPoint) -> Bool {
        guard let selection else { return false }
        let outer: CGRect = selection.insetBy(dx: -SelectionView.moveBandOutside, dy: -SelectionView.moveBandOutside)
        let inner: CGRect = selection.insetBy(dx: SelectionView.moveBandInside, dy: SelectionView.moveBandInside)
        return outer.contains(point) && !inner.contains(point)
    }

    /// Offsets `rect` by `delta`, keeping it fully on this screen.
    private func moved(_ rect: CGRect, by delta: CGPoint) -> CGRect {
        var result: CGRect = rect.offsetBy(dx: delta.x, dy: delta.y)
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result.integral
    }

    // MARK: - Handles

    private func handleRects(for rect: CGRect) -> [(Handle, CGRect)] {
        let s: CGFloat = SelectionView.handleSize
        func box(_ x: CGFloat, _ y: CGFloat) -> CGRect { CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s) }
        return [
            (.topLeft, box(rect.minX, rect.maxY)), (.top, box(rect.midX, rect.maxY)),
            (.topRight, box(rect.maxX, rect.maxY)), (.right, box(rect.maxX, rect.midY)),
            (.bottomRight, box(rect.maxX, rect.minY)), (.bottom, box(rect.midX, rect.minY)),
            (.bottomLeft, box(rect.minX, rect.minY)), (.left, box(rect.minX, rect.midY)),
        ]
    }

    private func handle(at point: CGPoint) -> Handle? {
        guard let selection else { return nil }
        return handleRects(for: selection).first(where: { $0.1.insetBy(dx: -5, dy: -5).contains(point) })?.0
    }

    private func resized(_ rect: CGRect, handle: Handle, to p: CGPoint) -> CGRect {
        var minX: CGFloat = rect.minX, maxX: CGFloat = rect.maxX, minY: CGFloat = rect.minY, maxY: CGFloat = rect.maxY
        switch handle {
        case .topLeft: minX = p.x; maxY = p.y
        case .top: maxY = p.y
        case .topRight: maxX = p.x; maxY = p.y
        case .right: maxX = p.x
        case .bottomRight: maxX = p.x; minY = p.y
        case .bottom: minY = p.y
        case .bottomLeft: minX = p.x; minY = p.y
        case .left: minX = p.x
        }
        return CGRect(corner: CGPoint(x: minX, y: minY), corner: CGPoint(x: maxX, y: maxY))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        ctx.draw(frozen.image, in: bounds)

        let highlight: CGRect? = selection ?? hoveredWindow.map {
            $0.frame.offsetBy(dx: -frozen.screen.frame.minX, dy: -frozen.screen.frame.minY).intersection(bounds)
        }

        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.addRect(bounds)
        if let highlight { ctx.addRect(highlight) }
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        guard let highlight else { return }

        if selection == nil {
            // Window hover: tinted fill + border.
            ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor)
            ctx.fill(highlight)
        }
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(selection == nil ? 3 : 1)
        ctx.stroke(highlight.insetBy(dx: -0.5, dy: -0.5))

        if let selection {
            drawSizeLabel(for: selection)
            if showsHandles {
                for (_, rect) in handleRects(for: selection) {
                    ctx.setFillColor(NSColor.white.cgColor)
                    ctx.fill(rect)
                    ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
                    ctx.setLineWidth(1)
                    ctx.stroke(rect)
                }
            }
        }
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text: String = "\(Int(rect.width * frozen.scale)) × \(Int(rect.height * frozen.scale))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size: CGSize = (text as NSString).size(withAttributes: attributes)
        var origin: CGPoint = CGPoint(x: rect.minX, y: rect.maxY + 6)
        if origin.y + size.height + 4 > bounds.maxY { origin.y = rect.maxY - size.height - 10 }
        if isEditing && origin.y < rect.maxY { return }
        let box: CGRect = CGRect(x: origin.x, y: origin.y, width: size.width + 10, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 5, y: box.minY + 2), withAttributes: attributes)
    }
}
