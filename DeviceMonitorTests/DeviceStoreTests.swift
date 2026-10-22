import Foundation
import SwiftData
import Testing
@testable import DeviceMonitor

@Suite("Device store", .serialized)
@MainActor
struct DeviceStoreTests {
    private let clock = FixedDateProvider(Date(timeIntervalSince1970: 1_700_000_000))

    private func makeStore(limits: StorageLimits = .standard) throws -> DeviceStore {
        DeviceStore(container: try ModelContainerFactory.makeInMemory(), limits: limits, dateProvider: clock)
    }

    private func probe(_ host: String, up: Bool, offset: TimeInterval = 0, latency: Double = 5) -> ProbeResult {
        ProbeResult(host: host, port: 80, kind: .tcp, outcome: up ? .reachable(latencyMilliseconds: latency) : .timedOut, timestamp: clock.now().addingTimeInterval(offset))
    }

    private func record(_ store: DeviceStore, _ id: UUID, _ result: ProbeResult, _ tracker: ReachabilityTracker, _ transition: ReachabilityTransition?) throws {
        _ = try store.applyProbeBatch([(deviceID: id, result: result, tracker: tracker, transition: transition)])
    }

    @Test func manualAddValidatesAndRejectsDuplicates() throws {
        let store = try makeStore()
        let added = try store.addManual(name: "Office Camera", host: " 192.168.1.44 ", preferredPort: 8080)
        #expect(added.host == "192.168.1.44")
        #expect(added.isUserAdded)
        #expect(added.preferredPort == 8080)
        #expect(added.state == .unknown)
        #expect(throws: DeviceMonitorError.duplicateDevice(host: "192.168.1.44")) {
            try store.addManual(name: "Again", host: "192.168.1.44", preferredPort: nil)
        }
        #expect(throws: DeviceMonitorError.self) {
            try store.addManual(name: "", host: "10.0.0.1", preferredPort: nil)
        }
        #expect(throws: DeviceMonitorError.self) {
            try store.addManual(name: "Bad", host: "300.1.1.1", preferredPort: nil)
        }
        let all = try store.loadSnapshots()
        #expect(all.count == 1)
    }

    @Test func discoveryMergesByIdentityAndKeepsUserData() throws {
        let store = try makeStore()
        let printer = DiscoveredHost(host: "10.0.0.20", hostname: "brother.local", services: [DiscoveredService(type: "_ipp._tcp", name: "Brother", port: 631, txt: [:])], probe: probe("10.0.0.20", up: true))
        let first = try store.upsert(discovered: [printer], networkKey: "net-1")
        let id = try #require(first.first?.id)
        #expect(first.first?.kind == .printer)
        #expect(first.first?.state == .online)
        #expect(first.first?.hostname == "brother")

        let stored = try store.snapshot(id: id)
        var edit = DeviceEdit(snapshot: try #require(stored))
        edit.nickname = "Kitchen Printer"
        edit.tags = ["office", " Office ", "", "printing"]
        edit.notes = "Paper tray sticks."
        edit.isFavorite = true
        let maybeEdited = try store.applyEdit(edit)
        let edited = try #require(maybeEdited)
        #expect(edited.tags == ["office", "printing"])

        // Same hostname, new address → same device, nickname preserved.
        let moved = DiscoveredHost(host: "10.0.0.99", hostname: "brother.local", services: [], probe: probe("10.0.0.99", up: true, offset: 60))
        let second = try store.upsert(discovered: [moved], networkKey: "net-1")
        #expect(second.count == 1)
        #expect(second.first?.id == id)
        #expect(second.first?.host == "10.0.0.99")
        #expect(second.first?.nickname == "Kitchen Printer")
        #expect(second.first?.displayName == "Kitchen Printer")
        #expect(second.first?.isFavorite == true)
        let all = try store.loadSnapshots()
        #expect(all.count == 1)
    }

    @Test func scanJoinsTheDeviceBonjourAlreadyFound() throws {
        let store = try makeStore()
        let bonjour = DiscoveredHost(host: "10.0.0.20", hostname: "brother.local", services: [DiscoveredService(type: "_ipp._tcp", name: "Brother", port: 631, txt: [:])], probe: probe("10.0.0.20", up: true))
        _ = try store.upsert(discovered: [bonjour], networkKey: nil)
        let scanned = DiscoveredHost(host: "10.0.0.20", probe: probe("10.0.0.20", up: true, offset: 30))
        let merged = try store.upsert(discovered: [scanned], networkKey: nil)
        let all = try store.loadSnapshots()
        #expect(all.count == 1)
        #expect(merged.first?.hostname == "brother")
    }

    @Test func raopNameCollapsesWithAirPlayAndFillsTheMAC() throws {
        let store = try makeStore()
        let airplay = DiscoveredHost(host: "10.0.0.30", services: [DiscoveredService(type: "_raop._tcp", name: "C869CD123456@Living Room", port: 7000, txt: [:])])
        let first = try store.upsert(discovered: [airplay], networkKey: nil)
        #expect(first.first?.macAddress == "C8:69:CD:12:34:56")
        #expect(first.first?.canWake == true)
        let again = DiscoveredHost(host: "10.0.0.30", services: [DiscoveredService(type: "_raop._tcp", name: "C869CD123456@Living Room", port: 7000, txt: [:])])
        _ = try store.upsert(discovered: [again], networkKey: nil)
        let all = try store.loadSnapshots()
        #expect(all.count == 1)
    }

    @Test func hostnameDeviceCannotBeAddedTwiceAfterItMoved() throws {
        let store = try makeStore()
        _ = try store.addManual(name: "NAS", host: "nas.local", preferredPort: nil)
        let found = DiscoveredHost(host: "10.0.0.7", hostname: "nas.local", services: [], probe: probe("10.0.0.7", up: true))
        _ = try store.upsert(discovered: [found], networkKey: nil)
        #expect(throws: DeviceMonitorError.duplicateDevice(host: "nas.local")) {
            try store.addManual(name: "NAS again", host: "nas.local", preferredPort: nil)
        }
    }

    @Test func addressOnlyDeviceGetsUpgradedIdentity() throws {
        let store = try makeStore()
        let manual = try store.addManual(name: "Unknown box", host: "10.0.0.7", preferredPort: nil)
        let discovered = DiscoveredHost(host: "10.0.0.7", hostname: "nas.local", services: [DiscoveredService(type: "_smb._tcp", name: "NAS", port: 445, txt: [:]), DiscoveredService(type: "_http._tcp", name: "NAS", port: 80, txt: [:])], probe: probe("10.0.0.7", up: true))
        let merged = try store.upsert(discovered: [discovered], networkKey: nil)
        #expect(merged.first?.id == manual.id)
        #expect(merged.first?.kind == .nas)
        #expect(merged.first?.isUserAdded == true)
        #expect(merged.first?.name == "Unknown box")
        #expect(merged.first?.displayName == "Unknown box")
        let all = try store.loadSnapshots()
        #expect(all.count == 1)
    }

    @Test func discoveredNamesFollowNewEvidence() throws {
        let store = try makeStore()
        let scanned = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.42", probe: probe("10.0.0.42", up: true))], networkKey: nil)
        #expect(scanned.first?.name == "Device 42")

        let named = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.42", hostname: "apple-tv.local")], networkKey: nil)
        #expect(named.first?.name == "Apple Tv")

        let airplay = DiscoveredService(type: "_airplay._tcp", name: "Living Room", port: 7000, txt: [:])
        let bonjour = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.42", hostname: "apple-tv.local", services: [airplay])], networkKey: nil)
        #expect(bonjour.first?.name == "Living Room")
        #expect(bonjour.first?.displayName == "Living Room")
        #expect(bonjour.first?.addressLine == "10.0.0.42 · apple-tv")

        // A later bare scan carries no naming evidence and keeps the Bonjour name.
        let rescanned = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.42", probe: probe("10.0.0.42", up: true, offset: 30))], networkKey: nil)
        #expect(rescanned.first?.name == "Living Room")
        let all = try store.loadSnapshots()
        #expect(all.count == 1)
    }

    @Test func statusEventsOnlyOnTransitionsAndLatencySpacing() throws {
        let store = try makeStore()
        let device = try store.addManual(name: "Sensor", host: "10.0.0.30", preferredPort: nil)
        var tracker = ReachabilityTracker()

        let hit = probe("10.0.0.30", up: true, offset: 0)
        let t1 = tracker.record(hit, policy: .standard)
        try record(store, device.id, hit, tracker, t1)

        let hitSoon = probe("10.0.0.30", up: true, offset: 3, latency: 9)
        let t2 = tracker.record(hitSoon, policy: .standard)
        try record(store, device.id, hitSoon, tracker, t2)

        let hitLater = probe("10.0.0.30", up: true, offset: 30, latency: 12)
        let t3 = tracker.record(hitLater, policy: .standard)
        try record(store, device.id, hitLater, tracker, t3)

        for offset in [60.0, 90, 120] {
            let miss = probe("10.0.0.30", up: false, offset: offset)
            let transition = tracker.record(miss, policy: .standard)
            try record(store, device.id, miss, tracker, transition)
        }

        let events = try store.statusEvents(deviceID: device.id, limit: 10)
        #expect(events.map(\.state) == [.offline, .degraded, .online])
        let samples = try store.latencySamples(deviceID: device.id, since: .distantPast)
        #expect(samples.map(\.milliseconds) == [5, 12])
        let maybeSnapshot = try store.snapshot(id: device.id)
        let snapshot = try #require(maybeSnapshot)
        #expect(snapshot.state == .offline)
        #expect(snapshot.latencyMilliseconds == nil)
        #expect(snapshot.lastSeen == clock.now().addingTimeInterval(30))
        let recent = try store.recentEvents(since: clock.now().addingTimeInterval(-1), limit: 10)
        #expect(recent.count == 3)
    }

    @Test func pruningRespectsLimits() throws {
        var limits = StorageLimits()
        limits.maxStatusEventsPerDevice = 3
        limits.maxLatencySamplesPerDevice = 2
        limits.minLatencySampleSpacingSeconds = 0
        let store = try makeStore(limits: limits)
        let device = try store.addManual(name: "Flappy", host: "10.0.0.40", preferredPort: nil)
        var tracker = ReachabilityTracker()
        var up = true
        for index in 0..<12 {
            let result = probe("10.0.0.40", up: up, offset: Double(index) * 30)
            let transition = tracker.record(result, policy: .standard)
            try record(store, device.id, result, tracker, transition)
            if index % 3 == 2 { up.toggle() }
        }
        let events = try store.statusEvents(deviceID: device.id, limit: 100)
        let samples = try store.latencySamples(deviceID: device.id, since: .distantPast)
        let pruned = try store.pruneHistory()
        #expect(events.count <= 3)
        #expect(samples.count <= 2)
        #expect(pruned == 0)
    }

    @Test func deleteCascades() throws {
        let store = try makeStore()
        let device = try store.addManual(name: "Temp", host: "10.0.0.50", preferredPort: nil)
        var tracker = ReachabilityTracker()
        let result = probe("10.0.0.50", up: true)
        let transition = tracker.record(result, policy: .standard)
        try record(store, device.id, result, tracker, transition)
        try store.delete(ids: [device.id])
        let remaining = try store.loadSnapshots()
        let events = try store.modelContext.fetch(FetchDescriptor<StatusEvent>())
        let samples = try store.modelContext.fetch(FetchDescriptor<LatencySample>())
        #expect(remaining.isEmpty)
        #expect(events.isEmpty)
        #expect(samples.isEmpty)
    }

    @Test func editValidation() throws {
        let store = try makeStore()
        let device = try store.addManual(name: "Edit me", host: "10.0.0.60", preferredPort: nil)
        var edit = DeviceEdit(snapshot: device)
        edit.macAddress = "nope"
        #expect(throws: DeviceMonitorError.self) { try store.applyEdit(edit) }
        edit.macAddress = "aa-bb-cc-dd-ee-ff"
        edit.kind = .camera
        edit.notes = String(repeating: "x", count: 5000)
        let maybeSaved = try store.applyEdit(edit)
        let saved = try #require(maybeSaved)
        #expect(saved.macAddress == "AA:BB:CC:DD:EE:FF")
        #expect(saved.kind == .camera)
        #expect(saved.notes.count == StorageLimits.standard.maxNotesLength)
        #expect(saved.canWake)
        // A later discovery must not override a user-chosen kind.
        let rediscovered = DiscoveredHost(host: "10.0.0.60", hostname: "edit-me.local", services: [DiscoveredService(type: "_ipp._tcp", name: "P", port: 631, txt: [:])])
        let merged = try store.upsert(discovered: [rediscovered], networkKey: nil)
        #expect(merged.first?.kind == .camera)
        var missing = DeviceEdit(snapshot: device)
        missing = DeviceEdit(snapshot: DeviceSnapshot(id: UUID(), name: "ghost", host: "0.0.0.0", firstSeen: clock.now()))
        #expect(throws: DeviceMonitorError.self) { try store.applyEdit(missing) }
    }

    @Test func gatewayMarkingAndNetworks() throws {
        let store = try makeStore()
        let router = try store.addManual(name: "Router", host: "192.168.1.1", preferredPort: nil)
        let changed = try store.markGateway(hosts: ["192.168.1.1"])
        #expect(changed.first?.id == router.id)
        #expect(changed.first?.isGateway == true)
        #expect(changed.first?.kind == .router)
        try store.recordNetwork(key: "k", displayName: "Home", gatewayHost: "192.168.1.1", subnetCIDR: "192.168.1.0/24")
        try store.recordNetwork(key: "k", displayName: "Home", gatewayHost: "192.168.1.1", subnetCIDR: "192.168.1.0/24")
        let networks = try store.knownNetworks()
        let all = try store.loadSnapshots()
        #expect(networks.count == 1)
        #expect(all.first?.isGateway == true)
    }

    // MARK: - One device, many services

    @Test func airPlayThenRAOPIsOneDevice() throws {
        let store = try makeStore()
        let airplay = DiscoveredService(type: "_airplay._tcp", name: "Living Room", port: 7000, txt: [:])
        let raop = DiscoveredService(type: "_raop._tcp", name: "C869CD123456@Living Room", port: 7000, txt: [:])
        let first = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.30", services: [airplay])], networkKey: nil)
        let second = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.30", services: [raop])], networkKey: nil)
        #expect(second.first?.id == first.first?.id)
        #expect(second.first?.macAddress == "C8:69:CD:12:34:56")
        #expect(second.first?.canWake == true)
        #expect(second.first?.name == "Living Room")
        let all = try store.loadSnapshots()
        #expect(all.count == 1)
    }

    @Test func raopThenAirPlayIsOneDeviceAndKeepsTheMAC() throws {
        let store = try makeStore()
        let raop = DiscoveredService(type: "_raop._tcp", name: "C869CD123456@Living Room", port: 7000, txt: [:])
        let airplay = DiscoveredService(type: "_airplay._tcp", name: "Living Room", port: 7000, txt: [:])
        let companion = DiscoveredService(type: "_companion-link._tcp", name: "Living Room", port: nil, txt: [:])
        _ = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.30", services: [raop])], networkKey: nil)
        _ = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.30", services: [airplay])], networkKey: nil)
        _ = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.30", services: [companion])], networkKey: nil)
        // A later RAOP sighting still finds the device by its MAC.
        _ = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.30", services: [raop])], networkKey: nil)
        let all = try store.loadSnapshots()
        #expect(all.count == 1)
        #expect(all.first?.macAddress == "C8:69:CD:12:34:56")
        #expect(all.first?.services.count == 3)
    }

    @Test func wifiSyncJoinsThePhoneAtItsAddress() throws {
        let store = try makeStore()
        let companion = DiscoveredService(type: "_companion-link._tcp", name: "Anton’s iPhone", port: nil, txt: [:])
        let wifiSync = DiscoveredService(type: "_apple-mobdev2._tcp", name: "a8:5c:2c:12:34:56@fe80::1", port: 62078, txt: [:])
        let first = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.31", services: [companion])], networkKey: nil)
        let second = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.31", services: [wifiSync])], networkKey: nil)
        #expect(second.first?.id == first.first?.id)
        #expect(second.first?.name == "Anton’s iPhone")
        #expect(second.first?.macAddress == "A8:5C:2C:12:34:56")
        let all = try store.loadSnapshots()
        #expect(all.count == 1)
    }

    @Test func servicesOfOneHostnameAreOneDevice() throws {
        let store = try makeStore()
        // The real resolver reports the SRV target ("NAS.local."), the same for every service of a host.
        let smb = DiscoveredService(type: "_smb._tcp", name: "NAS", port: 445, txt: [:])
        let web = DiscoveredService(type: "_http._tcp", name: "DiskStation", port: 5000, txt: [:])
        _ = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.7", hostname: "NAS.local.", services: [smb])], networkKey: nil)
        _ = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.7", hostname: "NAS.local.", services: [web])], networkKey: nil)
        let all = try store.loadSnapshots()
        #expect(all.count == 1)
        #expect(all.first?.hostname == "nas")
        #expect(all.first?.webURL?.absoluteString == "http://10.0.0.7:5000")
    }

    @Test func bonjourJoinsTheDeviceTheUserAddedByHostname() throws {
        let store = try makeStore()
        let manual = try store.addManual(name: "NAS", host: "nas.local", preferredPort: nil)
        let smb = DiscoveredService(type: "_smb._tcp", name: "NAS", port: 445, txt: [:])
        let merged = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.7", hostname: "NAS.local.", services: [smb])], networkKey: "net-1")
        #expect(merged.first?.id == manual.id)
        #expect(merged.first?.host == "10.0.0.7")
        let all = try store.loadSnapshots()
        #expect(all.count == 1)
    }

    @Test func differentHostnamesAtOneAddressStayApart() throws {
        let store = try makeStore()
        let first = DiscoveredService(type: "_ipp._tcp", name: "Office", port: 631, txt: [:])
        let second = DiscoveredService(type: "_smb._tcp", name: "Basement", port: 445, txt: [:])
        _ = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.50", hostname: "printer.local", services: [first])], networkKey: nil)
        // The address was handed to another host.
        _ = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.50", hostname: "nas.local", services: [second])], networkKey: nil)
        let all = try store.loadSnapshots()
        #expect(all.count == 2)
    }

    // MARK: - Networks

    @Test func otherNetworksNeverMergeByAddressOrName() throws {
        let store = try makeStore()
        let home = try store.upsert(discovered: [DiscoveredHost(host: "192.168.1.20", probe: probe("192.168.1.20", up: true))], networkKey: "net-home")
        let homeDevice = try #require(home.first)
        var edit = DeviceEdit(snapshot: homeDevice)
        edit.nickname = "Anna's MacBook"
        edit.isTrusted = true
        _ = try store.applyEdit(edit)

        // A café that also uses 192.168.1.0/24.
        let cafe = try store.upsert(discovered: [DiscoveredHost(host: "192.168.1.20", probe: probe("192.168.1.20", up: true, offset: 60))], networkKey: "net-cafe")
        #expect(cafe.first?.id != homeDevice.id)
        #expect(cafe.first?.nickname == nil)
        #expect(cafe.first?.isTrusted == false)
        let maybeHome = try store.snapshot(id: homeDevice.id)
        let homeAfter = try #require(maybeHome)
        #expect(homeAfter.networkKey == "net-home")
        #expect(homeAfter.nickname == "Anna's MacBook")

        // Bonjour names repeat between homes; only a MAC follows a device to another network.
        let airplay = DiscoveredService(type: "_airplay._tcp", name: "Living Room", port: 7000, txt: [:])
        _ = try store.upsert(discovered: [DiscoveredHost(host: "192.168.1.30", services: [airplay])], networkKey: "net-home")
        _ = try store.upsert(discovered: [DiscoveredHost(host: "192.168.1.30", services: [airplay])], networkKey: "net-cafe")
        let raop = DiscoveredService(type: "_raop._tcp", name: "C869CD123456@Kitchen", port: 7000, txt: [:])
        _ = try store.upsert(discovered: [DiscoveredHost(host: "192.168.1.40", services: [raop])], networkKey: "net-home")
        _ = try store.upsert(discovered: [DiscoveredHost(host: "10.0.0.40", services: [raop])], networkKey: "net-cafe")
        let all = try store.loadSnapshots()
        #expect(all.count == 5)
        #expect(all.filter { $0.macAddress == "C8:69:CD:12:34:56" }.count == 1)
    }

    @Test func manualAddressesCanBeScopedToTheirNetwork() throws {
        let store = try makeStore()
        let scoped = try store.addManual(name: "Camera", host: "192.168.1.44", preferredPort: nil, networkKey: "net-home")
        let global = try store.addManual(name: "Server", host: "example.com", preferredPort: nil)
        #expect(scoped.networkKey == "net-home")
        #expect(global.networkKey == nil)
    }

    @Test func gatewayMarkingLeavesOtherNetworksAlone() throws {
        let store = try makeStore()
        let homeRouter = try store.upsert(discovered: [DiscoveredHost(host: "192.168.1.1", probe: probe("192.168.1.1", up: true))], networkKey: "net-home", gatewayHosts: ["192.168.1.1"])
        #expect(homeRouter.first?.isGateway == true)
        let changed = try store.markGateway(hosts: ["10.0.0.1"], networkKey: "net-office")
        #expect(changed.isEmpty)
        let routerID = try #require(homeRouter.first?.id)
        let maybeRouter = try store.snapshot(id: routerID)
        #expect(maybeRouter?.isGateway == true)
    }

    // MARK: - Edits, ports and history

    @Test func rejectedEditLeavesTheDeviceUnchanged() throws {
        let store = try makeStore()
        let device = try store.addManual(name: "Tablet", host: "10.0.0.61", preferredPort: nil)
        var edit = DeviceEdit(snapshot: device)
        edit.nickname = "Kids iPad"
        edit.kind = .camera
        edit.isTrusted = true
        edit.macAddress = "AA:BB:CC:DD:EE"
        #expect(throws: DeviceMonitorError.self) { try store.applyEdit(edit) }
        // Every later write saves the shared context; nothing of the rejected edit may come along.
        try store.save()
        let maybeStored = try store.snapshot(id: device.id)
        let stored = try #require(maybeStored)
        #expect(stored.nickname == nil)
        #expect(stored.kind == device.kind)
        #expect(stored.isTrusted == false)
    }

    @Test func emptyPortScanKeepsAKnownKind() throws {
        let store = try makeStore()
        let device = try store.addManual(name: "Printer", host: "10.0.0.62", preferredPort: nil)
        let printer = try store.setOpenPorts(deviceID: device.id, ports: [9100])
        #expect(printer?.kind == .printer)
        let after = try store.setOpenPorts(deviceID: device.id, ports: [])
        #expect(after?.kind == .printer)
        #expect(after?.openPorts.isEmpty == true)
    }

    @Test func recentEventsWithoutALimitReturnEverything() throws {
        let store = try makeStore()
        let device = try store.addManual(name: "Flappy", host: "10.0.0.63", preferredPort: nil)
        var tracker = ReachabilityTracker()
        for index in 0..<8 {
            let result = probe("10.0.0.63", up: index.isMultiple(of: 2), offset: Double(index) * 30)
            let transition = tracker.record(result, policy: .standard)
            try record(store, device.id, result, tracker, transition)
        }
        let all = try store.recentEvents(since: .distantPast)
        let limited = try store.recentEvents(since: .distantPast, limit: 2)
        #expect(all.count > 2)
        #expect(limited.count == 2)
    }

    @Test func sampleDevicesFromVersionOneAreRemoved() throws {
        let store = try makeStore()
        // What the 1.0 → 2.0 migration leaves: an empty identity and `distantPast` as first sighting.
        let sample = Device(name: "Camera-01", ipAddress: "192.168.1.10", firstSeen: .distantPast)
        let own = Device(name: "My NAS", ipAddress: "192.168.1.5", isUserAdded: true, firstSeen: .distantPast)
        store.modelContext.insert(sample)
        store.modelContext.insert(own)
        store.modelContext.insert(StatusEvent(timestamp: clock.now(), isOnline: true, stateRaw: "online", device: sample))
        try store.save()
        _ = try store.upsert(discovered: [DiscoveredHost(host: "192.168.1.11", probe: probe("192.168.1.11", up: true))], networkKey: nil)

        let removed = try store.removeMigratedSampleDevices()
        #expect(removed == 1)
        let names = try store.loadSnapshots().map(\.name).sorted()
        #expect(names == ["Device 11", "My NAS"])
        // Only the scanned device's own arrival remains; the sample's history went with it.
        let events = try store.modelContext.fetch(FetchDescriptor<StatusEvent>())
        #expect(events.count == 1)
    }
}
