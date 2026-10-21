import Foundation
import Network
import Synchronization

/// Watches the network and reports whether the local network is reachable, its gateways and
/// local-network denial.
///
/// The LAN is judged from Wi‑Fi and Ethernet paths, not from the default route: when the home
/// internet is down, iOS keeps Wi‑Fi joined but sends the default route over cellular, and the
/// devices on the Wi‑Fi are still reachable (and worth checking) exactly then.
actor NetworkPathObserver {
    private let generalMonitor = NWPathMonitor()
    private let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let wiredMonitor = NWPathMonitor(requiredInterfaceType: .wiredEthernet)
    private let queue = DispatchQueue(label: "eu.smedberg.DeviceMonitor.path", qos: .utility)
    private let stream: AsyncStream<NetworkPathStatus>
    private let continuation: AsyncStream<NetworkPathStatus>.Continuation
    private var started = false

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: NetworkPathStatus.self, bufferingPolicy: .bufferingNewest(1))
        self.stream = stream
        self.continuation = continuation
    }

    /// Single-consumer stream of path changes. Starts monitoring on first call.
    func statuses() -> AsyncStream<NetworkPathStatus> {
        start()
        return stream
    }

    func start() {
        guard !started else { return }
        started = true
        let continuation = self.continuation
        let readings = PathReadings()
        generalMonitor.pathUpdateHandler = { path in
            if let status = readings.record(NetworkPathObserver.reading(from: path), from: .general) {
                continuation.yield(status)
            }
        }
        wifiMonitor.pathUpdateHandler = { path in
            if let status = readings.record(NetworkPathObserver.reading(from: path), from: .wifi) {
                continuation.yield(status)
            }
        }
        wiredMonitor.pathUpdateHandler = { path in
            if let status = readings.record(NetworkPathObserver.reading(from: path), from: .wired) {
                continuation.yield(status)
            }
        }
        generalMonitor.start(queue: queue)
        wifiMonitor.start(queue: queue)
        wiredMonitor.start(queue: queue)
    }

    nonisolated static func reading(from path: NWPath) -> PathReading {
        let localInterface = path.availableInterfaces.first { $0.type == .wifi || $0.type == .wiredEthernet }
        let gateways = path.gateways.compactMap { endpoint -> String? in
            if case .hostPort(let host, _) = endpoint {
                return ProbeSupport.hostString(host)
            }
            return nil
        }
        return PathReading(
            isSatisfied: path.status == .satisfied,
            interfaceName: localInterface?.name,
            gatewayHosts: gateways,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            isLocalNetworkDenied: path.unsatisfiedReason == .localNetworkDenied
        )
    }

    /// The LAN is up when the Wi‑Fi path (or else the Ethernet path) is satisfied, wherever the
    /// default route goes. Cost and constraints describe the default route.
    nonisolated static func combine(general: PathReading, wifi: PathReading, wired: PathReading) -> NetworkPathStatus {
        let lan: PathReading? = wifi.isSatisfied ? wifi : (wired.isSatisfied ? wired : nil)
        return NetworkPathStatus(
            isSatisfied: general.isSatisfied || lan != nil,
            isWiFi: lan != nil,
            isExpensive: general.isExpensive,
            isConstrained: general.isConstrained,
            wifiInterfaceName: lan?.interfaceName,
            gatewayHosts: lan?.gatewayHosts ?? [],
            isLocalNetworkDenied: general.isLocalNetworkDenied || wifi.isLocalNetworkDenied || wired.isLocalNetworkDenied
        )
    }
}

/// What one path monitor last reported.
nonisolated struct PathReading: Sendable, Hashable {
    let isSatisfied: Bool
    let interfaceName: String?
    let gatewayHosts: [String]
    let isExpensive: Bool
    let isConstrained: Bool
    let isLocalNetworkDenied: Bool

    init(isSatisfied: Bool, interfaceName: String?, gatewayHosts: [String], isExpensive: Bool, isConstrained: Bool, isLocalNetworkDenied: Bool) {
        self.isSatisfied = isSatisfied
        self.interfaceName = interfaceName
        self.gatewayHosts = gatewayHosts
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.isLocalNetworkDenied = isLocalNetworkDenied
    }
}

/// The latest reading of each monitor. Nothing is reported until the general and Wi‑Fi monitors
/// have answered once, so the first status cannot flip from "not on Wi‑Fi" to "on Wi‑Fi" and trigger
/// a needless check. Ethernet counts as down until its monitor says otherwise.
nonisolated final class PathReadings: Sendable {
    nonisolated enum Source: Sendable {
        case general, wifi, wired
    }

    nonisolated struct Latest: Sendable {
        var general: PathReading?
        var wifi: PathReading?
        var wired: PathReading?
    }

    private let latest = Mutex(Latest())

    init() {}

    /// Stores a reading and returns the combined status once the general and Wi‑Fi monitors have reported.
    func record(_ reading: PathReading, from source: Source) -> NetworkPathStatus? {
        latest.withLock { state in
            switch source {
            case .general: state.general = reading
            case .wifi: state.wifi = reading
            case .wired: state.wired = reading
            }
            guard let general = state.general, let wifi = state.wifi else { return nil }
            let wired = state.wired ?? PathReading(isSatisfied: false, interfaceName: nil, gatewayHosts: [], isExpensive: false, isConstrained: false, isLocalNetworkDenied: false)
            return NetworkPathObserver.combine(general: general, wifi: wifi, wired: wired)
        }
    }
}
