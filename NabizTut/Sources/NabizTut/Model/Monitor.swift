import Foundation

enum MonitorKind: String, Codable, CaseIterable, Identifiable {
    case http
    case ping
    case tcp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .http: return "HTTP(S)"
        case .ping: return "Ping"
        case .tcp: return L("TCP port")
        }
    }
}

enum HTTPMethod: String, Codable, CaseIterable, Identifiable {
    case get = "GET"
    case head = "HEAD"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"

    var id: String { rawValue }
}

enum KeywordMode: String, Codable, CaseIterable, Identifiable {
    case contains
    case notContains

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contains: return L("contains")
        case .notContains: return L("does not contain")
        }
    }
}

struct HeaderField: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    /// Empty in JSON when `secret` is true; the real value lives in the Keychain.
    var value: String = ""
    var secret: Bool = false
}

/// One thing to watch. Persisted as JSON by `MonitorStore`.
struct Monitor: Codable, Identifiable, Hashable {
    static let intervals: [Int] = [1, 2, 5, 10, 15, 30, 60]
    static let defaultExpectedStatus: String = "200-399"

    var id: UUID = UUID()
    var name: String = ""
    var kind: MonitorKind = .http
    var url: String = "https://"
    var host: String = ""
    var port: Int = 443
    var intervalMinutes: Int = 5
    var timeoutSeconds: Int = 10
    var method: HTTPMethod = .get
    var headers: [HeaderField] = []
    var body: String = ""
    var expectedStatus: String = Monitor.defaultExpectedStatus
    var keyword: String = ""
    var keywordMode: KeywordMode = .contains
    var followRedirects: Bool = true
    var sslWarnDays: Int = 14
    var notify: Bool = true
    var paused: Bool = false

    /// Human-readable target shown under the name.
    var target: String {
        switch kind {
        case .http: return url
        case .ping: return host
        case .tcp: return "\(host):\(port)"
        }
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? target : name
    }

    var interval: TimeInterval { TimeInterval(max(1, intervalMinutes) * 60) }

    /// Returns a user-facing problem, or nil when the monitor can be saved.
    var validationError: String? {
        switch kind {
        case .http:
            guard let parsed = URL(string: url.trimmingCharacters(in: .whitespaces)),
                  let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  parsed.host?.isEmpty == false else {
                return L("Enter a valid http:// or https:// address.")
            }
            if StatusCodeRule(expectedStatus) == nil {
                return L("Expected status codes are invalid. Example: 200-299, 301")
            }
        case .ping, .tcp:
            if host.trimmingCharacters(in: .whitespaces).isEmpty {
                return L("Enter a host name or IP address.")
            }
            if kind == .tcp && !(1...65535).contains(port) {
                return L("Port must be between 1 and 65535.")
            }
        }
        return nil
    }

    // Decode leniently so older/hand-edited JSON keeps working.
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d: Monitor = Monitor()
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? d.id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        kind = try c.decodeIfPresent(MonitorKind.self, forKey: .kind) ?? d.kind
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? d.url
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? d.host
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? d.port
        let rawInterval: Int = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? d.intervalMinutes
        intervalMinutes = Monitor.intervals.contains(rawInterval) ? rawInterval : max(1, rawInterval)
        timeoutSeconds = min(60, max(1, try c.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? d.timeoutSeconds))
        method = try c.decodeIfPresent(HTTPMethod.self, forKey: .method) ?? d.method
        headers = try c.decodeIfPresent([HeaderField].self, forKey: .headers) ?? d.headers
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? d.body
        expectedStatus = try c.decodeIfPresent(String.self, forKey: .expectedStatus) ?? d.expectedStatus
        keyword = try c.decodeIfPresent(String.self, forKey: .keyword) ?? d.keyword
        keywordMode = try c.decodeIfPresent(KeywordMode.self, forKey: .keywordMode) ?? d.keywordMode
        followRedirects = try c.decodeIfPresent(Bool.self, forKey: .followRedirects) ?? d.followRedirects
        sslWarnDays = try c.decodeIfPresent(Int.self, forKey: .sslWarnDays) ?? d.sslWarnDays
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? d.notify
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? d.paused
    }
}
