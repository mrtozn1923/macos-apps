import Foundation
import Network

enum TCPChecker {
    static func check(_ monitor: Monitor) async -> CheckResult {
        let host: String = monitor.host.trimmingCharacters(in: .whitespaces)
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: monitor.port)), monitor.port > 0 else {
            return .failure(monitor.id, L("Invalid port"))
        }
        let parameters: NWParameters = NWParameters.tcp
        if let options = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            options.connectionTimeout = monitor.timeoutSeconds
        }
        let connection: NWConnection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        let queue: DispatchQueue = DispatchQueue(label: "com.mertozen.nabiztut.tcp")
        let id: UUID = monitor.id
        let timeout: Int = monitor.timeoutSeconds

        return await withCheckedContinuation { (continuation: CheckedContinuation<CheckResult, Never>) in
            let once: OnceBox = OnceBox()
            let start: DispatchTime = DispatchTime.now()

            @Sendable func finish(_ result: CheckResult) {
                guard once.claim() else { return }
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(CheckResult(monitorID: id, date: Date(), ok: true, statusCode: nil,
                                       latencyMs: max(1, Checkers.elapsedMs(since: start)), error: nil, certExpiry: nil))
                case .failed(let error):
                    finish(.failure(id, reason(error)))
                case .waiting(let error):
                    // "Waiting" means the attempt failed and would be retried later; treat it as a failure.
                    finish(.failure(id, reason(error)))
                default:
                    break
                }
            }
            queue.asyncAfter(deadline: .now() + .seconds(timeout)) {
                finish(.failure(id, L("Timed out")))
            }
            connection.start(queue: queue)
        }
    }

    private static func reason(_ error: NWError) -> String {
        switch error {
        case .posix(let code) where code == .ECONNREFUSED: return L("Connection refused")
        case .posix(let code) where code == .ETIMEDOUT: return L("Timed out")
        case .posix(let code) where code == .EHOSTUNREACH || code == .ENETUNREACH: return L("Host unreachable")
        case .dns: return L("Host not found (DNS)")
        default: return error.localizedDescription
        }
    }
}

/// Guards a continuation against being resumed twice.
final class OnceBox: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var done: Bool = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
