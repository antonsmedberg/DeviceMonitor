import Foundation
import Network
import Synchronization

/// Guarantees a continuation is resumed exactly once from competing callbacks.
nonisolated final class ResumeGate: Sendable {
    private let claimed = Mutex(false)

    init() {}

    /// Returns true for the first caller only.
    func claim() -> Bool {
        claimed.withLock { value in
            if value { return false }
            value = true
            return true
        }
    }
}

nonisolated enum ProbeSupport {
    static func elapsedMilliseconds(since start: DispatchTime) -> Double {
        let nanoseconds = DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds
        return Double(nanoseconds) / 1_000_000
    }

    /// Maps a Network framework error to a probe outcome. ECONNREFUSED means the host is up.
    static func outcome(for error: NWError, elapsedMilliseconds: Double) -> ProbeOutcome {
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNREFUSED:
                return .refused(latencyMilliseconds: elapsedMilliseconds)
            case .EHOSTUNREACH, .ENETUNREACH, .EHOSTDOWN, .ENETDOWN:
                return .unreachable(code: code.rawValue)
            case .ETIMEDOUT:
                return .timedOut
            default:
                return .unreachable(code: code.rawValue)
            }
        case .dns(let code):
            return .unreachable(code: code)
        default:
            return .timedOut
        }
    }

    static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address):
            return address.debugDescription
        case .ipv6(let address):
            let literal = address.debugDescription
            if let percent = literal.firstIndex(of: "%") {
                return String(literal[..<percent])
            }
            return literal
        case .name(let name, _):
            return name
        @unknown default:
            return "\(host)"
        }
    }
}
