import Foundation
import Network

/// Sends a Wake-on-LAN magic packet as unicast UDP to the device's last known address.
/// Broadcast needs the multicast entitlement, so unicast is the sandbox-legal path: it works for
/// a few minutes after shutdown while the router still remembers the MAC address.
nonisolated enum WakeOnLANSender {
    static func send(mac: MACAddress, toHost host: String, port: UInt16 = 9, timeoutSeconds: Double = 2) async throws(DeviceMonitorError) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw DeviceMonitorError.wakeFailed("invalid port \(port)")
        }
        let packet = WakeOnLAN.magicPacket(for: mac)
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        let queue = DispatchQueue(label: "eu.smedberg.DeviceMonitor.wol", qos: .userInitiated)
        let gate = ResumeGate()

        let result: Result<Void, DeviceMonitorError> = await withCheckedContinuation { continuation in
            let finish: @Sendable (Result<Void, DeviceMonitorError>) -> Void = { value in
                guard gate.claim() else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: packet, completion: .contentProcessed { error in
                        if let error {
                            finish(.failure(.wakeFailed(error.localizedDescription)))
                        } else {
                            finish(.success(()))
                        }
                    })
                case .failed(let error):
                    finish(.failure(.wakeFailed(error.localizedDescription)))
                case .waiting(let error):
                    if connection.currentPath?.unsatisfiedReason == .localNetworkDenied {
                        finish(.failure(.localNetworkDenied))
                    } else if case .posix(let code) = error, code == .EHOSTUNREACH || code == .ENETUNREACH {
                        finish(.failure(.wakeFailed("the address is not reachable")))
                    }
                case .cancelled:
                    finish(.failure(.wakeFailed("cancelled")))
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                finish(.failure(.wakeFailed("timed out")))
            }
        }
        try result.get()
    }
}
