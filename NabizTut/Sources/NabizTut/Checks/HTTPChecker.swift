import Foundation

enum HTTPChecker {
    private static let maxBodyBytes: Int = 1_048_576
    private static let maxRedirects: Int = 5

    static func check(_ monitor: Monitor) async -> CheckResult {
        guard let url = URL(string: monitor.url.trimmingCharacters(in: .whitespaces)) else {
            return .failure(monitor.id, L("Invalid address"))
        }
        // Skip downloading the page when nothing in it is needed.
        let canUseHead: Bool = monitor.method == .get && monitor.keyword.isEmpty
        var result: CheckResult = await perform(monitor, url: url, method: canUseHead ? .head : monitor.method)
        if canUseHead, let code = result.statusCode, code == 405 || code == 501 {
            result = await perform(monitor, url: url, method: .get)
        }
        return result
    }

    private static func perform(_ monitor: Monitor, url: URL, method: HTTPMethod) async -> CheckResult {
        let delegate: SessionDelegate = SessionDelegate(followRedirects: monitor.followRedirects, maxRedirects: maxRedirects)
        let timeout: TimeInterval = TimeInterval(monitor.timeoutSeconds)
        let configuration: URLSessionConfiguration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 5
        configuration.waitsForConnectivity = false
        let session: URLSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request: URLRequest = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.setValue(String.userAgent, forHTTPHeaderField: "User-Agent")
        for header in monitor.headers where !header.name.trimmingCharacters(in: .whitespaces).isEmpty {
            request.setValue(header.value, forHTTPHeaderField: header.name.trimmingCharacters(in: .whitespaces))
        }
        if !monitor.body.isEmpty, method != .get, method != .head {
            request.httpBody = Data(monitor.body.utf8)
        }

        let start: DispatchTime = DispatchTime.now()
        do {
            let (bytes, response) = try await session.bytes(for: request)
            let latency: Int = max(1, Checkers.elapsedMs(since: start))
            guard let http = response as? HTTPURLResponse else {
                return .failure(monitor.id, L("Invalid server response"), latencyMs: latency, certExpiry: delegate.certExpiry)
            }
            let code: Int = http.statusCode
            let rule: StatusCodeRule = StatusCodeRule(monitor.expectedStatus) ?? StatusCodeRule(Monitor.defaultExpectedStatus)!
            guard rule.matches(code) else {
                let phrase: String = HTTPURLResponse.localizedString(forStatusCode: code).capitalized
                return .failure(monitor.id, L("HTTP %ld %@", code, phrase), statusCode: code,
                                latencyMs: latency, certExpiry: delegate.certExpiry)
            }

            let keyword: String = monitor.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            if !keyword.isEmpty && method != .head {
                var data: Data = Data()
                data.reserveCapacity(64 * 1024)
                for try await byte in bytes {
                    data.append(byte)
                    if data.count >= maxBodyBytes { break }
                }
                let body: String = String(decoding: data, as: UTF8.self)
                let found: Bool = body.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                if monitor.keywordMode == .contains && !found {
                    return .failure(monitor.id, L("Keyword “%@” not found", keyword), statusCode: code,
                                    latencyMs: latency, certExpiry: delegate.certExpiry)
                }
                if monitor.keywordMode == .notContains && found {
                    return .failure(monitor.id, L("Unwanted keyword “%@” found", keyword), statusCode: code,
                                    latencyMs: latency, certExpiry: delegate.certExpiry)
                }
            }
            return CheckResult(monitorID: monitor.id, date: Date(), ok: true, statusCode: code, latencyMs: latency,
                               error: nil, certExpiry: delegate.certExpiry)
        } catch {
            if let expiry = delegate.certExpiry, expiry < Date() {
                return .failure(monitor.id, L("SSL certificate expired on %@", expiry.formatted(date: .abbreviated, time: .omitted)),
                                certExpiry: expiry)
            }
            return .failure(monitor.id, Checkers.reason(for: error), certExpiry: delegate.certExpiry)
        }
    }
}

/// Captures the server certificate and enforces the redirect policy.
private final class SessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private let followRedirects: Bool
    private let maxRedirects: Int
    private var redirects: Int = 0
    private var _certExpiry: Date?

    var certExpiry: Date? {
        lock.lock(); defer { lock.unlock() }
        return _certExpiry
    }

    init(followRedirects: Bool, maxRedirects: Int) {
        self.followRedirects = followRedirects
        self.maxRedirects = maxRedirects
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock()
        redirects += 1
        let allowed: Bool = followRedirects && redirects <= maxRedirects
        lock.unlock()
        // Returning nil delivers the 3xx response itself, which is then checked against the expected codes.
        completionHandler(allowed ? request : nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            let expiry: Date? = CertificateInspector.leafExpiry(trust)
            lock.lock()
            if _certExpiry == nil { _certExpiry = expiry }
            lock.unlock()
        }
        // Default handling keeps normal certificate validation: invalid certificates fail the check.
        completionHandler(.performDefaultHandling, nil)
    }
}
