import Foundation
import Observation

enum OverallState {
    case empty
    case allUp
    case warning
    case down
    case offline
}

/// Observable state shared by the panel, menu bar and windows.
@Observable
@MainActor
final class AppState {
    var monitors: [Monitor] = []
    var statuses: [UUID: MonitorStatus] = [:]
    var offline: Bool = false
    var panelOpacity: Double = Preferences.shared.panelOpacity
    var panelEditing: Bool = false
    /// Bumped whenever history changes so open charts can reload.
    var historyRevision: Int = 0

    func status(for id: UUID) -> MonitorStatus {
        statuses[id] ?? MonitorStatus()
    }

    /// Monitors ordered for display: problems first, then the user's order.
    var sortedMonitors: [Monitor] {
        monitors.enumerated().sorted { a, b in
            let sa: Int = effectiveState(a.element).sortOrder
            let sb: Int = effectiveState(b.element).sortOrder
            return sa != sb ? sa < sb : a.offset < b.offset
        }.map(\.element)
    }

    func effectiveState(_ monitor: Monitor) -> MonitorState {
        monitor.paused ? .paused : status(for: monitor.id).state
    }

    var activeMonitors: [Monitor] { monitors.filter { !$0.paused } }

    var upCount: Int {
        activeMonitors.filter { [.up, .warning].contains(effectiveState($0)) }.count
    }

    var overall: OverallState {
        if offline { return .offline }
        let active: [Monitor] = activeMonitors
        if active.isEmpty { return .empty }
        let states: [MonitorState] = active.map(effectiveState)
        if states.contains(.down) { return .down }
        if states.contains(.warning) { return .warning }
        return .allUp
    }
}
