import AppKit

enum ToolbarAction {
    case undo
    case redo
    case openEditor
    case save
    case copy
    case close
}

/// Floating palette: tools, color, stroke width, undo/redo and output actions.
@MainActor
final class ToolbarView: NSVisualEffectView {
    private let toolState: ToolState
    private let document: AnnotationDocument
    private let showsEditorButton: Bool
    var onAction: ((ToolbarAction) -> Void)?

    private var toolButtons: [Tool: NSButton] = [:]
    private let colorButton: NSButton = NSButton()
    private let widthControl: NSSegmentedControl = NSSegmentedControl()
    private let undoButton: NSButton = NSButton()
    private let redoButton: NSButton = NSButton()
    private var observer: UUID?
    private var documentObserver: UUID?

    init(toolState: ToolState, document: AnnotationDocument, showsEditorButton: Bool) {
        self.toolState = toolState
        self.document = document
        self.showsEditorButton = showsEditorButton
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        appearance = NSAppearance(named: .darkAqua)
        build()
        observer = toolState.observe { [weak self] in self?.refresh() }
        documentObserver = document.observe { [weak self] in self?.refresh() }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func teardown() {
        if let observer { toolState.removeObserver(observer) }
        observer = nil
        if let documentObserver { document.removeObserver(documentObserver) }
        documentObserver = nil
    }

    func refresh() {
        for (tool, button) in toolButtons {
            button.state = tool == toolState.tool ? .on : .off
            button.contentTintColor = tool == toolState.tool ? .controlAccentColor : .labelColor
        }
        colorButton.image = ToolbarView.swatch(toolState.color)
        widthControl.selectedSegment = toolState.width.rawValue
        undoButton.isEnabled = document.canUndo
        redoButton.isEnabled = document.canRedo
    }

    private func build() {
        let stack: NSStackView = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        for tool in Tool.allCases {
            let button: NSButton = iconButton(tool.symbolName, tooltip: tool.title) { [weak self] in
                self?.toolState.tool = tool
            }
            button.setButtonType(.pushOnPushOff)
            toolButtons[tool] = button
            stack.addArrangedSubview(button)
        }

        stack.addArrangedSubview(separator())

        colorButton.isBordered = false
        colorButton.toolTip = L("Color (1-8)")
        colorButton.imagePosition = .imageOnly
        colorButton.target = self
        colorButton.action = #selector(showColorMenu(_:))
        colorButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        stack.addArrangedSubview(colorButton)

        widthControl.segmentCount = StrokeWidth.allCases.count
        for width in StrokeWidth.allCases {
            widthControl.setImage(ToolbarView.dot(diameter: 3 + CGFloat(width.rawValue) * 3), forSegment: width.rawValue)
            widthControl.setWidth(24, forSegment: width.rawValue)
            widthControl.setToolTip(width.title, forSegment: width.rawValue)
        }
        widthControl.segmentStyle = .rounded
        widthControl.controlSize = .small
        widthControl.target = self
        widthControl.action = #selector(widthChanged(_:))
        stack.addArrangedSubview(widthControl)

        stack.addArrangedSubview(separator())

        configure(undoButton, symbol: "arrow.uturn.backward", tooltip: L("Undo (⌘Z)")) { [weak self] in
            self?.onAction?(.undo)
        }
        configure(redoButton, symbol: "arrow.uturn.forward", tooltip: L("Redo (⌘⇧Z)")) { [weak self] in
            self?.onAction?(.redo)
        }
        stack.addArrangedSubview(undoButton)
        stack.addArrangedSubview(redoButton)

        stack.addArrangedSubview(separator())

        if showsEditorButton {
            stack.addArrangedSubview(iconButton("macwindow", tooltip: L("Open in Editor (⌘E)")) { [weak self] in
                self?.onAction?(.openEditor)
            })
        }
        stack.addArrangedSubview(iconButton("square.and.arrow.down", tooltip: L("Save (⌘S)")) { [weak self] in
            self?.onAction?(.save)
        })
        stack.addArrangedSubview(iconButton("doc.on.doc", tooltip: L("Copy (⌘C / Enter)")) { [weak self] in
            self?.onAction?(.copy)
        })
        stack.addArrangedSubview(iconButton("xmark", tooltip: L("Close (Esc)")) { [weak self] in
            self?.onAction?(.close)
        })
    }

    // MARK: - Actions

    @objc private func widthChanged(_ sender: NSSegmentedControl) {
        toolState.width = StrokeWidth(rawValue: sender.selectedSegment) ?? .medium
    }

    @objc private func showColorMenu(_ sender: NSButton) {
        let menu: NSMenu = NSMenu()
        for (index, color) in ToolState.presetColors.enumerated() {
            let item: NSMenuItem = NSMenuItem(title: ToolState.presetColorNames[index],
                                              action: #selector(presetChosen(_:)), keyEquivalent: "\(index + 1)")
            item.keyEquivalentModifierMask = []
            item.tag = index
            item.target = self
            item.image = ToolbarView.swatch(color)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let custom: NSMenuItem = NSMenuItem(title: L("Custom Color…"), action: #selector(customColor(_:)), keyEquivalent: "")
        custom.target = self
        menu.addItem(custom)
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func presetChosen(_ sender: NSMenuItem) {
        toolState.selectPreset(sender.tag)
    }

    @objc private func customColor(_ sender: NSMenuItem) {
        let panel: NSColorPanel = NSColorPanel.shared
        panel.color = toolState.color
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.level = .screenSaver + 1
        panel.orderFrontRegardless()
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        toolState.color = sender.color
    }

    // MARK: - Builders

    private func iconButton(_ symbol: String, tooltip: String, handler: @escaping () -> Void) -> NSButton {
        let button: NSButton = NSButton()
        configure(button, symbol: symbol, tooltip: tooltip, handler: handler)
        return button
    }

    private func configure(_ button: NSButton, symbol: String, tooltip: String, handler: @escaping () -> Void) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.contentTintColor = .labelColor
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let target: ClosureTarget = ClosureTarget(handler)
        button.target = target
        button.action = #selector(ClosureTarget.invoke)
        objc_setAssociatedObject(button, &ClosureTarget.key, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private func separator() -> NSView {
        let box: NSBox = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 9).isActive = true
        box.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return box
    }

    static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: CGSize(width: 18, height: 18), flipped: false) { rect in
            let path: NSBezierPath = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            color.setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.8).setStroke()
            path.lineWidth = 1.5
            path.stroke()
            return true
        }
    }

    private static func dot(diameter: CGFloat) -> NSImage {
        let image: NSImage = NSImage(size: CGSize(width: 14, height: 14), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: CGRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2,
                                        width: diameter, height: diameter)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Bridges NSControl target/action to a Swift closure.
final class ClosureTarget: NSObject {
    nonisolated(unsafe) static var key: UInt8 = 0
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func invoke() {
        handler()
    }
}
