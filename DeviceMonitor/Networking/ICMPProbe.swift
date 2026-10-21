import Foundation
import Darwin
import os

/// Secondary probe: unprivileged ICMP echo over `SOCK_DGRAM`/`IPPROTO_ICMP`.
/// If the socket cannot be created the probe reports `.unsupported` and the engine stops using it.
actor ICMPProbe: HostProbing {
    nonisolated let kind: ProbeKind = .icmp

    private var supported = true
    private var sequence: UInt16 = 0
    private let identifier = UInt16(truncatingIfNeeded: ProcessInfo.processInfo.processIdentifier)
    private let queue = DispatchQueue(label: "eu.smedberg.DeviceMonitor.icmp", qos: .utility, attributes: .concurrent)

    init() {}

    func probe(host: String, port: UInt16?, timeoutSeconds: Double) async -> ProbeResult {
        let timestamp = Date()
        guard supported else {
            return ProbeResult(host: host, port: nil, kind: .icmp, outcome: .unsupported, timestamp: timestamp)
        }
        guard let address = IPv4Host(host) else {
            // Only IPv4 echo is implemented; other hosts are covered by TCP.
            return ProbeResult(host: host, port: nil, kind: .icmp, outcome: .unsupported, timestamp: timestamp)
        }

        sequence &+= 1
        let sequence = self.sequence
        let identifier = self.identifier

        let outcome: ProbeOutcome = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.ping(address: address, identifier: identifier, sequence: sequence, timeoutSeconds: timeoutSeconds))
            }
        }

        if case .unsupported = outcome {
            supported = false
            AppLog.probe.notice("ICMP sockets are not available; disabling ping probes")
        }
        return ProbeResult(host: host, port: nil, kind: .icmp, outcome: outcome, timestamp: timestamp)
    }

    nonisolated private static func ping(address: IPv4Host, identifier: UInt16, sequence: UInt16, timeoutSeconds: Double) -> ProbeOutcome {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return .unsupported }
        defer { close(fd) }

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_addr.s_addr = address.rawValue.bigEndian

        let packet = ICMPPacket.echoRequest(identifier: identifier, sequence: sequence, payload: Data(repeating: 0x44, count: 32))
        let start = DispatchTime.now()

        let sent = packet.withUnsafeBytes { buffer -> Int in
            withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(fd, buffer.baseAddress, buffer.count, 0, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        guard sent == packet.count else {
            let code = errno
            if code == EHOSTUNREACH || code == ENETUNREACH || code == EHOSTDOWN {
                return .unreachable(code: code)
            }
            if code == EPERM || code == EACCES {
                return .unsupported
            }
            return .timedOut
        }

        var buffer = [UInt8](repeating: 0, count: 1024)
        let deadline = DispatchTime.now() + timeoutSeconds

        while true {
            // One clock read per pass: reading it twice could pass the deadline in between and
            // wrap the subtraction into a poll of about 24 days.
            let now = DispatchTime.now()
            guard now < deadline else { break }
            let remainingNanoseconds = deadline.uptimeNanoseconds - now.uptimeNanoseconds
            let remainingMilliseconds = Int32(min(Double(Int32.max), Double(remainingNanoseconds) / 1_000_000))
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, max(1, remainingMilliseconds))
            if ready < 0 {
                if errno == EINTR { continue }
                return .timedOut
            }
            if ready == 0 { break }

            let received = recv(fd, &buffer, buffer.count, 0)
            if received < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                if errno == EHOSTUNREACH || errno == ENETUNREACH { return .unreachable(code: errno) }
                return .timedOut
            }
            if received == 0 { continue }

            let datagram = Data(buffer[0..<received])
            if ICMPPacket.isEchoReply(datagram, identifier: identifier, sequence: sequence) {
                return .reachable(latencyMilliseconds: ProbeSupport.elapsedMilliseconds(since: start))
            }
        }
        return .timedOut
    }
}
