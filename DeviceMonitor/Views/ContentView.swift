import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var viewModel: DevicesViewModel

    @MainActor
    init(
        modelContext: ModelContext,
        deviceService: any DeviceServiceProtocol = MockDeviceMonitor()
    ) {
        let storage = LocalStorageService(modelContext: modelContext)
        _viewModel = StateObject(
            wrappedValue: DevicesViewModel(
                deviceService: deviceService,
                storage: storage
            )
        )
    }

    @MainActor
    init(viewModel: DevicesViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            DevicesView(viewModel: viewModel)
        }
    }
}

#if DEBUG
private struct ContentViewPreview: View {
    @StateObject private var previewViewModel = PreviewDevicesViewModelFactory.make()

    var body: some View {
        ContentView(viewModel: previewViewModel)
            .tint(AppTheme.accent)
            .preferredColorScheme(.dark)
    }
}

@MainActor
private enum PreviewDevicesViewModelFactory {
    static func make() -> DevicesViewModel {
        DevicesViewModel(
            deviceService: MockDeviceMonitor(),
            storage: PreviewStorageService(devices: MockDeviceMonitor.sampleDevices())
        )
    }
}

@MainActor
private final class PreviewStorageService: StorageServiceProtocol {
    private var devices: [Device]

    init(devices: [DeviceDTO]) {
        self.devices = devices.map(Self.makeDevice(from:))
    }

    func fetchDevices() throws -> [Device] {
        devices.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func addOrUpdate(deviceDTO: DeviceDTO) throws {
        upsert(deviceDTO)
    }

    func apply(devices: [DeviceDTO]) throws {
        let incomingIDs = Set(devices.map(\.id))

        for device in devices {
            upsert(device)
        }

        self.devices.removeAll { existing in
            !incomingIDs.contains(existing.id) && !existing.isUserAdded
        }
    }

    func resolveInitialStatus(id: UUID, isOnline: Bool, checkedAt: Date) throws {
        guard let device = devices.first(where: { $0.id == id }) else { return }
        device.isOnline = isOnline
        if isOnline {
            device.lastSeen = checkedAt
        }
        appendStatusEventIfNeeded(for: device, isOnline: isOnline, timestamp: checkedAt)
    }

    func delete(ids: [UUID]) throws {
        let idSet = Set(ids)
        devices.removeAll { idSet.contains($0.id) }
    }

    private func upsert(_ dto: DeviceDTO) {
        if let existing = devices.first(where: { $0.id == dto.id || $0.ipAddress == dto.ipAddress }) {
            existing.id = dto.id
            existing.name = dto.name
            existing.ipAddress = dto.ipAddress
            existing.isOnline = dto.isOnline
            existing.lastSeen = dto.lastSeen ?? existing.lastSeen
            existing.isUserAdded = existing.isUserAdded || dto.isUserAdded

            if let timestamp = dto.lastSeen ?? existing.lastSeen {
                appendStatusEventIfNeeded(for: existing, isOnline: dto.isOnline, timestamp: timestamp)
            }
            return
        }

        devices.append(Self.makeDevice(from: dto))
    }

    private func appendStatusEventIfNeeded(for device: Device, isOnline: Bool, timestamp: Date) {
        if let latest = device.statusHistory.max(by: { $0.timestamp < $1.timestamp }) {
            if latest.isOnline == isOnline {
                latest.timestamp = max(latest.timestamp, timestamp)
            } else {
                device.statusHistory.append(
                    StatusEvent(tidpunkt: timestamp, isOnline: isOnline, device: device)
                )
            }
            return
        }

        device.statusHistory = [
            StatusEvent(tidpunkt: timestamp, isOnline: isOnline, device: device)
        ]
    }

    private static func makeDevice(from dto: DeviceDTO) -> Device {
        let device = Device(
            id: dto.id,
            namn: dto.name,
            ipAddress: dto.ipAddress,
            isOnline: dto.isOnline,
            senastSedd: dto.lastSeen,
            isUserAdded: dto.isUserAdded
        )

        if let timestamp = dto.lastSeen ?? (dto.isOnline ? .now : nil) {
            device.statusHistory = [
                StatusEvent(tidpunkt: timestamp, isOnline: dto.isOnline, device: device)
            ]
        }

        return device
    }
}

#Preview("ContentView") {
    ContentViewPreview()
}
#endif
