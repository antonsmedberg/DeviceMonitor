import Foundation
import Network

/// Secondary probe for devices that drop TCP: a unicast mDNS query to port 5353.
/// Any reply proves the host is up; an ICMP port-unreachable surfaces as ECONNREFUSED, which also counts.
actor UDPProbe: HostProbing {
    nonisolated let kind: ProbeKind = .udp

    private let queue = DispatchQueue(label: "eu.smedberg.DeviceMonitor.udp", qos: .utility, attributes: .concurrent)

    init() {}

    func probe(host: String, port: UInt16?, timeoutSeconds: Double) async -> ProbeResult {
        let timestamp = Date()
        let targetPort = port ?? 5353
        let outcome = await Self.exchange(host: host, port: targetPort, payload: Self.mdnsServicesQuery, timeoutSeconds: timeoutSeconds, queue: queue)
        return ProbeResult(host: host, port: targetPort, kind: .udp, outcome: outcome, timestamp: timestamp)
    }

    nonisolated static let mdnsServicesQuery: Data = {
        var data = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        for label in ["_services", "_dns-sd", "_udp", "local"] {
            data.append(UInt8(label.utf8.count))
            data.append(contentsOf: Array(label.utf8))
        }
        data.append(0)
        data.append(contentsOf: [0x00, 0x0C, 0x80, 0x01])
        return data
    }()

    /// NetBIOS node status request for the wildcard name.
    nonisolated static let netbiosStatusQuery: Data = {
        var data = Data([0x44, 0x4E, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20])
        data.append(contentsOf: Array("CKAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA".utf8))
        data.append(contentsOf: [0x00, 0x00, 0x21, 0x00, 0x01])
        return data
    }()

    nonisolated static func exchange(host: String, port: UInt16, payload: Data, timeoutSeconds: Double, queue: DispatchQueue) async -> ProbeOutcome {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return .unreachable(code: 22) }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        let gate = ResumeGate()
        let start = DispatchTime.now()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ProbeOutcome, Never>) in
                let finish: @Sendable (ProbeOutcome) -> Void = { outcome in
                    guard gate.claim() else { return }
                    connection.cancel()
                    continuation.resume(returning: outcome)
                }

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.send(content: payload, completion: .contentProcessed { error in
                            if let error {
                                finish(ProbeSupport.outcome(for: error, elapsedMilliseconds: ProbeSupport.elapsedMilliseconds(since: start)))
                                return
                            }
                            connection.receiveMessage { data, _, _, error in
                                if let error {
                                    finish(ProbeSupport.outcome(for: error, elapsedMilliseconds: ProbeSupport.elapsedMilliseconds(since: start)))
                                } else if data != nil {
                                    finish(.reachable(latencyMilliseconds: ProbeSupport.elapsedMilliseconds(since: start)))
                                } else {
                                    finish(.timedOut)
                                }
                            }
                        })
                    case .failed(let error):
                        finish(ProbeSupport.outcome(for: error, elapsedMilliseconds: ProbeSupport.elapsedMilliseconds(since: start)))
                    case .waiting(let error):
                        if connection.currentPath?.unsatisfiedReason == .localNetworkDenied {
                            finish(.permissionDenied)
                            return
                        }
                        let mapped = ProbeSupport.outcome(for: error, elapsedMilliseconds: ProbeSupport.elapsedMilliseconds(since: start))
                        if mapped.indicatesHostUp {
                            finish(mapped)
                        } else if case .unreachable = mapped {
                            finish(mapped)
                        }
                    case .cancelled:
                        finish(.timedOut)
                    default:
                        break
                    }
                }

                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeoutSeconds + 0.25) {
                    finish(.timedOut)
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }
}
