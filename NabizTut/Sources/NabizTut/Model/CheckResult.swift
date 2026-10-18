import Foundation

/// Outcome of a single check.
struct CheckResult: Sendable {
    let monitorID: UUID
    let date: Date
    let ok: Bool
    let statusCode: Int?
    let latencyMs: Int?
    /// User-facing failure reason; nil when `ok`.
    let error: String?
    /// Leaf certificate expiry for HTTPS monitors.
    let certExpiry: Date?

    static func failure(_ monitorID: UUID, _ reason: String, statusCode: Int? = nil, latencyMs: Int? = nil,
                        certExpiry: Date? = nil, date: Date = Date()) -> CheckResult {
        CheckResult(monitorID: monitorID, date: date, ok: false, statusCode: statusCode, latencyMs: latencyMs,
                    error: reason, certExpiry: certExpiry)
    }
}
