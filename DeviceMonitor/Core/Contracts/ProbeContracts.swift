import Foundation

nonisolated enum ProbeKind: String, Sendable, Codable, Hashable, CaseIterable {
    case tcp, icmp, udp, bonjour, demo

    var title: String {
        switch self {
        case .tcp: return "TCP"
        case .icmp: return "Ping"
        case .udp: return "UDP"
        case .bonjour: return "Bonjour"
        case .demo: return "Demo"
        }
    }
}

/// The result of one probe attempt. Neutral outcomes never move the reachability state machine.
nonisolated enum ProbeOutcome: Sendable, Codable, Hashable {
    case reachable(latencyMilliseconds: Double)
    /// ECONNREFUSED or ICMP port-unreachable: nothing listens, but the host answered, so it is up.
    case refused(latencyMilliseconds: Double)
    case timedOut
    case unreachable(code: Int32)
    case permissionDenied
    case unsupported

    var indicatesHostUp: Bool {
        switch self {
        case .reachable, .refused: return true
        default: return false
        }
    }

    var isNeutral: Bool {
        switch self {
        case .permissionDenied, .unsupported: return true
        default: return false
        }
    }

    var latencyMilliseconds: Double? {
        switch self {
        case .reachable(let ms), .refused(let ms): return ms
        default: return nil
        }
    }
}

nonisolated struct ProbeResult: Sendable, Codable, Hashable {
    let host: String
    let port: UInt16?
    let kind: ProbeKind
    let outcome: ProbeOutcome
    let timestamp: Date

    init(host: String, port: UInt16?, kind: ProbeKind, outcome: ProbeOutcome, timestamp: Date) {
        self.host = host
        self.port = port
        self.kind = kind
        self.outcome = outcome
        self.timestamp = timestamp
    }
}

/// Implemented by actors. Must never throw: timeouts and denials are encoded in the outcome.
nonisolated protocol HostProbing: Sendable {
    var kind: ProbeKind { get }
    func probe(host: String, port: UInt16?, timeoutSeconds: Double) async -> ProbeResult
}

nonisolated struct DiscoveredHost: Sendable, Codable, Hashable, Identifiable {
    var id: String { host }
    let host: String
    var hostname: String?
    var macAddress: String?
    var services: [DiscoveredService]
    var probe: ProbeResult?

    init(host: String, hostname: String? = nil, macAddress: String? = nil, services: [DiscoveredService] = [], probe: ProbeResult? = nil) {
        self.host = host
        self.hostname = hostname
        self.macAddress = macAddress
        self.services = services
        self.probe = probe
    }
}

nonisolated enum DiscoveryEvent: Sendable, Hashable {
    case serviceAdded(service: DiscoveredService, host: String?, hostname: String?)
    case serviceRemoved(service: DiscoveredService)
    case permissionDenied
    case failed(type: String, message: String)
}

nonisolated struct ScanRequest: Sendable, Hashable {
    let subnet: IPv4Subnet
    var gatewayHosts: [String]
    var excludedHosts: Set<String>
    var timeoutSeconds: Double
    var maxDurationSeconds: Double

    init(subnet: IPv4Subnet, gatewayHosts: [String] = [], excludedHosts: Set<String> = [], timeoutSeconds: Double = 1.5, maxDurationSeconds: Double = 60) {
        self.subnet = subnet
        self.gatewayHosts = gatewayHosts
        self.excludedHosts = excludedHosts
        self.timeoutSeconds = timeoutSeconds
        self.maxDurationSeconds = maxDurationSeconds
    }

    /// What a probe adds to its timeout before it gives up (the connection fallback timer).
    static let probeOverheadSeconds = 0.25

    /// A time ceiling that still lets every host be tried once. Most addresses are empty, and an
    /// empty one only fails after each probe's timeout in turn (`perHostSeconds`), so the sweep
    /// takes about hosts ÷ concurrency × perHostSeconds. Never below a minute.
    static func durationCeiling(hostCount: Int, concurrency: Int, perHostSeconds: Double) -> Double {
        let sweep = Double(max(0, hostCount)) / Double(max(1, concurrency)) * max(0, perHostSeconds)
        return max(60, (sweep * 1.2).rounded(.up))
    }
}

nonisolated struct ScanProgress: Sendable, Hashable {
    let scanned: Int
    let total: Int
    let found: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(scanned) / Double(total))
    }

    init(scanned: Int, total: Int, found: Int) {
        self.scanned = scanned
        self.total = total
        self.found = found
    }
}

nonisolated enum ScanUpdate: Sendable, Hashable {
    case progress(ScanProgress)
    case found(DiscoveredHost)
    case permissionDenied
    case finished([DiscoveredHost])
}

nonisolated enum PortRisk: String, Sendable, Codable, Hashable, CaseIterable {
    case low, medium, high

    var title: String {
        switch self {
        case .low: return "Low risk"
        case .medium: return "Medium risk"
        case .high: return "High risk"
        }
    }

    var systemImage: String {
        switch self {
        case .low: return "checkmark.shield.fill"
        case .medium: return "exclamationmark.triangle.fill"
        case .high: return "exclamationmark.octagon.fill"
        }
    }
}

/// One probe of a manual ping burst. Diagnostic only: bursts never change a device's state.
nonisolated struct PingSample: Sendable, Hashable, Identifiable {
    let index: Int
    let outcome: ProbeOutcome
    let kind: ProbeKind

    var id: Int { index }

    init(index: Int, outcome: ProbeOutcome, kind: ProbeKind) {
        self.index = index
        self.outcome = outcome
        self.kind = kind
    }
}

/// Loss and latency over a ping burst.
nonisolated struct PingSummary: Sendable, Hashable {
    let sent: Int
    let received: Int
    let minimum: Double?
    let average: Double?
    let maximum: Double?

    init(samples: [PingSample]) {
        let latencies = samples.compactMap { $0.outcome.indicatesHostUp ? $0.outcome.latencyMilliseconds : nil }
        sent = samples.count
        received = samples.filter { $0.outcome.indicatesHostUp }.count
        minimum = latencies.min()
        maximum = latencies.max()
        average = latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)
    }

    /// 0…1 share of probes that got no answer.
    var loss: Double { sent == 0 ? 0 : Double(sent - received) / Double(sent) }
}

nonisolated struct PortScanResult: Sendable, Codable, Hashable, Identifiable {
    var id: UInt16 { port }
    let port: UInt16
    let isOpen: Bool
    let serviceName: String
    let risk: PortRisk

    init(port: UInt16, isOpen: Bool, serviceName: String, risk: PortRisk) {
        self.port = port
        self.isOpen = isOpen
        self.serviceName = serviceName
        self.risk = risk
    }
}

/// A device as the monitoring engine sees it.
nonisolated struct MonitoredTarget: Sendable, Hashable, Identifiable {
    let id: UUID
    var host: String
    var preferredPort: UInt16?
    var isGateway: Bool
    var tracker: ReachabilityTracker

    init(id: UUID, host: String, preferredPort: UInt16? = nil, isGateway: Bool = false, tracker: ReachabilityTracker = ReachabilityTracker()) {
        self.id = id
        self.host = host
        self.preferredPort = preferredPort
        self.isGateway = isGateway
        self.tracker = tracker
    }

    init(snapshot: DeviceSnapshot, isGateway: Bool) {
        self.init(
            id: snapshot.id,
            host: snapshot.host,
            preferredPort: snapshot.preferredPort,
            isGateway: isGateway || snapshot.isGateway,
            tracker: ReachabilityTracker(state: snapshot.state, confidence: snapshot.confidence, lastSeen: snapshot.lastSeen)
        )
    }
}

nonisolated enum MonitorEvent: Sendable, Hashable {
    case probe(deviceID: UUID, result: ProbeResult, tracker: ReachabilityTracker)
    case transition(deviceID: UUID, transition: ReachabilityTransition, tracker: ReachabilityTracker)
    case roundCompleted(at: Date)
    case paused(reason: String)
    case resumed
    case permissionDenied
    case probeUnsupported(ProbeKind)
}

nonisolated struct NetworkPathStatus: Sendable, Hashable {
    var isSatisfied: Bool
    var isWiFi: Bool
    var isExpensive: Bool
    var isConstrained: Bool
    var wifiInterfaceName: String?
    var gatewayHosts: [String]
    var isLocalNetworkDenied: Bool

    static let unavailable = NetworkPathStatus(isSatisfied: false, isWiFi: false, isExpensive: false, isConstrained: false, wifiInterfaceName: nil, gatewayHosts: [], isLocalNetworkDenied: false)

    init(isSatisfied: Bool, isWiFi: Bool, isExpensive: Bool, isConstrained: Bool, wifiInterfaceName: String?, gatewayHosts: [String], isLocalNetworkDenied: Bool) {
        self.isSatisfied = isSatisfied
        self.isWiFi = isWiFi
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.wifiInterfaceName = wifiInterfaceName
        self.gatewayHosts = gatewayHosts
        self.isLocalNetworkDenied = isLocalNetworkDenied
    }
}

nonisolated enum LocalNetworkPermissionState: String, Sendable, Hashable {
    case undetermined
    case likelyGranted
    case denied
}
