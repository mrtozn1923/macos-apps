import Foundation

/// Runs each monitor on its own interval, staggered so checks never fire all at once.
@MainActor
final class Scheduler {
    /// Delay before the confirmation check after a first failure.
    static let confirmationDelay: TimeInterval = 30
    /// Initial checks are spread over this window at launch/resume.
    static let staggerWindow: TimeInterval = 30

    private let state: AppState
    private let engine: StatusEngine
    private let history: HistoryRepository
    private let notifier: Notifier
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var running: Bool = false

    init(state: AppState, engine: StatusEngine, history: HistoryRepository, notifier: Notifier) {
        self.state = state
        self.engine = engine
        self.history = history
        self.notifier = notifier
    }

    func start() {
        running = true
        reschedule()
    }

    func stop() {
        running = false
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }

    /// Re-creates all loops (after config changes, wake or reconnect), staggering first runs.
    func reschedule() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        guard running, !state.offline else { return }
        let active: [Monitor] = state.monitors.filter { !$0.paused }
        let step: TimeInterval = active.isEmpty ? 0 : Scheduler.staggerWindow / Double(active.count)
        for (index, monitor) in active.enumerated() {
            tasks[monitor.id] = loop(monitor.id, initialDelay: Double(index) * step + Double.random(in: 0..<1))
        }
    }

    /// Restarts one monitor after it was added or edited (paused/removed monitors just stop).
    func restart(_ monitorID: UUID) {
        tasks[monitorID]?.cancel()
        tasks[monitorID] = nil
        guard running, !state.offline,
              let monitor = state.monitors.first(where: { $0.id == monitorID }), !monitor.paused else { return }
        tasks[monitorID] = loop(monitorID, initialDelay: 1)
    }

    /// Runs one check immediately, outside the normal schedule.
    func checkNow(_ monitorID: UUID) {
        guard let monitor = state.monitors.first(where: { $0.id == monitorID }) else { return }
        Task { await self.run(monitor) }
    }

    func checkAllNow() {
        let active: [Monitor] = state.monitors.filter { !$0.paused }
        for (index, monitor) in active.enumerated() {
            Task {
                // Small spacing so a manual refresh is not a burst either.
                try? await Task.sleep(nanoseconds: UInt64(index) * 300_000_000)
                await self.run(monitor)
            }
        }
    }

    private func loop(_ monitorID: UUID, initialDelay: TimeInterval) -> Task<Void, Never> {
        Task { [weak self] in
            var delay: TimeInterval = initialDelay
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled, let self,
                      let monitor = self.state.monitors.first(where: { $0.id == monitorID }), !monitor.paused else { return }
                await self.run(monitor)
                delay = monitor.interval
            }
        }
    }

    private func run(_ monitor: Monitor) async {
        let result: CheckResult = await Checkers.check(monitor)
        // Results that arrive after going offline or a config change are dropped.
        guard !state.offline, let current = state.monitors.first(where: { $0.id == monitor.id }), !current.paused else { return }
        history.insert(result)
        let events: [StatusEvent] = engine.process(result, monitor: current)
        for event in events {
            switch event {
            case .needsConfirmation:
                // Restart this monitor's loop so the next check is the confirmation, 30 s from now.
                if running && !state.offline {
                    tasks[monitor.id]?.cancel()
                    tasks[monitor.id] = loop(monitor.id, initialDelay: Scheduler.confirmationDelay)
                }
            case .wentDown, .recovered, .sslExpiring:
                notifier.post(event, monitor: current)
            }
        }
    }
}
