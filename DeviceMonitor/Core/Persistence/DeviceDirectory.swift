import Foundation
import Observation

/// In-memory, observable source of truth for the UI. Holds immutable snapshots only.
@Observable
@MainActor
final class DeviceDirectory {
    private(set) var devices: [DeviceSnapshot]
    private(set) var lastRoundAt: Date?
    /// Goes up whenever status events were written, so views showing history can reload on it
    /// instead of on a state change, which arrives before the event is stored.
    private(set) var historyRevision = 0

    init(devices: [DeviceSnapshot] = []) {
        self.devices = devices.sorted(by: DeviceStore.defaultOrder)
        self.lastRoundAt = nil
    }

    func device(id: UUID) -> DeviceSnapshot? {
        devices.first { $0.id == id }
    }

    func replaceAll(_ snapshots: [DeviceSnapshot]) {
        devices = snapshots.sorted(by: DeviceStore.defaultOrder)
    }

    func apply(_ snapshot: DeviceSnapshot) {
        apply([snapshot])
    }

    func apply(_ snapshots: [DeviceSnapshot]) {
        guard !snapshots.isEmpty else { return }
        var updated = devices
        for snapshot in snapshots {
            if let index = updated.firstIndex(where: { $0.id == snapshot.id }) {
                updated[index] = snapshot
            } else {
                updated.append(snapshot)
            }
        }
        devices = updated.sorted(by: DeviceStore.defaultOrder)
    }

    func remove(ids: [UUID]) {
        let idSet = Set(ids)
        devices.removeAll { idSet.contains($0.id) }
    }

    func markRound(at date: Date) {
        lastRoundAt = date
    }

    func markHistoryChanged() {
        historyRevision += 1
    }

    var onlineCount: Int { devices.filter { $0.state == .online }.count }
    var degradedCount: Int { devices.filter { $0.state == .degraded }.count }
    var offlineCount: Int { devices.filter { $0.state == .offline }.count }
    var unknownCount: Int { devices.filter { $0.state == .unknown }.count }

    func newCount(now: Date) -> Int {
        devices.filter { $0.isNew(now: now) && !$0.isUserAdded }.count
    }

    /// 0…1: online counts fully, unstable counts half; unknown devices are excluded.
    var healthScore: Double {
        let checked = devices.filter { $0.state != .unknown }
        guard !checked.isEmpty else { return 0 }
        let score = checked.reduce(0.0) { partial, device in
            switch device.state {
            case .online: return partial + 1
            case .degraded: return partial + 0.5
            default: return partial
            }
        }
        return score / Double(checked.count)
    }

    var gatewayID: UUID? {
        devices.first { $0.isGateway }?.id
    }

    var gateway: DeviceSnapshot? {
        devices.first { $0.isGateway }
    }
}
