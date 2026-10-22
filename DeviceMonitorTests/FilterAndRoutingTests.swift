import Foundation
import Testing
@testable import DeviceMonitor

/// Noon on a fixed day, so the demo's "new" device and its counts do not depend on when the tests run.
private let fixedNow = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)).addingTimeInterval(12 * 3600)

/// The invariants between Overview's counters, the router and the Devices filters: a counter always equals
/// the list it opens, and the router only records where to go.
@Suite("Filters and routing")
@MainActor
struct FilterAndRoutingTests {
    @Test func everyCounterEqualsTheListItOpens() {
        let devices = DemoFixtures.devices(now: fixedNow)
        let model = DashboardModel(directory: DeviceDirectory(devices: devices))
        let counters = NetworkCounters.make(devices: devices, now: fixedNow)

        #expect(model.count(for: .online, now: fixedNow) == counters.online)
        #expect(model.count(for: .offline, now: fixedNow) == counters.offline)
        #expect(model.count(for: .new, now: fixedNow) == counters.recentArrivals)
        #expect(model.count(for: .strangers, now: fixedNow) == counters.strangers)
        #expect(counters == NetworkCounters(online: 12, offline: 2, recentArrivals: 1, strangers: 1))
        #expect(model.count(for: .all, now: fixedNow) == 14)
        #expect(model.count(for: .favorites, now: fixedNow) == 4)
    }

    @Test func routerStartsOnOverview() {
        let router = AppRouter()
        #expect(router.selectedTab == .overview)
        #expect(router.insightsSection == .security)
        #expect(router.pendingDeviceFilter == nil)
        #expect(router.pendingActivityFilter == nil)
    }

    @Test func showDevicesRecordsTheFilterAndKeepsTheSelection() {
        let router = AppRouter()
        let selected = UUID()
        router.selectedDeviceID = selected
        router.showDevices(filter: .offline)
        #expect(router.selectedTab == .devices)
        #expect(router.pendingDeviceFilter == .offline)
        #expect(router.selectedDeviceID == selected)
    }

    @Test func showActivityRecordsTheFilter() {
        let router = AppRouter()
        router.showActivity(filter: .outages)
        #expect(router.selectedTab == .activity)
        #expect(router.pendingActivityFilter == .outages)
    }

    @Test func showInsightsOpensTheSection() {
        let router = AppRouter()
        router.showInsights(.map)
        #expect(router.selectedTab == .insights)
        #expect(router.insightsSection == .map)
    }
}
