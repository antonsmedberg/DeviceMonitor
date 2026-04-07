import Foundation

protocol DeviceServiceProtocol: AnyObject, Sendable {
    func currentDevices() async -> [DeviceDTO]
}

protocol DeviceMutableServiceProtocol: DeviceServiceProtocol {
    func remove(ids: [UUID]) async
}

@MainActor
protocol StorageServiceProtocol: AnyObject {
    func fetchDevices() throws -> [Device]
    func addOrUpdate(deviceDTO: DeviceDTO) throws
    func apply(devices: [DeviceDTO]) throws
    func resolveInitialStatus(id: UUID, isOnline: Bool, checkedAt: Date) throws
    func delete(ids: [UUID]) throws
}

/// Lightweight DTO passed safely across actor boundaries.
struct DeviceDTO: Sendable, Identifiable {
    let id: UUID
    let name: String
    let ipAddress: String
    let isOnline: Bool
    let lastSeen: Date?
    let isUserAdded: Bool

    nonisolated init(
        id: UUID = UUID(),
        name: String,
        ipAddress: String,
        isOnline: Bool = false,
        lastSeen: Date? = nil,
        isUserAdded: Bool = false
    ) {
        self.id = id
        self.name = name
        self.ipAddress = ipAddress
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.isUserAdded = isUserAdded
    }
}
