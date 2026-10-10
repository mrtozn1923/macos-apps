import AppKit

/// Regular window for annotating a capture with zoom and plenty of room.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static var openEditors: Set<EditorWindowController> = []

    private let annotationDocument: AnnotationDocument
    private let toolState: ToolState
    private let canvas: CanvasView
    private let toolbar: ToolbarView
    private let scrollView: NSScrollView = NSScrollView()

    static func open(document: AnnotationDocument, toolState: ToolState) {
        let controller: EditorWindowController = EditorWindowController(annotationDocument: document, toolState: toolState)
        openEditors.insert(controller)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.makeFirstResponder(controller.canvas)
    }

    private init(annotationDocument: AnnotationDocument, toolState: ToolState) {
        self.annotationDocument = annotationDocument
        self.toolState = toolState
        self.canvas = CanvasView(document: annotationDocument, toolState: toolState)
        self.toolbar = ToolbarView(toolState: toolState, document: annotationDocument, showsEditorButton: false)

        let window: NSWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                                        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                        backing: .buffered, defer: false)
        window.title = "TıkKare — \(Int(annotationDocument.pointSize.width * annotationDocument.scale)) × \(Int(annotationDocument.pointSize.height * annotationDocument.scale))"
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 640, height: 320)
        window.titlebarAppearsTransparent = false
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        sizeWindowToFit(window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildContent(in window: NSWindow) {
        let container: NSView = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        scrollView.contentView = CenteringClipView()
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 8
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.underPageBackgroundColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8),
            toolbar.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container

        canvas.onAction = { [weak self] action in self?.handle(action) }
        toolbar.onAction = { [weak self] action in self?.handle(action) }
    }

    private func sizeWindowToFit(_ window: NSWindow) {
        let screen: NSScreen = NSScreen.screen(containing: NSEvent.mouseLocation) ?? NSScreen.main!
        let available: CGSize = CGSize(width: screen.visibleFrame.width * 0.85, height: screen.visibleFrame.height * 0.85)
        let chrome: CGFloat = 100 // title bar + toolbar
        let image: CGSize = annotationDocument.pointSize
        let fit: CGFloat = min(1, available.width / image.width, (available.height - chrome) / image.height)
        scrollView.magnification = max(fit, 0.1)
        let content: CGSize = CGSize(width: max(image.width * fit + 2, 640),
                                     height: max(image.height * fit + chrome, 320))
        window.setContentSize(content)
    }

    // MARK: - Actions

    private func handle(_ action: ToolbarAction) {
        switch action {
        case .undo: annotationDocument.undo()
        case .redo: annotationDocument.redo()
        case .save: handle(CanvasAction.save)
        case .copy: handle(CanvasAction.copy)
        case .close: window?.performClose(nil)
        case .openEditor: break
        }
    }

    private func handle(_ action: CanvasAction) {
        canvas.commitText()
        do {
            switch action {
            case .copy:
                try Exporter.copy(annotationDocument)
                HUD.show(L("Copied to clipboard"))
            case .save:
                let url: URL = try Exporter.save(annotationDocument)
                HUD.show(L("Saved: %@", url.lastPathComponent))
            case .saveAs:
                if let url = try Exporter.saveAs(annotationDocument) {
                    HUD.show(L("Saved: %@", url.lastPathComponent))
                }
            case .zoomIn:
                scrollView.animator().magnification = min(scrollView.magnification * 1.25, scrollView.maxMagnification)
            case .zoomOut:
                scrollView.animator().magnification = max(scrollView.magnification / 1.25, scrollView.minMagnification)
            case .zoomReset:
                scrollView.animator().magnification = 1
            case .cancel, .openEditor:
                break
            }
        } catch {
            Exporter.showError(error)
        }
    }

    func windowWillClose(_ notification: Notification) {
        canvas.teardown()
        toolbar.teardown()
        EditorWindowController.openEditors.remove(self)
        if EditorWindowController.openEditors.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// Keeps the annotationDocument centered when it is smaller than the visible area.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect: NSRect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let docFrame: NSRect = documentView.frame
        if rect.width > docFrame.width { rect.origin.x = (docFrame.width - rect.width) / 2 }
        if rect.height > docFrame.height { rect.origin.y = (docFrame.height - rect.height) / 2 }
        return rect
    }
}
