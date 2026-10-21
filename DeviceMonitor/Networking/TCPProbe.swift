import Foundation
import Network
import os

/// Primary reachability probe: a real TCP connect. Refused connections still prove the host is up.
actor TCPProbe: HostProbing {
    nonisolated let kind: ProbeKind = .tcp

    /// Cheap ports that most LAN devices answer (or refuse) quickly.
    /// Web, secure web and SSH answer on most devices; a refused connection counts as "up" too.
    static let defaultPorts: [UInt16] = [80, 443, 22]

    private let queue = DispatchQueue(label: "eu.smedberg.DeviceMonitor.tcp", qos: .utility, attributes: .concurrent)

    init() {}

    func probe(host: String, port: UInt16?, timeoutSeconds: Double) async -> ProbeResult {
        let timestamp = Date()
        let ports = port.map { [$0] } ?? Self.defaultPorts
        let queue = self.queue

        let outcomes = await withTaskGroup(of: (UInt16, ProbeOutcome).self, returning: [(UInt16, ProbeOutcome)].self) { group in
            for candidate in ports {
                group.addTask {
                    let outcome = await Self.connect(host: host, port: candidate, timeoutSeconds: timeoutSeconds, queue: queue)
                    return (candidate, outcome)
                }
            }
            var collected: [(UInt16, ProbeOutcome)] = []
            for await entry in group {
                collected.append(entry)
                if entry.1.indicatesHostUp {
                    group.cancelAll()
                    break
                }
            }
            return collected
        }

        if let up = outcomes.first(where: { $0.1.indicatesHostUp }) {
            return ProbeResult(host: host, port: up.0, kind: .tcp, outcome: up.1, timestamp: timestamp)
        }
        if let denied = outcomes.first(where: { $0.1 == .permissionDenied }) {
            return ProbeResult(host: host, port: denied.0, kind: .tcp, outcome: .permissionDenied, timestamp: timestamp)
        }
        if let unreachable = outcomes.first(where: { if case .unreachable = $0.1 { return true } else { return false } }) {
            return ProbeResult(host: host, port: unreachable.0, kind: .tcp, outcome: unreachable.1, timestamp: timestamp)
        }
        return ProbeResult(host: host, port: ports.first, kind: .tcp, outcome: .timedOut, timestamp: timestamp)
    }

    nonisolated static func connect(host: String, port: UInt16, timeoutSeconds: Double, queue: DispatchQueue) async -> ProbeOutcome {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return .unreachable(code: 22) }

        let parameters = NWParameters.tcp
        if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.connectionTimeout = max(1, Int(timeoutSeconds.rounded(.up)))
            tcpOptions.noDelay = true
        }
        parameters.serviceClass = .background

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
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
                        finish(.reachable(latencyMilliseconds: ProbeSupport.elapsedMilliseconds(since: start)))
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
                        } else if case .timedOut = mapped {
                            finish(.timedOut)
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
