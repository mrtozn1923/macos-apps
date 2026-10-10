import AppKit

/// Repeatedly captures a fixed region while the user scrolls, then opens the stitched result in the editor.
@MainActor
final class ScrollCaptureController {
    private let region: CGRect
    private let screen: NSScreen
    private let scale: CGFloat
    private let stitcher: ImageStitcher = ImageStitcher()
    private let onFinish: () -> Void

    private var borderWindow: NSWindow?
    private var panel: NSPanel?
    private var statusLabel: NSTextField?
    private var timer: Timer?
    private var isCapturing: Bool = false
    private var isFinished: Bool = false
    private var frames: Int = 0

    init(selection: RegionSelection, onFinish: @escaping () -> Void) {
        self.region = selection.globalRect
        self.screen = selection.frozen.screen
        self.scale = selection.frozen.scale
        self.onFinish = onFinish
    }

    func start() {
        showBorder()
        showPanel()
        CaptureSound.play()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// Finishes the session (also triggered by pressing the scrolling hotkey again).
    func finish() {
        guard !isFinished else { return }
        isFinished = true
        tearDown()
        if let image = stitcher.result() {
            let document: AnnotationDocument = AnnotationDocument(baseImage: image, scale: scale)
            EditorWindowController.open(document: document, toolState: ToolState())
        }
        onFinish()
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        tearDown()
        onFinish()
    }

    private func tick() {
        guard !isCapturing, !isFinished else { return }
        isCapturing = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isCapturing = false }
            guard let image = try? await ScreenCapturer.captureRect(self.region, on: self.screen), !self.isFinished else { return }
            switch self.stitcher.append(image) {
            case .first, .appended:
                self.frames += 1
                self.updateStatus(hint: nil)
            case .noMatch:
                self.updateStatus(hint: L("Scroll a bit slower"))
            case .unchanged:
                break
            case .full:
                self.finish()
            }
        }
    }

    private func updateStatus(hint: String?) {
        let height: Int = stitcher.height
        statusLabel?.stringValue = hint ?? L("Scroll down… %ld px", height)
    }

    // MARK: - Windows

    private func showBorder() {
        let inset: CGFloat = 3
        let window: NSWindow = NSWindow(contentRect: region.insetBy(dx: -inset, dy: -inset), styleMask: .borderless,
                                        backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let border: NSView = NSView()
        border.wantsLayer = true
        border.layer?.borderColor = NSColor.systemRed.cgColor
        border.layer?.borderWidth = 2
        window.contentView = border
        window.orderFrontRegardless()
        borderWindow = window
    }

    private func showPanel() {
        let label: NSTextField = NSTextField(labelWithString: L("Scroll down…"))
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        statusLabel = label

        let done: NSButton = NSButton(title: L("Done"), target: nil, action: nil)
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let doneTarget: ClosureTarget = ClosureTarget { [weak self] in self?.finish() }
        done.target = doneTarget
        done.action = #selector(ClosureTarget.invoke)
        objc_setAssociatedObject(done, &ClosureTarget.key, doneTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let cancel: NSButton = NSButton(title: L("Cancel"), target: nil, action: nil)
        cancel.bezelStyle = .rounded
        let cancelTarget: ClosureTarget = ClosureTarget { [weak self] in self?.cancel() }
        cancel.target = cancelTarget
        cancel.action = #selector(ClosureTarget.invoke)
        objc_setAssociatedObject(cancel, &ClosureTarget.key, cancelTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let stack: NSStackView = NSStackView(views: [label, cancel, done])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 8)

        let background: NSVisualEffectView = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.appearance = NSAppearance(named: .darkAqua)
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        let size: CGSize = stack.fittingSize
        var origin: CGPoint = CGPoint(x: region.midX - size.width / 2, y: region.minY - size.height - 12)
        if origin.y < screen.visibleFrame.minY + 4 {
            origin.y = region.maxY + 12
        }
        if origin.y + size.height > screen.visibleFrame.maxY {
            // Region fills the screen vertically: sit inside its bottom edge (excluded from the capture anyway).
            origin.y = region.minY + 12
        }
        origin.x = min(max(origin.x, screen.visibleFrame.minX + 4), screen.visibleFrame.maxX - size.width - 4)

        // Non-activating so the scrolled app keeps keyboard focus and receives wheel events.
        let panel: NSPanel = NSPanel(contentRect: CGRect(origin: origin, size: size),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.contentView = background
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func tearDown() {
        timer?.invalidate()
        timer = nil
        borderWindow?.orderOut(nil)
        panel?.orderOut(nil)
        borderWindow = nil
        panel = nil
    }
}
