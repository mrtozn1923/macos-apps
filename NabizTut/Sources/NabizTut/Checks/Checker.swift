import Foundation

/// The only place that performs network checks.
enum Checkers {
    static func check(_ monitor: Monitor) async -> CheckResult {
        switch monitor.kind {
        case .http: return await HTTPChecker.check(monitor)
        case .ping: return await PingChecker.check(monitor)
        case .tcp: return await TCPChecker.check(monitor)
        }
    }

    static func elapsedMs(since start: DispatchTime) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }

    /// Maps URLError / POSIX errors to short, user-facing reasons.
    static func reason(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return L("Timed out")
            case .cannotFindHost, .dnsLookupFailed: return L("Host not found (DNS)")
            case .cannotConnectToHost: return L("Connection refused")
            case .networkConnectionLost: return L("Connection lost")
            case .notConnectedToInternet: return L("No internet connection")
            case .serverCertificateHasBadDate: return L("SSL certificate expired or not yet valid")
            case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                return L("SSL certificate is not trusted")
            case .secureConnectionFailed: return L("Secure connection failed")
            case .httpTooManyRedirects: return L("Too many redirects")
            case .badServerResponse: return L("Invalid server response")
            default: return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

extension String {
    static let userAgent: String = {
        let version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "NabizTut/\(version) (+https://github.com/mrtozn1923/macos-apps)"
    }()
}
