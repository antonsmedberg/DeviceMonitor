import Foundation

actor MockDeviceMonitor: DeviceMutableServiceProtocol {
    private var devices: [DeviceDTO]
    private var lastSnapshotAt = Date.distantPast
    private let minimumSnapshotInterval: TimeInterval = 2

    init() {
        devices = Self.sampleDevices()
    }

    func currentDevices() async -> [DeviceDTO] {
        let now = Date()
        guard now.timeIntervalSince(lastSnapshotAt) >= minimumSnapshotInterval else {
            return devices
        }

        lastSnapshotAt = now
        let cycle = Int(now.timeIntervalSince1970 / 15)
        let refreshed = devices.map { device in
            let shouldFlip = (Self.stableSeed(for: device.id) ^ cycle).isMultiple(of: 7)
            let nextOnline = shouldFlip ? !device.isOnline : device.isOnline
            let lastSeen = nextOnline ? now : device.lastSeen

            return DeviceDTO(
                id: device.id,
                name: device.name,
                ipAddress: device.ipAddress,
                isOnline: nextOnline,
                lastSeen: lastSeen
            )
        }
        .sorted { (lhs: DeviceDTO, rhs: DeviceDTO) in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        devices = refreshed
        return refreshed
    }

    func remove(ids: [UUID]) async {
        let idSet = Set(ids)
        devices.removeAll { idSet.contains($0.id) }
    }

    nonisolated private static func stableSeed(for id: UUID) -> Int {
        id.uuidString.utf8.reduce(into: 5381) { hash, byte in
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
    }

    nonisolated static func sampleDevices(referenceDate: Date = .now) -> [DeviceDTO] {
        [
            DeviceDTO(id: stableUUID(for: "192.168.1.10"), name: "Camera-01", ipAddress: "192.168.1.10", isOnline: true, lastSeen: referenceDate),
            DeviceDTO(id: stableUUID(for: "192.168.1.22"), name: "Sensor-Alpha", ipAddress: "192.168.1.22", isOnline: false, lastSeen: referenceDate.addingTimeInterval(-2 * 60 * 60)),
            DeviceDTO(id: stableUUID(for: "10.0.0.1"), name: "Gateway", ipAddress: "10.0.0.1", isOnline: true, lastSeen: referenceDate.addingTimeInterval(-5 * 60)),
            DeviceDTO(id: stableUUID(for: "10.0.0.45"), name: "AccessPoint-2F", ipAddress: "10.0.0.45", isOnline: false, lastSeen: referenceDate.addingTimeInterval(-24 * 60 * 60)),
            DeviceDTO(id: stableUUID(for: "172.16.0.5"), name: "NAS-Backup", ipAddress: "172.16.0.5", isOnline: true, lastSeen: referenceDate.addingTimeInterval(-60 * 60)),
            DeviceDTO(id: stableUUID(for: "192.168.1.55"), name: "Printer-Lobby", ipAddress: "192.168.1.55", isOnline: false, lastSeen: referenceDate.addingTimeInterval(-15 * 60)),
            DeviceDTO(id: stableUUID(for: "10.0.0.254"), name: "Router-Core", ipAddress: "10.0.0.254", isOnline: true, lastSeen: referenceDate.addingTimeInterval(-30)),
            DeviceDTO(id: stableUUID(for: "192.168.1.75"), name: "Thermostat-LivingRoom", ipAddress: "192.168.1.75", isOnline: true, lastSeen: referenceDate.addingTimeInterval(-10 * 60)),
            DeviceDTO(id: stableUUID(for: "192.168.1.80"), name: "SmartLock-FrontDoor", ipAddress: "192.168.1.80", isOnline: false, lastSeen: referenceDate.addingTimeInterval(-3 * 60 * 60)),
            DeviceDTO(id: stableUUID(for: "192.168.1.90"), name: "LightSwitch-Kitchen", ipAddress: "192.168.1.90", isOnline: true, lastSeen: referenceDate.addingTimeInterval(-1 * 60)),
            DeviceDTO(id: stableUUID(for: "10.0.0.60"), name: "SmokeDetector-1F", ipAddress: "10.0.0.60", isOnline: true, lastSeen: referenceDate.addingTimeInterval(-45 * 60)),
            DeviceDTO(id: stableUUID(for: "10.0.0.61"), name: "WaterSensor-Basement", ipAddress: "10.0.0.61", isOnline: false, lastSeen: referenceDate.addingTimeInterval(-48 * 60 * 60))
        ]
    }

    nonisolated private static func stableUUID(for value: String) -> UUID {
        var hash: UInt64 = 0xcbf29ce484222325
        var secondaryHash: UInt64 = 0x84222325cbf29ce4

        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3

            secondaryHash &+= UInt64(byte) &* 0x9e3779b185ebca87
            secondaryHash ^= secondaryHash >> 33
        }

        let bytes = bigEndianBytes(of: hash) + bigEndianBytes(of: secondaryHash)

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    nonisolated private static func bigEndianBytes(of value: UInt64) -> [UInt8] {
        [
            UInt8((value >> 56) & 0xff),
            UInt8((value >> 48) & 0xff),
            UInt8((value >> 40) & 0xff),
            UInt8((value >> 32) & 0xff),
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
    }
}
