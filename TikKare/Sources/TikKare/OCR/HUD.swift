import AppKit

/// Short-lived, non-interactive message at the top of the active screen.
@MainActor
enum HUD {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ message: String, symbol: String = "checkmark.circle.fill", duration: TimeInterval = 1.6) {
        hideWork?.cancel()
        panel?.orderOut(nil)

        let label: NSTextField = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingMiddle

        let icon: NSImageView = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .white

        let stack: NSStackView = NSStackView(views: [icon, label])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 16)

        let background: NSVisualEffectView = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.appearance = NSAppearance(named: .darkAqua)
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])

        let size: CGSize = stack.fittingSize
        let screen: NSScreen = NSScreen.screen(containing: NSEvent.mouseLocation) ?? NSScreen.main!
        let frame: CGRect = CGRect(x: screen.visibleFrame.midX - size.width / 2,
                                   y: screen.visibleFrame.maxY - size.height - 24,
                                   width: size.width, height: size.height)
        let newPanel: NSPanel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered, defer: false)
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.level = .statusBar
        newPanel.ignoresMouseEvents = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .transient]
        newPanel.contentView = background
        newPanel.alphaValue = 0
        newPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; newPanel.animator().alphaValue = 1 }
        panel = newPanel

        let work: DispatchWorkItem = DispatchWorkItem {
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; newPanel.animator().alphaValue = 0 }) {
                    MainActor.assumeIsolated {
                        newPanel.orderOut(nil)
                        if HUD.panel === newPanel { HUD.panel = nil }
                    }
                }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
