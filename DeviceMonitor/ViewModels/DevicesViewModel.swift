import Foundation
import Combine
import os

@MainActor
final class DevicesViewModel: ObservableObject {
    enum FilterType: String, CaseIterable, Hashable, Sendable {
        case all
        case online
        case offline
    }

    private let logger = Logger(subsystem: "DeviceMonitor", category: "DevicesViewModel")

    @Published private(set) var devices: [Device] = []
    @Published private(set) var selectedFilter: FilterType = .all
    @Published private(set) var lastError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var lastRefreshAt: Date?

    private let deviceService: any DeviceServiceProtocol
    private let storage: any StorageServiceProtocol

    var filteredDevices: [Device] {
        switch selectedFilter {
            case .all:
                return devices
            case .online:
                return devices.filter { $0.hasCompletedInitialCheck && $0.isOnline }
            case .offline:
                return devices.filter { $0.hasCompletedInitialCheck && !$0.isOnline }
        }
    }

    var allCount: Int {
        devices.count
    }

    var onlineCount: Int {
        devices.lazy.filter { $0.hasCompletedInitialCheck && $0.isOnline }.count
    }

    var offlineCount: Int {
        devices.lazy.filter { $0.hasCompletedInitialCheck && !$0.isOnline }.count
    }

    var checkingCount: Int {
        devices.lazy.filter { !$0.hasCompletedInitialCheck }.count
    }

    init(
        deviceService: any DeviceServiceProtocol,
        storage: any StorageServiceProtocol
    ) {
        self.deviceService = deviceService
        self.storage = storage
        loadPersistedDevices()
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let latestDevices = await deviceService.currentDevices()
            try Task.checkCancellation()
            try storage.apply(devices: latestDevices)
            let storedDevices = try storage.fetchDevices()
            try Task.checkCancellation()
            devices = storedDevices
            lastRefreshAt = .now
            lastError = nil
        } catch is CancellationError {
            logger.debug("Refresh cancelled")
        } catch {
            recordFailure(error, prefix: "Failed to refresh devices")
        }
    }

    func add(deviceDTO: DeviceDTO) {
        mutateStorage(errorPrefix: "Failed to add device") {
            try storage.addOrUpdate(deviceDTO: deviceDTO)
        }

        scheduleInitialStatusResolution(for: deviceDTO)
    }

    func delete(deviceIDs: [UUID]) {
        guard !deviceIDs.isEmpty else { return }

        let idSet = Set(deviceIDs)
        let removableIDs = devices
            .filter { idSet.contains($0.id) }
            .map(\.id)
        guard !removableIDs.isEmpty else { return }

        mutateStorage(errorPrefix: "Failed to delete device") {
            try storage.delete(ids: removableIDs)
        }

        if let mutableService = deviceService as? DeviceMutableServiceProtocol {
            Task {
                await mutableService.remove(ids: removableIDs)
            }
        }
    }

    func setFilter(_ filter: FilterType) {
        guard selectedFilter != filter else { return }
        selectedFilter = filter
    }

    private func loadPersistedDevices() {
        do {
            devices = try storage.fetchDevices()
        } catch {
            recordFailure(error, prefix: "Failed to load stored devices")
        }
    }

    private func mutateStorage(errorPrefix: String, operation: () throws -> Void) {
        do {
            try operation()
            devices = try storage.fetchDevices()
            lastError = nil
        } catch {
            recordFailure(error, prefix: errorPrefix)
        }
    }

    private func recordFailure(_ error: Error, prefix: String) {
        let message = error.localizedDescription
        logger.error("\(prefix, privacy: .public): \(message, privacy: .public)")
        lastError = "\(prefix): \(message)"
    }

    private func scheduleInitialStatusResolution(for deviceDTO: DeviceDTO) {
        guard deviceDTO.isUserAdded else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 2_300_000_000)
            guard !Task.isCancelled else { return }

            do {
                let checkedAt = Date()
                try storage.resolveInitialStatus(id: deviceDTO.id, isOnline: true, checkedAt: checkedAt)
                devices = try storage.fetchDevices()
                lastRefreshAt = checkedAt
                lastError = nil
            } catch {
                recordFailure(error, prefix: "Failed to finish initial device check")
            }
        }
    }
}
