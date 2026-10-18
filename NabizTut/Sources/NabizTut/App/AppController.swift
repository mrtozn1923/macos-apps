import AppKit

/// Owns the app's services and is the single entry point for user actions.
@MainActor
final class AppController {
    static let maintenanceInterval: TimeInterval = 6 * 3600

    let state: AppState = AppState()
    let store: MonitorStore = MonitorStore()
    let history: HistoryRepository = HistoryRepository()
    let notifier: Notifier = Notifier()
    private(set) lazy var engine: StatusEngine = StatusEngine(state: state, history: history)
    private(set) lazy var scheduler: Scheduler = Scheduler(state: state, engine: engine, history: history, notifier: notifier)
    private let network: NetworkWatcher = NetworkWatcher()
    private let sleep: SleepWatcher = SleepWatcher()
    private var maintenanceTimer: Timer?

    var openDetail: ((UUID) -> Void)?
    var openSettings: ((SettingsRoute) -> Void)?

    func start() {
        store.load()
        state.monitors = store.monitors
        history.closeDanglingIncidents()
        history.maintain()
        for monitor in state.monitors { engine.preload(monitor) }

        notifier.requestAuthorization()

        network.onChange = { [weak self] online in self?.setOnline(online) }
        network.start()
        sleep.onSleep = { [weak self] in self?.suspend() }
        sleep.onWake = { [weak self] in self?.scheduler.start() }
        sleep.start()

        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: AppController.maintenanceInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.history.maintain() }
        }
        scheduler.start()

        if let problem = store.loadProblem {
            let alert: NSAlert = NSAlert()
            alert.messageText = L("Monitor list could not be loaded")
            alert.informativeText = problem
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: - Monitor editing

    func save(_ monitor: Monitor) {
        let previous: Monitor? = state.monitors.first { $0.id == monitor.id }
        store.upsert(monitor)
        state.monitors = store.monitors
        if let previous, AppController.checkChanged(previous, monitor) || previous.paused != monitor.paused {
            closeOpenIncident(monitor.id)
            engine.reset(monitor.id)
            engine.preload(monitor)
        } else if previous == nil {
            engine.preload(monitor)
        }
        scheduler.restart(monitor.id)
    }

    func delete(_ id: UUID) {
        store.delete(id)
        state.monitors = store.monitors
        state.statuses[id] = nil
        history.deleteAll(monitorID: id)
        scheduler.restart(id)
    }

    func setPaused(_ id: UUID, _ paused: Bool) {
        guard var monitor = state.monitors.first(where: { $0.id == id }) else { return }
        monitor.paused = paused
        save(monitor)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        store.move(fromOffsets: source, toOffset: destination)
        state.monitors = store.monitors
    }

    func refreshAll() {
        scheduler.checkAllNow()
    }

    /// One-off check for the settings form; nothing is stored.
    func test(_ monitor: Monitor) async -> CheckResult {
        await Checkers.check(monitor)
    }

    // MARK: - System state

    private func setOnline(_ online: Bool) {
        guard state.offline == online else { return }
        if online {
            state.offline = false
            scheduler.start()
        } else {
            suspend()
            state.offline = true
        }
    }

    /// Stops checking and ends open outages, so sleep or offline time never counts as downtime.
    private func suspend() {
        scheduler.stop()
        for monitor in state.monitors where state.status(for: monitor.id).state == .down {
            closeOpenIncident(monitor.id)
        }
        for monitor in state.monitors {
            engine.reset(monitor.id)
            engine.preload(monitor)
        }
    }

    private func closeOpenIncident(_ id: UUID) {
        if state.status(for: id).state == .down {
            history.closeIncident(monitorID: id, end: Date())
        }
    }

    /// True when a change affects how the monitor is checked (so its live status must restart).
    private static func checkChanged(_ a: Monitor, _ b: Monitor) -> Bool {
        var x: Monitor = a
        var y: Monitor = b
        x.name = ""; y.name = ""
        x.notify = true; y.notify = true
        x.paused = false; y.paused = false
        x.sslWarnDays = 0; y.sslWarnDays = 0
        return x != y
    }
}
