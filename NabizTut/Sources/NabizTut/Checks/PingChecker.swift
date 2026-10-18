import Darwin
import Foundation

/// ICMP echo using an unprivileged datagram socket (no root needed on macOS). IPv4 only.
enum PingChecker {
    static func check(_ monitor: Monitor) async -> CheckResult {
        let host: String = monitor.host.trimmingCharacters(in: .whitespaces)
        let timeout: Int = monitor.timeoutSeconds
        let id: UUID = monitor.id
        return await Task.detached(priority: .utility) {
            ping(host: host, timeoutSeconds: timeout, monitorID: id)
        }.value
    }

    private static func ping(host: String, timeoutSeconds: Int, monitorID: UUID) -> CheckResult {
        guard let address = resolveIPv4(host) else {
            return .failure(monitorID, resolvesOnlyIPv6(host) ? L("IPv6-only host: ping is IPv4 only, try a TCP check")
                                                              : L("Host not found (DNS)"))
        }
        let fd: Int32 = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return .failure(monitorID, L("Could not open ICMP socket")) }
        defer { close(fd) }

        var tv: timeval = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let identifier: UInt16 = UInt16.random(in: 1...UInt16.max)
        let sequence: UInt16 = UInt16.random(in: 1...UInt16.max)
        var packet: [UInt8] = [8, 0, 0, 0,
                               UInt8(identifier >> 8), UInt8(identifier & 0xff),
                               UInt8(sequence >> 8), UInt8(sequence & 0xff)]
        packet += Array("NabizTut-ping-payload-0123456789".utf8)
        let sum: UInt16 = checksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xff)

        var destination: sockaddr_in = address
        let start: DispatchTime = DispatchTime.now()
        let sent: Int = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == packet.count else { return .failure(monitorID, L("Ping could not be sent")) }

        let deadline: DispatchTime = start + .seconds(timeoutSeconds)
        var buffer: [UInt8] = [UInt8](repeating: 0, count: 2048)
        while DispatchTime.now() < deadline {
            let received: Int = recv(fd, &buffer, buffer.count, 0)
            if received <= 0 { continue }
            // Darwin delivers the IPv4 header in front of the ICMP message on datagram ICMP sockets.
            let ipHeaderLength: Int = received >= 20 && buffer[0] >> 4 == 4 ? Int(buffer[0] & 0x0f) * 4 : 0
            guard received >= ipHeaderLength + 8 else { continue }
            let icmp: ArraySlice<UInt8> = buffer[ipHeaderLength..<received]
            let type: UInt8 = icmp[icmp.startIndex]
            let replySequence: UInt16 = UInt16(icmp[icmp.startIndex + 6]) << 8 | UInt16(icmp[icmp.startIndex + 7])
            if type == 0 && replySequence == sequence {
                return CheckResult(monitorID: monitorID, date: Date(), ok: true, statusCode: nil,
                                   latencyMs: max(1, Checkers.elapsedMs(since: start)), error: nil, certExpiry: nil)
            }
        }
        return .failure(monitorID, L("No ping reply (ICMP may be blocked, try a TCP check)"))
    }

    private static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index: Int = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count { sum += UInt32(bytes[index]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum)
    }

    private static func resolveIPv4(_ host: String) -> sockaddr_in? {
        var hints: addrinfo = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let info = result else { return nil }
        defer { freeaddrinfo(result) }
        return info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
    }

    private static func resolvesOnlyIPv6(_ host: String) -> Bool {
        var hints: addrinfo = addrinfo()
        hints.ai_family = AF_INET6
        var result: UnsafeMutablePointer<addrinfo>?
        let found: Bool = getaddrinfo(host, nil, &hints, &result) == 0
        if result != nil { freeaddrinfo(result) }
        return found
    }
}
