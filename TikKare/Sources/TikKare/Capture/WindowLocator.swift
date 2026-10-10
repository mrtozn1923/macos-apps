import AppKit

struct WindowInfo {
    let id: CGWindowID
    /// Frame in AppKit global coordinates (bottom-left origin).
    let frame: CGRect
    let ownerName: String
}

/// Lists normal on-screen windows front-to-back so the overlay can highlight the one under the cursor.
enum WindowLocator {
    static func windows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID: Int32 = ProcessInfo.processInfo.processIdentifier
        let primaryHeight: CGFloat = NSScreen.screens.first?.frame.height ?? 0

        return list.compactMap { entry -> WindowInfo? in
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let cgBounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            let alpha: Double = entry[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.01, cgBounds.width > 40, cgBounds.height > 40 else { return nil }
            let frame: CGRect = CGRect(x: cgBounds.minX,
                                       y: primaryHeight - cgBounds.maxY,
                                       width: cgBounds.width,
                                       height: cgBounds.height)
            let owner: String = entry[kCGWindowOwnerName as String] as? String ?? ""
            return WindowInfo(id: id, frame: frame, ownerName: owner)
        }
    }
}
