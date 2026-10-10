import AppKit
import ScreenCaptureKit

/// A display grabbed at the moment a capture was triggered.
struct FrozenScreen {
    let screen: NSScreen
    let image: CGImage
    let scale: CGFloat
}

enum CaptureError: LocalizedError {
    case displayNotFound
    case windowNotFound

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return L("Display not found.")
        case .windowNotFound: return L("Window not found.")
        }
    }
}

/// The only type that talks to ScreenCaptureKit.
@MainActor
enum ScreenCapturer {
    static func captureAllScreens() async throws -> [FrozenScreen] {
        let content: SCShareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApps: [SCRunningApplication] = content.applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        var result: [FrozenScreen] = []
        for screen in NSScreen.screens {
            guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { continue }
            let filter: SCContentFilter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config: SCStreamConfiguration = makeConfiguration(size: screen.frame.size, scale: screen.backingScaleFactor)
            let image: CGImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            // Derive the real pixel ratio from the image; scaled display modes may not match backingScaleFactor.
            let scale: CGFloat = CGFloat(image.width) / max(screen.frame.width, 1)
            result.append(FrozenScreen(screen: screen, image: image, scale: scale))
        }
        return result
    }

    /// Captures a single window without anything overlapping it.
    static func captureWindow(id: CGWindowID, scale: CGFloat) async throws -> CGImage {
        let content: SCShareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.windowNotFound }
        let filter: SCContentFilter = SCContentFilter(desktopIndependentWindow: window)
        let config: SCStreamConfiguration = makeConfiguration(size: window.frame.size, scale: scale)
        config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Captures `rect` (AppKit global coordinates) on `screen`, excluding TıkKare's own windows.
    static func captureRect(_ rect: CGRect, on screen: NSScreen) async throws -> CGImage {
        let content: SCShareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let ownApps: [SCRunningApplication] = content.applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter: SCContentFilter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config: SCStreamConfiguration = makeConfiguration(size: rect.size, scale: screen.backingScaleFactor)
        config.sourceRect = screen.localTopLeftRect(fromGlobal: rect)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private static func makeConfiguration(size: CGSize, scale: CGFloat) -> SCStreamConfiguration {
        let config: SCStreamConfiguration = SCStreamConfiguration()
        config.width = max(1, Int((size.width * scale).rounded()))
        config.height = max(1, Int((size.height * scale).rounded()))
        config.showsCursor = false
        config.captureResolution = .best
        config.colorSpaceName = CGColorSpace.sRGB
        return config
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Converts a rect in AppKit global coordinates to this display's top-left-origin point space.
    func localTopLeftRect(fromGlobal rect: CGRect) -> CGRect {
        CGRect(x: rect.minX - frame.minX,
               y: frame.maxY - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    static func screen(containing point: CGPoint) -> NSScreen? {
        screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? main
    }
}
