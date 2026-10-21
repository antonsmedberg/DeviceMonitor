import Foundation
import SwiftData

extension DeviceStore {
    /// Seeds a store with demo devices, their history and latency samples.
    func seedDemo(devices: [DeviceSnapshot], events: [StatusEventSnapshot], latencySampler: (UUID, Double) -> [LatencySampleSnapshot]) throws {
        var models: [UUID: Device] = [:]
        for snapshot in devices {
            let device = Device(
                id: snapshot.id,
                name: snapshot.name,
                ipAddress: snapshot.host,
                isOnline: snapshot.state.isUp,
                lastSeen: snapshot.lastSeen,
                isUserAdded: snapshot.isUserAdded,
                identityKey: DeviceIdentity.key(macAddress: snapshot.macAddress, hostname: snapshot.hostname, bonjourName: snapshot.services.first?.name, host: snapshot.host),
                firstSeen: snapshot.firstSeen
            )
            device.nickname = snapshot.nickname
            device.hostname = snapshot.hostname
            device.macAddress = snapshot.macAddress
            device.vendor = snapshot.vendor
            device.kind = snapshot.kind
            device.state = snapshot.state
            device.confidence = snapshot.confidence
            device.latestLatencyMs = snapshot.latencyMilliseconds
            device.lastChecked = snapshot.lastChecked
            device.isFavorite = snapshot.isFavorite
            device.isTrusted = snapshot.isTrusted
            device.isGateway = snapshot.isGateway
            device.tags = snapshot.tags
            device.notes = snapshot.notes
            device.preferredPortValue = snapshot.preferredPort
            device.openPorts = snapshot.openPorts
            device.services = snapshot.services
            device.networkKey = snapshot.networkKey
            modelContext.insert(device)
            models[snapshot.id] = device

            if let baseline = snapshot.latencyMilliseconds {
                for sample in latencySampler(snapshot.id, baseline) {
                    modelContext.insert(LatencySample(id: sample.id, timestamp: sample.timestamp, milliseconds: sample.milliseconds, probeKindRaw: sample.probeKind.rawValue, device: device))
                }
            }
        }
        for event in events {
            guard let device = models[event.deviceID] else { continue }
            modelContext.insert(StatusEvent(id: event.id, timestamp: event.timestamp, isOnline: event.state.isUp, stateRaw: event.state.rawValue, device: device))
        }
        try save()
    }
}
