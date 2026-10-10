import AppKit

/// A finished region choice for modes that do not annotate in place (OCR, scrolling).
struct RegionSelection {
    let frozen: FrozenScreen
    /// AppKit global coordinates.
    let globalRect: CGRect
    /// Pixels of the frozen screen inside the selection.
    let image: CGImage?
}

/// Runs one capture session over every display: select, then annotate in place or hand the region back.
@MainActor
final class OverlayController {
    enum Purpose {
        case annotate
        case fullScreen
        case selectRegion((RegionSelection) -> Void)
    }

    let purpose: Purpose
    let windows: [WindowInfo]
    let toolState: ToolState = ToolState()

    private var overlayWindows: [OverlayWindow] = []
    private var selectionViews: [SelectionView] = []
    private var activeView: SelectionView?
    private var document: AnnotationDocument?
    private var canvas: CanvasView?
    private var toolbar: ToolbarView?
    private var captureTask: Task<Void, Never>?
    private let onFinish: () -> Void

    var allowsWindowPick: Bool { true }

    var canRestartSelection: Bool { document?.isEmpty ?? true }

    init(purpose: Purpose, frozenScreens: [FrozenScreen], onFinish: @escaping () -> Void) {
        self.purpose = purpose
        self.windows = WindowLocator.windows()
        self.onFinish = onFinish

        for frozen in frozenScreens {
            let window: OverlayWindow = OverlayWindow(screen: frozen.screen)
            let view: SelectionView = SelectionView(frozen: frozen)
            view.controller = self
            window.contentView = view
            overlayWindows.append(window)
            selectionViews.append(view)
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        let mouse: CGPoint = NSEvent.mouseLocation
        for (window, view) in zip(overlayWindows, selectionViews) {
            window.orderFrontRegardless()
            if window.frame.contains(mouse) {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(view)
            }
        }
        if case .fullScreen = purpose,
           let view = selectionViews.first(where: { $0.window?.frame.contains(mouse) == true }) ?? selectionViews.first {
            view.setSelection(view.bounds)
            selectionDidFinish(in: view)
        }
    }

    // MARK: - Selection callbacks

    func selectionWillRestart(in view: SelectionView) {
        tearDownEditing()
        for other in selectionViews { other.clearSelection() }
        activeView = view
        view.window?.makeKey()
    }

    func selectionIsResizing(in view: SelectionView) {
        canvas?.isHidden = true
        toolbar?.isHidden = true
    }

    func selectionDidFinish(in view: SelectionView) {
        guard let selection = view.selection else { return }
        activeView = view
        let frozen: FrozenScreen = view.frozen

        switch purpose {
        case .selectRegion(let handler):
            let result: RegionSelection = RegionSelection(frozen: frozen,
                                                          globalRect: view.globalRect(selection),
                                                          image: crop(frozen, to: selection))
            close()
            handler(result)

        case .annotate, .fullScreen:
            if let windowID = view.selectedWindowID {
                captureTask?.cancel()
                captureTask = Task { [weak self] in
                    let image: CGImage? = try? await ScreenCapturer.captureWindow(id: windowID, scale: frozen.scale)
                    guard let self, !Task.isCancelled, self.activeView === view, view.selection == selection else { return }
                    self.beginEditing(in: view, image: image ?? self.crop(frozen, to: selection))
                }
            } else {
                beginEditing(in: view, image: crop(frozen, to: selection))
            }
        }
    }

    private func crop(_ frozen: FrozenScreen, to rect: CGRect) -> CGImage? {
        let height: CGFloat = frozen.screen.frame.height
        let pixelRect: CGRect = CGRect(x: rect.minX * frozen.scale,
                                       y: (height - rect.maxY) * frozen.scale,
                                       width: rect.width * frozen.scale,
                                       height: rect.height * frozen.scale).integral
        return frozen.image.cropping(to: pixelRect)
    }

    // MARK: - Editing

    private func beginEditing(in view: SelectionView, image: CGImage?) {
        guard let image, let selection = view.selection else { return }
        tearDownEditing()
        CaptureSound.play()

        // Window captures may differ slightly in size; scale is derived so the image fills the selection.
        let scale: CGFloat = CGFloat(image.width) / max(selection.width, 1)
        let document: AnnotationDocument = AnnotationDocument(baseImage: image, scale: scale)
        let canvas: CanvasView = CanvasView(document: document, toolState: toolState)
        canvas.frame = selection
        canvas.onAction = { [weak self] action in self?.handle(action) }
        canvas.onFirstEdit = { [weak view] in view?.showsHandles = false }
        view.addSubview(canvas)

        let toolbar: ToolbarView = ToolbarView(toolState: toolState, document: document, showsEditorButton: true)
        toolbar.onAction = { [weak self] action in self?.handle(action) }
        view.addSubview(toolbar)
        toolbar.frame.size = toolbar.fittingSize
        toolbar.frame.origin = toolbarOrigin(size: toolbar.frame.size, selection: selection, bounds: view.bounds)

        self.document = document
        self.canvas = canvas
        self.toolbar = toolbar
        view.isEditing = true
        view.showsHandles = true
        view.window?.makeKeyAndOrderFront(nil)
        view.window?.makeFirstResponder(canvas)
    }

    private func toolbarOrigin(size: CGSize, selection: CGRect, bounds: CGRect) -> CGPoint {
        let gap: CGFloat = 10
        var y: CGFloat
        if selection.minY - gap - size.height >= bounds.minY + 4 {
            y = selection.minY - gap - size.height // below
        } else if selection.maxY + gap + size.height <= bounds.maxY - 4 {
            y = selection.maxY + gap // above
        } else {
            y = selection.minY + gap // inside, bottom
        }
        var x: CGFloat = selection.maxX - size.width
        x = min(max(x, bounds.minX + 4), bounds.maxX - size.width - 4)
        y = min(max(y, bounds.minY + 4), bounds.maxY - size.height - 4)
        return CGPoint(x: x, y: y)
    }

    private func tearDownEditing() {
        captureTask?.cancel()
        canvas?.teardown()
        canvas?.removeFromSuperview()
        toolbar?.teardown()
        toolbar?.removeFromSuperview()
        canvas = nil
        toolbar = nil
        document = nil
    }

    // MARK: - Actions

    private func handle(_ action: ToolbarAction) {
        switch action {
        case .undo: document?.undo()
        case .redo: document?.redo()
        case .openEditor: handle(CanvasAction.openEditor)
        case .save: handle(CanvasAction.save)
        case .copy: handle(CanvasAction.copy)
        case .close: cancel()
        }
    }

    private func handle(_ action: CanvasAction) {
        canvas?.commitText()
        guard let document else { return }
        switch action {
        case .copy:
            close()
            do {
                try Exporter.copy(document)
                HUD.show(L("Copied to clipboard"))
            } catch {
                Exporter.showError(error)
            }
        case .save:
            close()
            do {
                let url: URL = try Exporter.save(document)
                HUD.show(L("Saved: %@", url.lastPathComponent))
            } catch {
                Exporter.showError(error)
                EditorWindowController.open(document: document, toolState: toolState)
            }
        case .saveAs:
            close()
            do {
                if let url = try Exporter.saveAs(document) {
                    HUD.show(L("Saved: %@", url.lastPathComponent))
                }
            } catch {
                Exporter.showError(error)
                EditorWindowController.open(document: document, toolState: toolState)
            }
        case .openEditor:
            close()
            EditorWindowController.open(document: document, toolState: toolState)
        case .cancel:
            cancel()
        case .zoomIn, .zoomOut, .zoomReset:
            break
        }
    }

    func cancel() {
        close()
    }

    private func close() {
        guard !overlayWindows.isEmpty else { return }
        tearDownEditing()
        for window in overlayWindows {
            window.orderOut(nil)
            window.contentView = nil
        }
        overlayWindows.removeAll()
        selectionViews.removeAll()
        onFinish()
    }
}
