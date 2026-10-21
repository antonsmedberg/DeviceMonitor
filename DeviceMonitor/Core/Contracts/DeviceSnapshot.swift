import Foundation

/// Confidence-based reachability state. `degraded` means recent misses but not yet offline.
nonisolated enum ReachabilityState: String, Sendable, Codable, Hashable, CaseIterable {
    case unknown
    case online
    case degraded
    case offline

    var title: String {
        switch self {
        case .unknown: return "Checking"
        case .online: return "Online"
        case .degraded: return "Unstable"
        case .offline: return "Offline"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .online: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .offline: return "xmark.circle.fill"
        }
    }

    /// Glyph for the small badge on a device tile, so state never depends on colour alone.
    var badgeSymbol: String {
        switch self {
        case .unknown: return "ellipsis"
        case .online: return "checkmark"
        case .degraded: return "exclamationmark"
        case .offline: return "xmark"
        }
    }

    /// Sort order for lists: problems first.
    var sortRank: Int {
        switch self {
        case .degraded: return 0
        case .offline: return 1
        case .unknown: return 2
        case .online: return 3
        }
    }

    var isUp: Bool { self == .online || self == .degraded }
}

nonisolated enum DeviceKind: String, Sendable, Codable, Hashable, CaseIterable {
    case router, computer, phone, tablet, printer, tv, speaker, camera, nas, iot, console, watch, hub, unknown

    var title: String {
        switch self {
        case .router: return "Router"
        case .computer: return "Computer"
        case .phone: return "Phone"
        case .tablet: return "Tablet"
        case .printer: return "Printer"
        case .tv: return "TV"
        case .speaker: return "Speaker"
        case .camera: return "Camera"
        case .nas: return "Storage"
        case .iot: return "Smart Device"
        case .console: return "Game Console"
        case .watch: return "Watch"
        case .hub: return "Hub"
        case .unknown: return "Device"
        }
    }

    var systemImage: String {
        switch self {
        case .router: return "wifi.router"
        case .computer: return "desktopcomputer"
        case .phone: return "smartphone"
        case .tablet: return "ipad"
        case .printer: return "printer"
        case .tv: return "tv"
        case .speaker: return "hifispeaker"
        case .camera: return "web.camera"
        case .nas: return "server.rack"
        case .iot: return "lightbulb.led"
        case .console: return "gamecontroller"
        case .watch: return "watch.analog"
        case .hub: return "house.badge.wifi"
        case .unknown: return "questionmark"
        }
    }
}

/// A Bonjour service advertised by a device.
nonisolated struct DiscoveredService: Sendable, Codable, Hashable, Identifiable {
    var id: String { "\(type)|\(name)" }
    let type: String
    let name: String
    let port: UInt16?
    let txt: [String: String]

    init(type: String, name: String, port: UInt16?, txt: [String: String]) {
        self.type = type
        self.name = name
        self.port = port
        self.txt = txt
    }
}

/// Immutable view of a device, safe to pass between actors and cheap for SwiftUI to diff.
nonisolated struct DeviceSnapshot: Sendable, Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var nickname: String?
    var hostname: String?
    var host: String
    var macAddress: String?
    var vendor: String?
    var kind: DeviceKind
    var state: ReachabilityState
    var confidence: Double
    var latencyMilliseconds: Double?
    var firstSeen: Date
    var lastSeen: Date?
    var lastChecked: Date?
    var isUserAdded: Bool
    var isFavorite: Bool
    var isTrusted: Bool
    var isGateway: Bool
    var tags: [String]
    var notes: String
    var preferredPort: UInt16?
    var openPorts: [UInt16]
    var services: [DiscoveredService]
    var networkKey: String?

    init(
        id: UUID,
        name: String,
        nickname: String? = nil,
        hostname: String? = nil,
        host: String,
        macAddress: String? = nil,
        vendor: String? = nil,
        kind: DeviceKind = .unknown,
        state: ReachabilityState = .unknown,
        confidence: Double = 0,
        latencyMilliseconds: Double? = nil,
        firstSeen: Date,
        lastSeen: Date? = nil,
        lastChecked: Date? = nil,
        isUserAdded: Bool = false,
        isFavorite: Bool = false,
        isTrusted: Bool = false,
        isGateway: Bool = false,
        tags: [String] = [],
        notes: String = "",
        preferredPort: UInt16? = nil,
        openPorts: [UInt16] = [],
        services: [DiscoveredService] = [],
        networkKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.nickname = nickname
        self.hostname = hostname
        self.host = host
        self.macAddress = macAddress
        self.vendor = vendor
        self.kind = kind
        self.state = state
        self.confidence = confidence
        self.latencyMilliseconds = latencyMilliseconds
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.lastChecked = lastChecked
        self.isUserAdded = isUserAdded
        self.isFavorite = isFavorite
        self.isTrusted = isTrusted
        self.isGateway = isGateway
        self.tags = tags
        self.notes = notes
        self.preferredPort = preferredPort
        self.openPorts = openPorts
        self.services = services
        self.networkKey = networkKey
    }

    /// What the user sees: nickname, then the stored name (typed by the user or derived from
    /// Bonjour and the hostname), then the hostname, then the address.
    var displayName: String {
        if let nickname, !nickname.isEmpty { return nickname }
        if !name.isEmpty { return name }
        if let hostname, !hostname.isEmpty { return hostname }
        return host
    }

    /// Secondary line: address plus hostname when it differs from the display name.
    var addressLine: String {
        if let hostname, !hostname.isEmpty, hostname != displayName {
            return "\(host) · \(hostname)"
        }
        return host
    }

    func isNew(now: Date) -> Bool {
        now.timeIntervalSince(firstSeen) < 24 * 60 * 60
    }

    var canWake: Bool { macAddress != nil }

    /// Found on the network, never trusted or added by the user, and not the router.
    var isStranger: Bool { !isTrusted && !isUserAdded && !isGateway }

    /// A web UI URL when an HTTP service is advertised or a web port is open. An advertised service
    /// carries its real port (a NAS on 5000/5001, QNAP on 8080), so it wins over the port guesses.
    var webURL: URL? {
        if let service = services.first(where: { $0.type == "_https._tcp" }) {
            return linkURL(scheme: "https", port: service.port, defaultPort: 443)
        }
        if let service = services.first(where: { $0.type == "_http._tcp" }) {
            return linkURL(scheme: "http", port: service.port, defaultPort: 80)
        }
        if openPorts.contains(443) { return URL(string: "https://\(bracketedHost)") }
        if openPorts.contains(80) { return URL(string: "http://\(bracketedHost)") }
        if openPorts.contains(8443) { return URL(string: "https://\(bracketedHost):8443") }
        if openPorts.contains(8080) { return URL(string: "http://\(bracketedHost):8080") }
        if let preferredPort, [80, 8080, 8000].contains(preferredPort) {
            return URL(string: "http://\(bracketedHost):\(preferredPort)")
        }
        return nil
    }

    var sshURL: URL? {
        if let service = services.first(where: { $0.type == "_ssh._tcp" || $0.type == "_sftp-ssh._tcp" }) {
            return linkURL(scheme: "ssh", port: service.port, defaultPort: 22)
        }
        return openPorts.contains(22) ? URL(string: "ssh://\(bracketedHost)") : nil
    }

    var vncURL: URL? {
        if let service = services.first(where: { $0.type == "_rfb._tcp" }) {
            return linkURL(scheme: "vnc", port: service.port, defaultPort: 5900)
        }
        return openPorts.contains(5900) ? URL(string: "vnc://\(bracketedHost)") : nil
    }

    /// Leaves the port out when it is the scheme's default.
    private func linkURL(scheme: String, port: UInt16?, defaultPort: UInt16) -> URL? {
        if let port, port != defaultPort {
            return URL(string: "\(scheme)://\(bracketedHost):\(port)")
        }
        return URL(string: "\(scheme)://\(bracketedHost)")
    }

    /// IPv6 literals must be bracketed inside URLs.
    var bracketedHost: String {
        host.contains(":") ? "[\(host)]" : host
    }
}

nonisolated struct StatusEventSnapshot: Sendable, Codable, Hashable, Identifiable {
    let id: UUID
    let deviceID: UUID
    let timestamp: Date
    let state: ReachabilityState

    init(id: UUID, deviceID: UUID, timestamp: Date, state: ReachabilityState) {
        self.id = id
        self.deviceID = deviceID
        self.timestamp = timestamp
        self.state = state
    }
}

nonisolated struct LatencySampleSnapshot: Sendable, Codable, Hashable, Identifiable {
    let id: UUID
    let deviceID: UUID
    let timestamp: Date
    let milliseconds: Double
    let probeKind: ProbeKind

    init(id: UUID, deviceID: UUID, timestamp: Date, milliseconds: Double, probeKind: ProbeKind) {
        self.id = id
        self.deviceID = deviceID
        self.timestamp = timestamp
        self.milliseconds = milliseconds
        self.probeKind = probeKind
    }
}

/// User-editable fields, applied atomically by the store.
nonisolated struct DeviceEdit: Sendable, Hashable {
    let id: UUID
    var nickname: String?
    var kind: DeviceKind
    var tags: [String]
    var notes: String
    var isFavorite: Bool
    var isTrusted: Bool
    var macAddress: String?
    var preferredPort: UInt16?

    init(snapshot: DeviceSnapshot) {
        id = snapshot.id
        nickname = snapshot.nickname
        kind = snapshot.kind
        tags = snapshot.tags
        notes = snapshot.notes
        isFavorite = snapshot.isFavorite
        isTrusted = snapshot.isTrusted
        macAddress = snapshot.macAddress
        preferredPort = snapshot.preferredPort
    }
}
