import AppKit
import UniformTypeIdentifiers

enum ExportError: LocalizedError {
    case renderFailed

    var errorDescription: String? { L("Could not create the image.") }
}

/// Flattens a document and sends it to the clipboard or disk.
@MainActor
enum Exporter {
    static func copy(_ document: AnnotationDocument) throws {
        let (png, tiff): (Data, Data?) = try encode(document)
        let pasteboard: NSPasteboard = .general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff { pasteboard.setData(tiff, forType: .tiff) }
    }

    /// Saves into the configured folder with a timestamped name.
    @discardableResult
    static func save(_ document: AnnotationDocument) throws -> URL {
        let folder: URL = Preferences.shared.saveFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url: URL = uniqueURL(in: folder, baseName: defaultFileName())
        try write(document, to: url)
        return url
    }

    /// Shows a save panel. Returns nil when the user cancels.
    static func saveAs(_ document: AnnotationDocument) throws -> URL? {
        let panel: NSSavePanel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = Preferences.shared.saveFolder
        panel.nameFieldStringValue = defaultFileName() + ".png"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try write(document, to: url)
        return url
    }

    static func defaultFileName(date: Date = Date()) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: date))"
    }

    private static func write(_ document: AnnotationDocument, to url: URL) throws {
        let (png, _): (Data, Data?) = try encode(document, includeTIFF: false)
        try png.write(to: url, options: .atomic)
        if Preferences.shared.copyOnSave { try copy(document) }
    }

    private static func encode(_ document: AnnotationDocument, includeTIFF: Bool = true) throws -> (Data, Data?) {
        guard let image = AnnotationRenderer.flatten(document) else { throw ExportError.renderFailed }
        let rep: NSBitmapImageRep = NSBitmapImageRep(cgImage: image)
        // Point size carries the Retina DPI (144) so the image pastes/opens at its on-screen size.
        rep.size = document.pointSize
        guard let png = rep.representation(using: .png, properties: [:]) else { throw ExportError.renderFailed }
        return (png, includeTIFF ? rep.tiffRepresentation : nil)
    }

    private static func uniqueURL(in folder: URL, baseName: String) -> URL {
        var url: URL = folder.appendingPathComponent(baseName).appendingPathExtension("png")
        var counter: Int = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(baseName) (\(counter))").appendingPathExtension("png")
            counter += 1
        }
        return url
    }

    static func showError(_ error: Error) {
        let alert: NSAlert = NSAlert(error: error)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

@MainActor
enum CaptureSound {
    private static let sound: NSSound? = {
        let path: String = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        return NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Tink")
    }()

    static func play() {
        guard Preferences.shared.playSound else { return }
        sound?.stop()
        sound?.play()
    }
}
