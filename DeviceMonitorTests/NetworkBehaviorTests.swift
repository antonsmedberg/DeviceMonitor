import Foundation
import Testing
@testable import DeviceMonitor

@Suite("Network path")
struct NetworkPathTests {
    private func reading(_ satisfied: Bool, interface: String? = nil, gateways: [String] = [], expensive: Bool = false, denied: Bool = false) -> PathReading {
        PathReading(isSatisfied: satisfied, interfaceName: interface, gatewayHosts: gateways, isExpensive: expensive, isConstrained: false, isLocalNetworkDenied: denied)
    }

    @Test func wifiWithoutInternetStillCountsAsTheLAN() {
        // The router's internet is down: iOS keeps Wi‑Fi joined and routes the default over cellular.
        let status = NetworkPathObserver.combine(
            general: reading(true, expensive: true),
            wifi: reading(true, interface: "en0", gateways: ["192.168.1.1"]),
            wired: reading(false)
        )
        #expect(status.isWiFi)
        #expect(status.isSatisfied)
        #expect(status.wifiInterfaceName == "en0")
        #expect(status.gatewayHosts == ["192.168.1.1"])
        #expect(status.isExpensive)
    }

    @Test func wifiWithoutInternetOrCellularIsStillSatisfied() {
        let status = NetworkPathObserver.combine(
            general: reading(false),
            wifi: reading(true, interface: "en0", gateways: ["192.168.1.1"]),
            wired: reading(false)
        )
        #expect(status.isSatisfied)
        #expect(status.isWiFi)
    }

    @Test func cellularOnlyIsNotTheLAN() {
        let status = NetworkPathObserver.combine(
            general: reading(true, gateways: ["10.64.0.1"], expensive: true),
            wifi: reading(false),
            wired: reading(false)
        )
        #expect(status.isSatisfied)
        #expect(!status.isWiFi)
        #expect(status.gatewayHosts.isEmpty)
        #expect(status.wifiInterfaceName == nil)
    }

    @Test func ethernetCountsWhenWiFiIsOff() {
        let status = NetworkPathObserver.combine(
            general: reading(true),
            wifi: reading(false),
            wired: reading(true, interface: "en2", gateways: ["10.0.0.1"])
        )
        #expect(status.isWiFi)
        #expect(status.wifiInterfaceName == "en2")
        #expect(status.gatewayHosts == ["10.0.0.1"])
    }

    @Test func denialOnAnyPathIsReported() {
        let status = NetworkPathObserver.combine(general: reading(true), wifi: reading(false, denied: true), wired: reading(false))
        #expect(status.isLocalNetworkDenied)
    }

    @Test func nothingIsReportedUntilGeneralAndWiFiAnswered() {
        let readings = PathReadings()
        #expect(readings.record(reading(false), from: .wired) == nil)
        #expect(readings.record(reading(true), from: .general) == nil)
        let status = readings.record(reading(true, interface: "en0"), from: .wifi)
        #expect(status?.isWiFi == true)
        #expect(status?.wifiInterfaceName == "en0")
    }
}

@Suite("Scanning")
struct ScanningTests {
    @Test func timeCeilingCoversTheWholeSubnet() {
        // Three probes of 1.5 s, each with its fallback margin: an empty address costs 5.25 s.
        let perHost = 3 * (1.5 + ScanRequest.probeOverheadSeconds)
        let slash24 = ScanRequest.durationCeiling(hostCount: 254, concurrency: 32, perHostSeconds: perHost)
        let slash22 = ScanRequest.durationCeiling(hostCount: 1022, concurrency: 32, perHostSeconds: perHost)
        #expect(slash24 == 60)
        #expect(slash22 >= 1022.0 / 32 * perHost)
        #expect(slash22 < 300)
        #expect(ScanRequest.durationCeiling(hostCount: 0, concurrency: 0, perHostSeconds: perHost) == 60)
    }

    @Test func silentHostProvesNothing() async {
        let silent = DemoProbe(script: ["10.0.0.9": [.timedOut]])
        let report = await PortScanner(probe: silent).scan(host: "10.0.0.9", ports: [22, 80, 443])
        #expect(!report.hostAnswered)
        #expect(!report.permissionDenied)
        #expect(report.results.count == 3)
        #expect(report.results.allSatisfy { !$0.isOpen })
    }

    @Test func refusedPortsProveTheHostIsUp() async {
        let report = await PortScanner(probe: DemoPortProbe(openPorts: [22])).scan(host: "10.0.0.9", ports: [22, 80])
        #expect(report.hostAnswered)
        #expect(report.results.filter(\.isOpen).map(\.port) == [22])
    }

    @Test func deniedScanIsReported() async {
        let denied = DemoProbe(script: ["10.0.0.9": [.permissionDenied]])
        let report = await PortScanner(probe: denied).scan(host: "10.0.0.9", ports: [22])
        #expect(report.permissionDenied)
        #expect(!report.hostAnswered)
        #expect(report.results.isEmpty)
    }
}

@Suite("Monitoring rounds")
struct MonitoringRoundTests {
    @Test func backedOffDevicesDoNotHoldTheRound() {
        let settings = MonitorSettings.standard
        let online = MonitoredTarget(id: UUID(), host: "10.0.0.1", tracker: ReachabilityTracker(state: .online, confidence: 1, lastSeen: nil))
        let justOffline = MonitoredTarget(id: UUID(), host: "10.0.0.2", tracker: ReachabilityTracker(state: .offline, confidence: 0, lastSeen: nil))
        var backedOffTracker = ReachabilityTracker(state: .offline, confidence: 0, lastSeen: nil)
        _ = backedOffTracker.record(ProbeResult(host: "10.0.0.3", port: nil, kind: .tcp, outcome: .timedOut, timestamp: Date()), policy: .standard)
        let backedOff = MonitoredTarget(id: UUID(), host: "10.0.0.3", tracker: backedOffTracker)
        #expect(ProbeSchedule.intervalSeconds(for: backedOffTracker, settings: settings) > settings.baseIntervalSeconds)

        let targets = Dictionary(uniqueKeysWithValues: [online, justOffline, backedOff].map { ($0.id, $0) })
        let members = MonitorEngine.roundMembers(of: targets, settings: settings)
        #expect(members == [online.id, justOffline.id])
    }
}

@Suite("Device links")
struct DeviceLinkTests {
    private func device(ports: [UInt16] = [], services: [DiscoveredService] = [], host: String = "10.0.0.7") -> DeviceSnapshot {
        DeviceSnapshot(id: UUID(), name: "NAS", host: host, firstSeen: Date(timeIntervalSince1970: 0), openPorts: ports, services: services)
    }

    private func service(_ type: String, port: UInt16?) -> DiscoveredService {
        DiscoveredService(type: type, name: "NAS", port: port, txt: [:])
    }

    @Test func advertisedPortsAreUsed() {
        #expect(device(services: [service("_http._tcp", port: 8080)]).webURL?.absoluteString == "http://10.0.0.7:8080")
        #expect(device(services: [service("_https._tcp", port: 5001)]).webURL?.absoluteString == "https://10.0.0.7:5001")
        #expect(device(services: [service("_ssh._tcp", port: 2222)]).sshURL?.absoluteString == "ssh://10.0.0.7:2222")
        #expect(device(services: [service("_rfb._tcp", port: 5901)]).vncURL?.absoluteString == "vnc://10.0.0.7:5901")
    }

    @Test func defaultPortsAreLeftOut() {
        #expect(device(services: [service("_http._tcp", port: 80)]).webURL?.absoluteString == "http://10.0.0.7")
        #expect(device(services: [service("_https._tcp", port: nil)]).webURL?.absoluteString == "https://10.0.0.7")
        #expect(device(services: [service("_sftp-ssh._tcp", port: 22)]).sshURL?.absoluteString == "ssh://10.0.0.7")
    }

    @Test func openPortsAreTheFallback() {
        #expect(device(ports: [443, 80]).webURL?.absoluteString == "https://10.0.0.7")
        #expect(device(ports: [8080]).webURL?.absoluteString == "http://10.0.0.7:8080")
        #expect(device(ports: [22]).sshURL?.absoluteString == "ssh://10.0.0.7")
        #expect(device().webURL == nil)
    }

    @Test func ipv6HostsKeepTheirBrackets() {
        #expect(device(services: [service("_http._tcp", port: 8080)], host: "fe80::1").webURL?.absoluteString == "http://[fe80::1]:8080")
    }
}

@Suite("Store recovery")
struct StoreRecoveryTests {
    @Test func aMissingStoreIsNotATransientProblem() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).store")
        #expect(!ModelContainerFactory.environmentLooksTransient(storeURL: missing))
    }

    @Test func aReadableStoreWithRoomToMigrateIsNotTransient() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("readable-\(UUID().uuidString).store")
        try Data(repeating: 0, count: 1024).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(!ModelContainerFactory.environmentLooksTransient(storeURL: url))
    }
}
