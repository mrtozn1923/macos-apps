import Foundation
import SwiftUI

enum AppPaths {
    static var supportDirectory: URL {
        // NABIZTUT_DATA_DIR lets development runs use a throwaway folder instead of the real data.
        let dir: URL
        if let override = ProcessInfo.processInfo.environment["NABIZTUT_DATA_DIR"], !override.isEmpty {
            dir = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("NabizTut", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var monitorsFile: URL { supportDirectory.appendingPathComponent("monitors.json") }
    static var databaseFile: URL { supportDirectory.appendingPathComponent("history.sqlite") }

    static func timestampSuffix() -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

/// Loads and saves the monitor list. Secret header values are kept in the Keychain, not in the JSON file.
@MainActor
final class MonitorStore {
    private(set) var monitors: [Monitor] = []
    /// Set when the JSON file was unreadable and had to be moved aside.
    private(set) var loadProblem: String?

    func load() {
        let url: URL = AppPaths.monitorsFile
        guard FileManager.default.fileExists(atPath: url.path) else {
            monitors = []
            return
        }
        do {
            let data: Data = try Data(contentsOf: url)
            var loaded: [Monitor] = try JSONDecoder().decode([Monitor].self, from: data)
            for index in loaded.indices {
                for h in loaded[index].headers.indices where loaded[index].headers[h].secret {
                    loaded[index].headers[h].value = SecretStore.get(monitorID: loaded[index].id,
                                                                     header: loaded[index].headers[h].name) ?? ""
                }
            }
            monitors = loaded
        } catch {
            let backup: URL = url.deletingPathExtension()
                .appendingPathExtension("broken-\(AppPaths.timestampSuffix()).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            monitors = []
            loadProblem = L("The monitor list could not be read and was moved to %@.", backup.lastPathComponent)
        }
    }

    func upsert(_ monitor: Monitor) {
        if let index = monitors.firstIndex(where: { $0.id == monitor.id }) {
            let old: Monitor = monitors[index]
            // Remove Keychain entries for secret headers that no longer exist or stopped being secret.
            for header in old.headers where header.secret {
                let stillSecret: Bool = monitor.headers.contains { $0.secret && $0.name.lowercased() == header.name.lowercased() }
                if !stillSecret { SecretStore.delete(monitorID: monitor.id, header: header.name) }
            }
            monitors[index] = monitor
        } else {
            monitors.append(monitor)
        }
        save()
    }

    func delete(_ id: UUID) {
        guard let monitor = monitors.first(where: { $0.id == id }) else { return }
        for header in monitor.headers where header.secret {
            SecretStore.delete(monitorID: id, header: header.name)
        }
        monitors.removeAll { $0.id == id }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        monitors.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func save() {
        var persisted: [Monitor] = monitors
        for index in persisted.indices {
            for h in persisted[index].headers.indices where persisted[index].headers[h].secret {
                let header: HeaderField = persisted[index].headers[h]
                SecretStore.set(header.value, monitorID: persisted[index].id, header: header.name)
                persisted[index].headers[h].value = ""
            }
        }
        do {
            let encoder: JSONEncoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(persisted).write(to: AppPaths.monitorsFile, options: .atomic)
        } catch {
            NSLog("NabizTut: failed to save monitors: \(error)")
        }
    }
}
