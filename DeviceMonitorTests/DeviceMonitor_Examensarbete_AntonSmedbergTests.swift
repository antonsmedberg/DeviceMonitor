import XCTest
import SwiftData
@testable import DeviceMonitor

final class DeviceMonitorTests: XCTestCase {
    private var containers: [ModelContainer] = []

    @MainActor
    func testStorageApplyRemovesStaleDevices() throws {
        let storage = try makeStorage()
        let first = DeviceDTO(id: UUID(), name: "A", ipAddress: "10.0.0.1", isOnline: true, lastSeen: .now)
        let second = DeviceDTO(id: UUID(), name: "B", ipAddress: "10.0.0.2", isOnline: false, lastSeen: .now)

        try storage.apply(devices: [first, second])
        XCTAssertEqual(try storage.fetchDevices().count, 2)

        try storage.apply(devices: [first])
        let devices = try storage.fetchDevices()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.id, first.id)
    }

    @MainActor
    func testViewModelFilteringAndCounters() async throws {
        let storage = try makeStorage()
        let initial = [
            DeviceDTO(id: UUID(), name: "Camera", ipAddress: "192.168.1.10", isOnline: true, lastSeen: .now),
            DeviceDTO(id: UUID(), name: "Sensor", ipAddress: "192.168.1.20", isOnline: false, lastSeen: .now)
        ]

        let deviceService = TestDeviceService(devices: initial)
        let viewModel = DevicesViewModel(
            deviceService: deviceService,
            storage: storage
        )

        await viewModel.refresh()
        XCTAssertEqual(viewModel.allCount, 2)
        XCTAssertEqual(viewModel.onlineCount, 1)
        XCTAssertEqual(viewModel.offlineCount, 1)

        viewModel.setFilter(.online)
        XCTAssertEqual(viewModel.filteredDevices.count, 1)
        XCTAssertTrue(viewModel.filteredDevices.allSatisfy(\.isOnline))
    }

    @MainActor
    func testStorageApplyPreservesUserAddedDevices() throws {
        let storage = try makeStorage()
        let snapshotDevice = DeviceDTO(
            id: UUID(),
            name: "Gateway",
            ipAddress: "10.0.0.1",
            isOnline: true,
            lastSeen: .now
        )
        let customDevice = DeviceDTO(
            id: UUID(),
            name: "Office Camera",
            ipAddress: "10.0.0.44",
            isOnline: false,
            lastSeen: nil,
            isUserAdded: true
        )

        try storage.addOrUpdate(deviceDTO: customDevice)
        try storage.apply(devices: [snapshotDevice])

        let devices = try storage.fetchDevices()
        XCTAssertEqual(devices.count, 2)
        XCTAssertTrue(devices.contains { $0.id == customDevice.id && $0.isUserAdded })
        XCTAssertTrue(devices.contains { $0.id == snapshotDevice.id })
    }

    @MainActor
    func testStorageAddsStatusHistoryOnlyOnTransitions() throws {
        let storage = try makeStorage()
        let deviceID = UUID()
        let offlineSnapshot = DeviceDTO(
            id: deviceID,
            name: "Sensor",
            ipAddress: "192.168.1.20",
            isOnline: false,
            lastSeen: nil
        )
        let onlineSnapshot = DeviceDTO(
            id: deviceID,
            name: "Sensor",
            ipAddress: "192.168.1.20",
            isOnline: true,
            lastSeen: .now
        )

        try storage.apply(devices: [offlineSnapshot])
        XCTAssertEqual(try storage.fetchDevices().first?.statusHistory.count, 1)

        try storage.apply(devices: [onlineSnapshot])
        XCTAssertEqual(try storage.fetchDevices().first?.statusHistory.count, 2)

        try storage.apply(devices: [onlineSnapshot])
        XCTAssertEqual(try storage.fetchDevices().first?.statusHistory.count, 2)
    }

    @MainActor
    func testStorageMatchesExistingDeviceByIPAddressWhenServiceIDChanges() throws {
        let storage = try makeStorage()
        let initial = DeviceDTO(
            id: UUID(),
            name: "Camera",
            ipAddress: "192.168.1.10",
            isOnline: false,
            lastSeen: nil
        )
        let refreshed = DeviceDTO(
            id: UUID(),
            name: "Camera",
            ipAddress: "192.168.1.10",
            isOnline: true,
            lastSeen: .now
        )

        try storage.apply(devices: [initial])
        try storage.apply(devices: [refreshed])

        let devices = try storage.fetchDevices()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.id, refreshed.id)
        XCTAssertEqual(devices.first?.statusHistory.count, 2)
        XCTAssertEqual(devices.first?.ipAddress, refreshed.ipAddress)
    }

    @MainActor
    func testManuallyAddedDeviceStartsPendingUntilFirstResolution() throws {
        let storage = try makeStorage()
        let device = DeviceDTO(
            name: "Office Camera",
            ipAddress: "192.168.1.44",
            isUserAdded: true
        )

        try storage.addOrUpdate(deviceDTO: device)

        let pendingDevice = try XCTUnwrap(try storage.fetchDevices().first)
        XCTAssertFalse(pendingDevice.hasCompletedInitialCheck)
        XCTAssertEqual(pendingDevice.statusHistory.count, 0)

        try storage.resolveInitialStatus(id: device.id, isOnline: false, checkedAt: .now)

        let resolvedDevice = try XCTUnwrap(try storage.fetchDevices().first)
        XCTAssertTrue(resolvedDevice.hasCompletedInitialCheck)
        XCTAssertEqual(resolvedDevice.statusHistory.count, 1)
        XCTAssertFalse(resolvedDevice.isOnline)
    }

    @MainActor
    private func makeStorage() throws -> LocalStorageService {
        let container = try AppModelFactory.makeInMemoryModelContainer()
        containers.append(container)
        return LocalStorageService(modelContext: container.mainContext)
    }
}

actor TestDeviceService: DeviceServiceProtocol {
    private let devices: [DeviceDTO]

    init(devices: [DeviceDTO]) {
        self.devices = devices
    }

    func currentDevices() async -> [DeviceDTO] { devices }
}
