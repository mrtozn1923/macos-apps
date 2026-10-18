import Foundation

enum MonitorState: Equatable {
    case unknown
    case up
    case warning
    case down
    case paused

    /// Sort weight: problems first.
    var sortOrder: Int {
        switch self {
        case .down: return 0
        case .warning: return 1
        case .up: return 2
        case .unknown: return 3
        case .paused: return 4
        }
    }
}

/// Live status of one monitor, derived by `StatusEngine`.
struct MonitorStatus {
    var state: MonitorState = .unknown
    var lastResult: CheckResult?
    /// When the current state began (used for "down · 4 min").
    var since: Date?
    /// Why the monitor is down or in warning.
    var reason: String?
    var consecutiveFailures: Int = 0
    /// Time of the first failure in the current failing streak (incident start).
    var firstFailure: Date?
    /// 24 h uptime percentage, refreshed after each check.
    var uptime24h: Double?
    /// Last hour of latencies for the sparkline (oldest first; nil = failed check).
    var sparkline: [Int?] = []
    var certExpiry: Date?
}

struct Incident: Identifiable {
    let id: Int64
    let monitorID: UUID
    let started: Date
    let ended: Date?
    let reason: String

    var duration: TimeInterval { (ended ?? Date()).timeIntervalSince(started) }
}

enum DurationFormatter {
    /// "45 sn", "4 dk", "2 sa 5 dk", "3 g 2 sa" (localized).
    static func short(_ interval: TimeInterval) -> String {
        let seconds: Int = max(0, Int(interval))
        if seconds < 60 { return L("%ld s", seconds) }
        let minutes: Int = seconds / 60
        if minutes < 60 { return L("%ld min", minutes) }
        let hours: Int = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? L("%ld h", hours) : L("%ld h %ld min", hours, minutes % 60) }
        let days: Int = hours / 24
        return hours % 24 == 0 ? L("%ld d", days) : L("%ld d %ld h", days, hours % 24)
    }

    static func latency(_ ms: Int?) -> String {
        guard let ms else { return "—" }
        if ms < 1000 { return "\(ms) ms" }
        return String(format: "%.1f s", Double(ms) / 1000)
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value >= 99.995 { return "100%" }
        return String(format: value >= 99 ? "%.2f%%" : "%.1f%%", value)
    }
}
