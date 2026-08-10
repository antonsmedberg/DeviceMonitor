import Foundation
import SwiftData

@MainActor
final class LocalStorageService: StorageServiceProtocol {
    private typealias DeviceMaps = (byID: [UUID: Device], byIP: [String: Device])

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchDevices() throws -> [Device] {
        let request = FetchDescriptor<Device>()
        let devices = try modelContext.fetch(request)
        return devices.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func addOrUpdate(deviceDTO: DeviceDTO) throws {
        var existingDevices = try existingDeviceMaps()
        upsert(deviceDTO, into: &existingDevices)

        try modelContext.save()
    }

    func apply(devices: [DeviceDTO]) throws {
        var existingDevices = try existingDeviceMaps()
        let incomingIDs = Set(devices.map(\.id))

        for dto in devices {
            upsert(dto, into: &existingDevices)
        }

        // Keep snapshot-backed devices in sync while preserving locally added demo devices.
        for existing in existingDevices.byID.values where !incomingIDs.contains(existing.id) && !existing.isUserAdded {
            modelContext.delete(existing)
        }

        try modelContext.save()
    }

    func resolveInitialStatus(id: UUID, isOnline: Bool, checkedAt: Date) throws {
        let request = FetchDescriptor<Device>()
        let devices = try modelContext.fetch(request)

        guard let device = devices.first(where: { $0.id == id }) else { return }

        let shouldRecordEvent =
            latestStatusEvent(for: device)?.isOnline != isOnline

        device.isOnline = isOnline

        if isOnline {
            device.lastSeen = checkedAt
        }

        if shouldRecordEvent {
            updateStatusHistory(for: device, isOnline: isOnline, timestamp: checkedAt)
        } else if latestStatusEvent(for: device) != nil {
            updateStatusHistory(for: device, isOnline: isOnline, timestamp: checkedAt)
        }

        try modelContext.save()
    }

    func delete(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        let idSet = Set(ids)
        let request = FetchDescriptor<Device>()
        let items = try modelContext.fetch(request)

        for item in items where idSet.contains(item.id) {
            modelContext.delete(item)
        }

        try modelContext.save()
    }

    private func existingDeviceMaps() throws -> DeviceMaps {
        let request = FetchDescriptor<Device>()
        let existingDevices = try modelContext.fetch(request)
        return (
            byID: Dictionary(uniqueKeysWithValues: existingDevices.map { ($0.id, $0) }),
            byIP: Dictionary(uniqueKeysWithValues: existingDevices.map { ($0.ipAddress, $0) })
        )
    }

    private func upsert(
        _ dto: DeviceDTO,
        into existingDevices: inout DeviceMaps
    ) {
        let snapshotTimestamp = Date.now

        if let existing = existingDevices.byID[dto.id] ?? existingDevices.byIP[dto.ipAddress] {
            let previousID = existing.id
            let previousIP = existing.ipAddress

            existing.id = dto.id
            existing.name = dto.name
            existing.ipAddress = dto.ipAddress
            existing.isOnline = dto.isOnline
            existing.lastSeen = resolvedLastSeen(for: dto, existingLastSeen: existing.lastSeen)
            existing.isUserAdded = existing.isUserAdded || dto.isUserAdded

            if !existing.statusHistory.isEmpty || shouldCreateStatusRecord(for: dto) {
                updateStatusHistory(for: existing, isOnline: dto.isOnline, timestamp: snapshotTimestamp)
            }

            if previousID != dto.id {
                existingDevices.byID.removeValue(forKey: previousID)
            }

            if previousIP != dto.ipAddress {
                existingDevices.byIP.removeValue(forKey: previousIP)
            }

            existingDevices.byID[dto.id] = existing
            existingDevices.byIP[dto.ipAddress] = existing
            return
        }

        let newDevice = Device(
            id: dto.id,
            namn: dto.name,
            ipAddress: dto.ipAddress,
            isOnline: dto.isOnline,
            senastSedd: resolvedLastSeen(for: dto, existingLastSeen: nil),
            isUserAdded: dto.isUserAdded
        )

        if shouldCreateStatusRecord(for: dto) {
            let event = StatusEvent(
                tidpunkt: snapshotTimestamp,
                isOnline: dto.isOnline,
                device: newDevice
            )
            newDevice.statusHistory = [event]
        }

        modelContext.insert(newDevice)
        existingDevices.byID[dto.id] = newDevice
        existingDevices.byIP[dto.ipAddress] = newDevice
    }

    private func shouldCreateStatusRecord(for dto: DeviceDTO) -> Bool {
        !dto.isUserAdded || dto.lastSeen != nil || dto.isOnline
    }

    private func resolvedLastSeen(for dto: DeviceDTO, existingLastSeen: Date?) -> Date? {
        if let lastSeen = dto.lastSeen {
            return lastSeen
        }

        if dto.isOnline {
            return existingLastSeen ?? .now
        }

        return existingLastSeen
    }

    private func updateStatusHistory(for device: Device, isOnline: Bool, timestamp: Date) {
        guard let latestEvent = latestStatusEvent(for: device) else {
            device.statusHistory = [
                StatusEvent(
                    tidpunkt: timestamp,
                    isOnline: isOnline,
                    device: device
                )
            ]
            return
        }

        if latestEvent.isOnline == isOnline {
            latestEvent.timestamp = max(latestEvent.timestamp, timestamp)
        } else {
            device.statusHistory.append(
                StatusEvent(
                    tidpunkt: timestamp,
                    isOnline: isOnline,
                    device: device
                )
            )
        }
    }

    private func latestStatusEvent(for device: Device) -> StatusEvent? {
        device.statusHistory.max { lhs, rhs in
            lhs.timestamp < rhs.timestamp
        }
    }
}
