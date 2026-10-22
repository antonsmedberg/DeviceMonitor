import Foundation
import Testing
@testable import DeviceMonitor

@Suite("Activity density")
struct ActivityDensityTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func device(_ state: ReachabilityState, firstSeen: TimeInterval = -86_400 * 30) -> DeviceSnapshot {
        DeviceSnapshot(id: UUID(), name: "d", host: "10.0.0.\(Int.random(in: 2...250))", state: state, firstSeen: now.addingTimeInterval(firstSeen))
    }

    @Test func bucketsCoverTheRange() {
        let density = ActivityDensity(events: [], devices: [], range: .day, now: now)
        #expect(density.buckets.count == 24)
        #expect(density.buckets.first?.start == now.addingTimeInterval(-86_400))
        #expect(density.buckets.last?.end == now)
        #expect(ActivityDensity(events: [], devices: [], range: .week, now: now).buckets.count == 28)
    }

    @Test func steadyDevicesUseTheirCurrentState() {
        let devices = [device(.online), device(.online), device(.offline)]
        let density = ActivityDensity(events: [], devices: devices, range: .day, now: now)
        #expect(density.buckets.allSatisfy { $0.online == 2 })
        #expect(density.peakOnline == 2)
    }

    @Test func historyDecidesEachBucket() {
        let phone = device(.online)
        // Left 10 hours ago, came back 4 hours ago.
        let events = [
            StatusEventSnapshot(id: UUID(), deviceID: phone.id, timestamp: now.addingTimeInterval(-10 * 3600), state: .offline),
            StatusEventSnapshot(id: UUID(), deviceID: phone.id, timestamp: now.addingTimeInterval(-4 * 3600), state: .online),
        ]
        let density = ActivityDensity(events: events, devices: [phone], range: .day, now: now)
        // Bucket 13 starts 11 hours ago (before the first event: it was up then).
        #expect(density.buckets[13].online == 1)
        // Bucket 15 starts 9 hours ago: offline.
        #expect(density.buckets[15].online == 0)
        // Bucket 21 starts 3 hours ago: back online.
        #expect(density.buckets[21].online == 1)
        #expect(density.buckets[14].events == 1)
        #expect(density.buckets[20].events == 1)
        #expect(density.buckets.map(\.events).reduce(0, +) == 2)
    }

    @Test func aDeviceThatBecameUnstableWasUpBefore() {
        // Its "came online" event is older than the fetched history; only an online device turns unstable.
        let nas = device(.online)
        let events = [
            StatusEventSnapshot(id: UUID(), deviceID: nas.id, timestamp: now.addingTimeInterval(-10 * 3600), state: .degraded),
            StatusEventSnapshot(id: UUID(), deviceID: nas.id, timestamp: now.addingTimeInterval(-10 * 3600 + 60), state: .online),
        ]
        let density = ActivityDensity(events: events, devices: [nas], range: .day, now: now)
        // Bucket 13 starts 11 hours ago, before the first event.
        #expect(density.buckets[13].online == 1)
        #expect(density.buckets.allSatisfy { $0.online == 1 })
    }

    @Test func devicesAppearOnlyAfterTheyWereFirstSeen() {
        let newcomer = device(.online, firstSeen: -2 * 3600)
        let density = ActivityDensity(events: [], devices: [newcomer], range: .day, now: now)
        #expect(density.buckets[21].online == 0)
        #expect(density.buckets[22].online == 1)
    }

    @Test func countUsesHalfOpenRanges() {
        let times = [0.0, 10, 10, 20].map { now.addingTimeInterval($0) }
        #expect(ActivityDensity.count(in: now..<now.addingTimeInterval(10), sortedTimes: times) == 1)
        #expect(ActivityDensity.count(in: now.addingTimeInterval(10)..<now.addingTimeInterval(21), sortedTimes: times) == 3)
        #expect(ActivityDensity.count(in: now.addingTimeInterval(30)..<now.addingTimeInterval(40), sortedTimes: times) == 0)
    }
}
