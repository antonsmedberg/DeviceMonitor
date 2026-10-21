import Foundation
import SwiftData

/// Current schema. Renames use `originalName` so the V1 → V2 migration stays lightweight;
/// every new attribute has an inline default.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Device.self, StatusEvent.self, LatencySample.self, KnownNetwork.self]
    }

    @Model
    final class Device {
        @Attribute(.unique) var id: UUID
        @Attribute(originalName: "namn") var name: String
        var ipAddress: String
        var isOnline: Bool
        @Attribute(originalName: "senastSedd") var lastSeen: Date?
        var isUserAdded: Bool

        var identityKey: String = ""
        var stateRaw: String = "unknown"
        var confidence: Double = 0
        var hostname: String? = nil
        var macAddress: String? = nil
        var vendor: String? = nil
        var kindRaw: String = "unknown"
        var kindIsUserSet: Bool = false
        var nickname: String? = nil
        var notes: String = ""
        var tagsRaw: String = ""
        var isFavorite: Bool = false
        var isTrusted: Bool = false
        var isGateway: Bool = false
        /// Rows migrated from V1 get `distantPast`, so an upgrade never marks every known device as new.
        var firstSeen: Date = Date.distantPast
        var lastChecked: Date? = nil
        var preferredPort: Int = 0
        var openPortsRaw: String = ""
        var servicesJSON: Data? = nil
        var networkKey: String? = nil
        var latestLatencyMs: Double? = nil

        @Relationship(deleteRule: .cascade, originalName: "statusHistorik", inverse: \StatusEvent.device)
        var statusHistory: [StatusEvent]

        @Relationship(deleteRule: .cascade, inverse: \LatencySample.device)
        var latencySamples: [LatencySample]

        init(
            id: UUID = UUID(),
            name: String,
            ipAddress: String,
            isOnline: Bool = false,
            lastSeen: Date? = nil,
            isUserAdded: Bool = false,
            identityKey: String = "",
            firstSeen: Date = .now
        ) {
            self.id = id
            self.name = name
            self.ipAddress = ipAddress
            self.isOnline = isOnline
            self.lastSeen = lastSeen
            self.isUserAdded = isUserAdded
            self.identityKey = identityKey
            self.firstSeen = firstSeen
            self.statusHistory = []
            self.latencySamples = []
        }
    }

    @Model
    final class StatusEvent {
        @Attribute(.unique) var id: UUID
        @Attribute(originalName: "tidpunkt") var timestamp: Date
        var isOnline: Bool
        var stateRaw: String = ""
        var device: Device?

        init(id: UUID = UUID(), timestamp: Date = .now, isOnline: Bool, stateRaw: String, device: Device? = nil) {
            self.id = id
            self.timestamp = timestamp
            self.isOnline = isOnline
            self.stateRaw = stateRaw
            self.device = device
        }
    }

    @Model
    final class LatencySample {
        @Attribute(.unique) var id: UUID
        var timestamp: Date
        var milliseconds: Double
        var probeKindRaw: String
        var device: Device?

        init(id: UUID = UUID(), timestamp: Date, milliseconds: Double, probeKindRaw: String, device: Device? = nil) {
            self.id = id
            self.timestamp = timestamp
            self.milliseconds = milliseconds
            self.probeKindRaw = probeKindRaw
            self.device = device
        }
    }

    @Model
    final class KnownNetwork {
        @Attribute(.unique) var key: String
        var displayName: String
        var gatewayHost: String
        var subnetCIDR: String
        var firstSeen: Date
        var lastSeen: Date

        init(key: String, displayName: String, gatewayHost: String, subnetCIDR: String, firstSeen: Date = .now, lastSeen: Date = .now) {
            self.key = key
            self.displayName = displayName
            self.gatewayHost = gatewayHost
            self.subnetCIDR = subnetCIDR
            self.firstSeen = firstSeen
            self.lastSeen = lastSeen
        }
    }
}

typealias Device = SchemaV2.Device
typealias StatusEvent = SchemaV2.StatusEvent
typealias LatencySample = SchemaV2.LatencySample
typealias KnownNetwork = SchemaV2.KnownNetwork

// MARK: - Typed accessors

extension SchemaV2.Device {
    static let tagSeparator = "\u{1F}"

    var state: ReachabilityState {
        get { ReachabilityState(rawValue: stateRaw) ?? (isOnline ? .online : .unknown) }
        set {
            stateRaw = newValue.rawValue
            isOnline = newValue.isUp
        }
    }

    var kind: DeviceKind {
        get { DeviceKind(rawValue: kindRaw) ?? .unknown }
        set { kindRaw = newValue.rawValue }
    }

    var tags: [String] {
        get { tagsRaw.isEmpty ? [] : tagsRaw.components(separatedBy: Self.tagSeparator) }
        set { tagsRaw = newValue.joined(separator: Self.tagSeparator) }
    }

    var openPorts: [UInt16] {
        get { openPortsRaw.split(separator: ",").compactMap { UInt16($0) }.sorted() }
        set { openPortsRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }

    var services: [DiscoveredService] {
        get {
            guard let servicesJSON else { return [] }
            return (try? JSONDecoder().decode([DiscoveredService].self, from: servicesJSON)) ?? []
        }
        set {
            servicesJSON = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    var preferredPortValue: UInt16? {
        get { preferredPort > 0 && preferredPort <= Int(UInt16.max) ? UInt16(preferredPort) : nil }
        set { preferredPort = newValue.map(Int.init) ?? 0 }
    }

    func snapshot() -> DeviceSnapshot {
        DeviceSnapshot(
            id: id,
            name: name,
            nickname: nickname,
            hostname: hostname,
            host: ipAddress,
            macAddress: macAddress,
            vendor: vendor,
            kind: kind,
            state: state,
            confidence: confidence,
            latencyMilliseconds: latestLatencyMs,
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            lastChecked: lastChecked,
            isUserAdded: isUserAdded,
            isFavorite: isFavorite,
            isTrusted: isTrusted,
            isGateway: isGateway,
            tags: tags,
            notes: notes,
            preferredPort: preferredPortValue,
            openPorts: openPorts,
            services: services,
            networkKey: networkKey
        )
    }
}

extension SchemaV2.StatusEvent {
    var state: ReachabilityState {
        ReachabilityState(rawValue: stateRaw) ?? (isOnline ? .online : .offline)
    }

    func snapshot(deviceID: UUID) -> StatusEventSnapshot {
        StatusEventSnapshot(id: id, deviceID: deviceID, timestamp: timestamp, state: state)
    }
}

extension SchemaV2.LatencySample {
    func snapshot(deviceID: UUID) -> LatencySampleSnapshot {
        LatencySampleSnapshot(
            id: id,
            deviceID: deviceID,
            timestamp: timestamp,
            milliseconds: milliseconds,
            probeKind: ProbeKind(rawValue: probeKindRaw) ?? .tcp
        )
    }
}
