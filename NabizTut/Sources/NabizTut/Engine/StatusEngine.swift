import Foundation

enum StatusEvent {
    /// First failure of a streak: the scheduler should run a confirmation check soon.
    case needsConfirmation
    case wentDown(reason: String)
    case recovered(downtime: TimeInterval)
    case sslExpiring(expiry: Date)
}

/// Turns check results into monitor states and events. Holds no network or UI code.
@MainActor
final class StatusEngine {
    static let failuresToDown: Int = 2
    /// Response time above this multiple of the 24 h median marks a monitor as slow.
    static let slowFactor: Double = 3
    /// Ignore "slow" below this absolute time to avoid noise on very fast endpoints.
    static let slowFloorMs: Int = 500

    private let state: AppState
    private let history: HistoryRepository

    init(state: AppState, history: HistoryRepository) {
        self.state = state
        self.history = history
    }

    func process(_ result: CheckResult, monitor: Monitor) -> [StatusEvent] {
        var status: MonitorStatus = state.status(for: monitor.id)
        var events: [StatusEvent] = []
        status.lastResult = result
        if let expiry = result.certExpiry { status.certExpiry = expiry }

        if result.ok {
            if status.state == .down {
                let downtime: TimeInterval = result.date.timeIntervalSince(status.firstFailure ?? status.since ?? result.date)
                history.closeIncident(monitorID: monitor.id, end: result.date)
                events.append(.recovered(downtime: downtime))
            }
            status.consecutiveFailures = 0
            status.firstFailure = nil
            let warning: String? = warningReason(result, monitor: monitor)
            let newState: MonitorState = warning == nil ? .up : .warning
            if newState != status.state { status.since = result.date }
            status.state = newState
            status.reason = warning
        } else {
            status.consecutiveFailures += 1
            if status.firstFailure == nil { status.firstFailure = result.date }
            let reason: String = result.error ?? L("Check failed")
            if status.state == .down {
                status.reason = reason
            } else if status.consecutiveFailures >= StatusEngine.failuresToDown {
                let start: Date = status.firstFailure ?? result.date
                status.state = .down
                status.since = start
                status.reason = reason
                history.openIncident(monitorID: monitor.id, start: start, reason: reason)
                events.append(.wentDown(reason: reason))
            } else {
                events.append(.needsConfirmation)
            }
        }

        if let expiry = result.certExpiry, expiresSoon(expiry, monitor: monitor),
           !history.sslWarned(monitorID: monitor.id, expiry: expiry) {
            history.markSSLWarned(monitorID: monitor.id, expiry: expiry)
            events.append(.sslExpiring(expiry: expiry))
        }

        let dayAgo: Date = Date().addingTimeInterval(-86_400)
        status.uptime24h = history.uptime(monitorID: monitor.id, since: dayAgo)
        status.sparkline = history.samples(monitorID: monitor.id, since: Date().addingTimeInterval(-3600))
            .map { $0.ok ? $0.latencyMs : nil }
        state.statuses[monitor.id] = status
        state.historyRevision += 1
        return events
    }

    /// Restores sparkline/uptime at launch so the panel is not empty before the first check.
    func preload(_ monitor: Monitor) {
        var status: MonitorStatus = state.status(for: monitor.id)
        status.uptime24h = history.uptime(monitorID: monitor.id, since: Date().addingTimeInterval(-86_400))
        let recent: [Sample] = history.samples(monitorID: monitor.id, since: Date().addingTimeInterval(-3600))
        status.sparkline = recent.map { $0.ok ? $0.latencyMs : nil }
        state.statuses[monitor.id] = status
    }

    func reset(_ monitorID: UUID) {
        state.statuses[monitorID] = nil
    }

    private func expiresSoon(_ expiry: Date, monitor: Monitor) -> Bool {
        expiry.timeIntervalSinceNow < TimeInterval(monitor.sslWarnDays) * 86_400
    }

    private func warningReason(_ result: CheckResult, monitor: Monitor) -> String? {
        if let expiry = result.certExpiry, expiresSoon(expiry, monitor: monitor) {
            let days: Int = max(0, Int(expiry.timeIntervalSinceNow / 86_400))
            return L("SSL expires in %ld days", days)
        }
        if let latency = result.latencyMs, latency >= StatusEngine.slowFloorMs,
           let median = history.medianLatency(monitorID: monitor.id, since: Date().addingTimeInterval(-86_400)),
           Double(latency) > Double(median) * StatusEngine.slowFactor {
            return L("Slow: %@ (usually %@)", DurationFormatter.latency(latency), DurationFormatter.latency(median))
        }
        return nil
    }
}
