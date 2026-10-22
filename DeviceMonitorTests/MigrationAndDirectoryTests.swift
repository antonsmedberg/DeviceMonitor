import Foundation
import SwiftData
import Testing
@testable import DeviceMonitor

@Suite("Schema migration")
struct MigrationPlanTests {
    @Test func planListsBothVersions() {
        #expect(DeviceMonitorMigrationPlan.schemas.count == 2)
        #expect(DeviceMonitorMigrationPlan.stages.count == 1)
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(SchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
    }

    @Test func v1EntitiesMatchTheShippedStore() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let device = try #require(schema.entities.first { $0.name == "Device" })
        let attributes = Set(device.attributes.map(\.name))
        #expect(attributes.isSuperset(of: ["id", "namn", "ipAddress", "isOnline", "senastSedd", "isUserAdded"]))
        #expect(device.relationships.map(\.name) == ["statusHistorik"])
        let event = try #require(schema.entities.first { $0.name == "StatusEvent" })
        #expect(Set(event.attributes.map(\.name)).isSuperset(of: ["id", "tidpunkt", "isOnline"]))
    }

    @Test func v2RenamesKeepOriginalNames() throws {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let device = try #require(schema.entities.first { $0.name == "Device" })
        let name = try #require(device.attributes.first { $0.name == "name" })
        #expect(name.originalName == "namn")
        let lastSeen = try #require(device.attributes.first { $0.name == "lastSeen" })
        #expect(lastSeen.originalName == "senastSedd")
        let history = try #require(device.relationships.first { $0.name == "statusHistory" })
        #expect(history.originalName == "statusHistorik")
        let event = try #require(schema.entities.first { $0.name == "StatusEvent" })
        let timestamp = try #require(event.attributes.first { $0.name == "timestamp" })
        #expect(timestamp.originalName == "tidpunkt")
        #expect(schema.entities.map(\.name).sorted() == ["Device", "KnownNetwork", "LatencySample", "StatusEvent"])
    }

    @Test @MainActor func inMemoryContainerOpens() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        context.insert(Device(name: "x", ipAddress: "10.0.0.1"))
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<Device>())
        #expect(fetched.count == 1)
    }
}

@Suite("Device directory")
@MainActor
struct DeviceDirectoryTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(_ name: String, state: ReachabilityState, isGateway: Bool = false, firstSeen: Date? = nil) -> DeviceSnapshot {
        DeviceSnapshot(id: UUID(), name: name, host: name, state: state, firstSeen: firstSeen ?? now.addingTimeInterval(-86_400 * 5), isGateway: isGateway)
    }

    @Test func countsAndHealth() {
        let directory = DeviceDirectory(devices: [
            snapshot("Router", state: .online, isGateway: true),
            snapshot("A", state: .online),
            snapshot("B", state: .degraded),
            snapshot("C", state: .offline),
            snapshot("D", state: .unknown),
            snapshot("E", state: .online, firstSeen: now.addingTimeInterval(-60)),
        ])
        #expect(directory.onlineCount == 3)
        #expect(directory.degradedCount == 1)
        #expect(directory.offlineCount == 1)
        #expect(directory.unknownCount == 1)
        #expect(directory.newCount(now: now) == 1)
        #expect(abs(directory.healthScore - 0.7) < 0.0001)
        #expect(directory.devices.first?.name == "Router")
        #expect(directory.gateway?.name == "Router")
    }

    @Test func applyReplacesOrInserts() {
        let directory = DeviceDirectory()
        let first = snapshot("A", state: .unknown)
        directory.apply(first)
        var updated = first
        updated.state = .online
        directory.apply(updated)
        #expect(directory.devices.count == 1)
        #expect(directory.device(id: first.id)?.state == .online)
        directory.apply([snapshot("B", state: .offline)])
        #expect(directory.devices.count == 2)
        #expect(directory.devices.first?.name == "B")
        directory.remove(ids: [first.id])
        #expect(directory.devices.count == 1)
        directory.markRound(at: now)
        #expect(directory.lastRoundAt == now)
    }
}
