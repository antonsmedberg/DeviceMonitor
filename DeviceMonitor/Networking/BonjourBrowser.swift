import Foundation
import Network
import dnssd
import os

nonisolated struct ResolvedEndpoint: Sendable, Hashable {
    let host: String
    let port: UInt16

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
}

/// Browses every declared Bonjour type and resolves services to addresses.
actor BonjourBrowser {
    private let serviceTypes: [String]
    private let queue = DispatchQueue(label: "eu.smedberg.DeviceMonitor.bonjour", qos: .utility)
    private let stream: AsyncStream<DiscoveryEvent>
    private let continuation: AsyncStream<DiscoveryEvent>.Continuation
    private var browsers: [String: NWBrowser] = [:]
    private var isRunning = false

    init(serviceTypes: [String] = BonjourServiceCatalog.declaredTypes) {
        self.serviceTypes = serviceTypes
        let (stream, continuation) = AsyncStream.makeStream(of: DiscoveryEvent.self, bufferingPolicy: .unbounded)
        self.stream = stream
        self.continuation = continuation
    }

    /// Single-consumer stream of discovery events.
    func events() -> AsyncStream<DiscoveryEvent> {
        stream
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let continuation = self.continuation
        let queue = self.queue

        for type in serviceTypes {
            let parameters = NWParameters()
            parameters.includePeerToPeer = false
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: parameters)

            browser.stateUpdateHandler = { state in
                switch state {
                case .failed(let error):
                    AppLog.discovery.error("Browser for \(type, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    continuation.yield(.failed(type: type, message: error.localizedDescription))
                case .waiting(let error):
                    if case .dns(let code) = error, Int(code) == -65570 {
                        continuation.yield(.permissionDenied)
                    }
                default:
                    break
                }
            }

            browser.browseResultsChangedHandler = { _, changes in
                for change in changes {
                    switch change {
                    case .added(let result):
                        BonjourBrowser.publish(result, added: true, continuation: continuation, queue: queue)
                    case .removed(let result):
                        BonjourBrowser.publish(result, added: false, continuation: continuation, queue: queue)
                    case .changed(_, let result, let flags):
                        // TXT updates (playback state and the like) need no new connection; only a
                        // new interface can mean a new address.
                        if flags.contains(.interfaceAdded) {
                            BonjourBrowser.publish(result, added: true, continuation: continuation, queue: queue)
                        }
                    case .identical:
                        break
                    @unknown default:
                        break
                    }
                }
            }

            browser.start(queue: queue)
            browsers[type] = browser
        }
    }

    func stop() {
        for browser in browsers.values {
            browser.cancel()
        }
        browsers.removeAll()
        isRunning = false
    }

    nonisolated private static func publish(_ result: NWBrowser.Result, added: Bool, continuation: AsyncStream<DiscoveryEvent>.Continuation, queue: DispatchQueue) {
        guard case .service(let name, let type, let domain, let interface) = result.endpoint else { return }
        var txt: [String: String] = [:]
        if case .bonjour(let record) = result.metadata {
            txt = BonjourServiceCatalog.parseTXT(record)
        }
        let service = DiscoveredService(type: type, name: name, port: BonjourServiceCatalog.port(for: type), txt: txt)

        guard added else {
            continuation.yield(.serviceRemoved(service: service))
            return
        }

        let endpoint = result.endpoint
        let interfaceIndex = UInt32(exactly: interface?.index ?? 0) ?? 0
        Task.detached(priority: .utility) {
            async let address = BonjourResolver.resolveHost(of: endpoint, timeoutSeconds: 4, queue: queue)
            async let target = SRVHostLookup.hostTarget(name: name, type: type, domain: domain, interfaceIndex: interfaceIndex, timeoutSeconds: 4, queue: queue)
            let resolved = await address
            let hostname = await target
            let resolvedService = DiscoveredService(type: type, name: name, port: resolved?.port ?? service.port, txt: txt)
            continuation.yield(.serviceAdded(service: resolvedService, host: resolved?.host, hostname: hostname))
        }
    }
}

/// Resolves a Bonjour service endpoint to a concrete address by opening a TCP connection
/// and reading the remote endpoint of the chosen path. IPv4 is preferred.
nonisolated enum BonjourResolver {
    static func resolveHost(of endpoint: NWEndpoint, timeoutSeconds: Double, queue: DispatchQueue) async -> ResolvedEndpoint? {
        let parameters = NWParameters.tcp
        if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.connectionTimeout = max(1, Int(timeoutSeconds.rounded(.up)))
        }
        if let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }
        parameters.serviceClass = .background

        let connection = NWConnection(to: endpoint, using: parameters)
        let gate = ResumeGate()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ResolvedEndpoint?, Never>) in
                let finish: @Sendable (ResolvedEndpoint?) -> Void = { value in
                    guard gate.claim() else { return }
                    connection.cancel()
                    continuation.resume(returning: value)
                }
                // A connected path's remote endpoint is always an address; the hostname comes from
                // the SRV record (`SRVHostLookup`), which Network framework does not expose.
                let readRemote: @Sendable () -> ResolvedEndpoint? = {
                    guard let remote = connection.currentPath?.remoteEndpoint,
                          case .hostPort(let host, let port) = remote else { return nil }
                    return ResolvedEndpoint(host: ProbeSupport.hostString(host), port: port.rawValue)
                }

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        finish(readRemote())
                    case .waiting(let error):
                        if case .posix(let code) = error, code == .ECONNREFUSED {
                            finish(readRemote())
                        } else if connection.currentPath?.unsatisfiedReason == .localNetworkDenied {
                            finish(nil)
                        }
                    case .failed:
                        finish(readRemote())
                    case .cancelled:
                        finish(nil)
                    default:
                        break
                    }
                }

                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                    finish(readRemote())
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }
}

/// Reads a service's SRV target ("NAS.local."), the device's mDNS hostname, with DNS‑SD.
/// Network framework resolves services only to addresses, and the hostname is the identity that
/// ties all of one device's services together and matches a device the user added by name.
nonisolated final class SRVHostLookup: @unchecked Sendable {
    // Touched only on `queue`, which must be serial; that is what makes this class Sendable.
    private let queue: DispatchQueue
    private var reference: DNSServiceRef?
    private var continuation: CheckedContinuation<String?, Never>?

    private init(queue: DispatchQueue) {
        self.queue = queue
    }

    /// The host target, or nil when the lookup fails or takes longer than `timeoutSeconds`.
    static func hostTarget(name: String, type: String, domain: String, interfaceIndex: UInt32, timeoutSeconds: Double, queue: DispatchQueue) async -> String? {
        let lookup = SRVHostLookup(queue: queue)
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            queue.async {
                lookup.start(name: name, type: type, domain: domain, interfaceIndex: interfaceIndex, timeoutSeconds: timeoutSeconds, continuation: continuation)
            }
        }
    }

    /// On `queue`.
    private func start(name: String, type: String, domain: String, interfaceIndex: UInt32, timeoutSeconds: Double, continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
        // The callback holds this object until `finish` releases it.
        let retained = Unmanaged.passRetained(self)
        var created: DNSServiceRef?
        let error = DNSServiceResolve(
            &created,
            0,
            interfaceIndex,
            name, type, domain,
            { _, _, _, errorCode, _, target, _, _, _, pointer in
                guard let pointer else { return }
                let lookup = Unmanaged<SRVHostLookup>.fromOpaque(pointer).takeUnretainedValue()
                lookup.finish(errorCode == 0 ? target.map { String(cString: $0) } : nil)
            },
            retained.toOpaque()
        )
        guard error == 0, let serviceRef = created else {
            retained.release()
            finish(nil)
            return
        }
        guard DNSServiceSetDispatchQueue(serviceRef, queue) == 0 else {
            DNSServiceRefDeallocate(serviceRef)
            retained.release()
            finish(nil)
            return
        }
        reference = serviceRef
        queue.asyncAfter(deadline: .now() + timeoutSeconds) { [self] in
            finish(nil)
        }
    }

    /// On `queue`. Resumes once; later calls (the timeout after an answer) do nothing.
    private func finish(_ hostTarget: String?) {
        if let reference {
            self.reference = nil
            DNSServiceRefDeallocate(reference)
            Unmanaged.passUnretained(self).release()
        }
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: hostTarget)
    }
}
