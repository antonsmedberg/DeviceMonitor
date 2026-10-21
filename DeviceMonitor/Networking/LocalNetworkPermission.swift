import Foundation
import Network
import UIKit

/// Deliberately triggers the Local Network privacy alert (TN3179) and exposes the Settings deep link.
nonisolated enum LocalNetworkPermission {
    /// Sends one UDP datagram to a random link-local IPv6 address on each local interface.
    /// This is enough for iOS to show the alert; the datagram itself is discarded.
    static func triggerPrompt() async {
        let interfaces = LocalInterfaceEnumerator.ipv4Interfaces().map(\.name)
        let names = interfaces.isEmpty ? ["en0"] : Array(Set(interfaces)).sorted()
        let queue = DispatchQueue(label: "eu.smedberg.DeviceMonitor.lnp", qos: .utility)

        await withTaskGroup(of: Void.self) { group in
            for name in names {
                group.addTask {
                    let suffix = String(format: "%04x:%04x", UInt16.random(in: 1...0xFFFF), UInt16.random(in: 1...0xFFFF))
                    await nudge(host: "fe80::\(suffix)%\(name)", queue: queue)
                }
            }
        }
    }

    private static func nudge(host: String, queue: DispatchQueue) async {
        guard let port = NWEndpoint.Port(rawValue: 9) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .udp)
        let gate = ResumeGate()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let finish: @Sendable () -> Void = {
                guard gate.claim() else { return }
                connection.cancel()
                continuation.resume()
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: Data([0]), completion: .contentProcessed { _ in finish() })
                case .failed, .cancelled:
                    finish()
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 1.0) { finish() }
        }
    }

    @MainActor
    static func settingsURL() -> URL? {
        URL(string: UIApplication.openSettingsURLString)
    }
}
