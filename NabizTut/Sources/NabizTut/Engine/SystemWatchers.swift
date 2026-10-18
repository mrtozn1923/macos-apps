import AppKit
import Network

/// Reports whether the Mac has a usable network path.
@MainActor
final class NetworkWatcher {
    private let monitor: NWPathMonitor = NWPathMonitor()
    var onChange: ((_ online: Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online: Bool = path.status == .satisfied
            Task { @MainActor in self?.onChange?(online) }
        }
        monitor.start(queue: DispatchQueue(label: "com.mertozen.nabiztut.network"))
    }
}

/// Pauses work while the Mac sleeps and resumes shortly after wake.
@MainActor
final class SleepWatcher {
    static let wakeDelay: TimeInterval = 10

    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var wakeWork: DispatchWorkItem?

    func start() {
        let center: NotificationCenter = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.wakeWork?.cancel()
                self?.onSleep?()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let work: DispatchWorkItem = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated { self?.onWake?() }
                }
                self.wakeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + SleepWatcher.wakeDelay, execute: work)
            }
        })
    }
}
