import Foundation
import Testing
@testable import DeviceMonitor

@Suite("Device classification")
struct DeviceClassifierTests {
    private func service(_ type: String, name: String = "Thing", txt: [String: String] = [:]) -> DiscoveredService {
        DiscoveredService(type: type, name: name, port: nil, txt: txt)
    }

    @Test func gatewayWins() {
        #expect(DeviceClassifier.kind(services: [service("_ipp._tcp")], openPorts: [], hostname: nil, vendor: nil, isGateway: true) == .router)
    }

    @Test func modelHintsBeatServiceTypes() {
        let airplay = service("_airplay._tcp", txt: ["model": "AppleTV14,1"])
        #expect(DeviceClassifier.kind(services: [airplay], openPorts: [], hostname: nil, vendor: nil, isGateway: false) == .tv)
        let homepod = service("_airplay._tcp", txt: ["model": "AudioAccessory5,1"])
        #expect(DeviceClassifier.kind(services: [homepod], openPorts: [], hostname: nil, vendor: nil, isGateway: false) == .hub)
        let macbookAir = service("_airplay._tcp", txt: ["model": "Mac14,2"])
        #expect(DeviceClassifier.kind(services: [macbookAir, service("_companion-link._tcp")], openPorts: [], hostname: nil, vendor: nil, isGateway: false) == .computer)
    }

    @Test func companionLinkIsOnlyALastResort() {
        let companion = service("_companion-link._tcp")
        #expect(DeviceClassifier.kind(services: [companion], openPorts: [], hostname: "Annas-iPad.local", vendor: nil, isGateway: false) == .tablet)
        #expect(DeviceClassifier.kind(services: [companion], openPorts: [], hostname: nil, vendor: nil, isGateway: false) == .phone)
    }

    @Test func serviceTypes() {
        #expect(DeviceClassifier.kind(services: [service("_ipp._tcp")], openPorts: [], hostname: nil, vendor: nil, isGateway: false) == .printer)
        #expect(DeviceClassifier.kind(services: [service("_googlecast._tcp")], openPorts: [], hostname: nil, vendor: nil, isGateway: false) == .tv)
        #expect(DeviceClassifier.kind(services: [service("_hap._tcp")], openPorts: [], hostname: nil, vendor: nil, isGateway: false) == .iot)
        #expect(DeviceClassifier.kind(services: [service("_smb._tcp"), service("_http._tcp")], openPorts: [], hostname: nil, vendor: nil, isGateway: false) == .nas)
        #expect(DeviceClassifier.kind(services: [service("_ssh._tcp")], openPorts: [], hostname: nil, vendor: nil, isGateway: false) == .computer)
    }

    @Test func hostnameAndPortFallbacks() {
        #expect(DeviceClassifier.kind(services: [], openPorts: [], hostname: "Annas-iPhone.local", vendor: nil, isGateway: false) == .phone)
        #expect(DeviceClassifier.kind(services: [], openPorts: [], hostname: "diskstation", vendor: nil, isGateway: false) == .nas)
        #expect(DeviceClassifier.kind(services: [], openPorts: [], hostname: "nas01.local", vendor: nil, isGateway: false) == .nas)
        #expect(DeviceClassifier.kind(services: [], openPorts: [], hostname: "jonas-macbook", vendor: nil, isGateway: false) == .computer)
        #expect(DeviceClassifier.kind(services: [], openPorts: [], hostname: "annas-ipadpro", vendor: nil, isGateway: false) == .tablet)
        #expect(DeviceClassifier.kind(services: [], openPorts: [], hostname: "front-door-cam", vendor: nil, isGateway: false) == .camera)
        #expect(DeviceClassifier.kind(services: [], openPorts: [], hostname: "shuey-pc", vendor: nil, isGateway: false) == .computer)
        #expect(DeviceClassifier.vendor(from: [], hostname: "shuey-pc") == nil)
        #expect(DeviceClassifier.kind(services: [], openPorts: [9100], hostname: nil, vendor: nil, isGateway: false) == .printer)
        #expect(DeviceClassifier.kind(services: [], openPorts: [554], hostname: nil, vendor: nil, isGateway: false) == .camera)
        #expect(DeviceClassifier.kind(services: [], openPorts: [62078], hostname: nil, vendor: nil, isGateway: false) == .phone)
        #expect(DeviceClassifier.kind(services: [], openPorts: [23], hostname: nil, vendor: nil, isGateway: false) == .iot)
        #expect(DeviceClassifier.kind(services: [], openPorts: [], hostname: nil, vendor: nil, isGateway: false) == .unknown)
    }

    @Test func vendorAndNames() {
        let txt = service("_printer._tcp", name: "Brother HL-L2350DW", txt: ["ty": "Brother HL-L2350DW series"])
        #expect(DeviceClassifier.vendor(from: [txt], hostname: nil) == "Brother HL-L2350DW series")
        #expect(DeviceClassifier.vendor(from: [], hostname: "DiskStation") == "Synology")
        #expect(DeviceClassifier.vendor(from: [], hostname: nil) == nil)
        #expect(DeviceClassifier.suggestedName(from: [], hostname: "living-room-tv.local", host: "10.0.0.9") == "Living Room Tv")
        #expect(DeviceClassifier.suggestedName(from: [txt], hostname: nil, host: "10.0.0.9") == "Brother HL-L2350DW")
        #expect(DeviceClassifier.suggestedName(from: [], hostname: nil, host: "10.0.0.9") == "Device 9")
        #expect(DeviceClassifier.suggestedName(from: [], hostname: nil, host: "fe80::1") == "fe80::1")
    }

    @Test func friendlyBonjourNamesBeatHostnames() {
        let airplay = service("_airplay._tcp", name: "Living Room")
        #expect(DeviceClassifier.suggestedName(from: [airplay], hostname: "apple-tv-4k.local", host: "10.0.0.9") == "Living Room")
        let raop = service("_raop._tcp", name: "C869CD123456@Kitchen")
        #expect(DeviceClassifier.suggestedName(from: [raop], hostname: nil, host: "10.0.0.9") == "Kitchen")
        let sonos = service("_sonos._tcp", name: "Sonos-ABC123@Living Room")
        #expect(DeviceClassifier.suggestedName(from: [sonos], hostname: "sonos-one.local", host: "10.0.0.9") == "Living Room")
        let generic = [service("_http._tcp", name: "device-a1b2c3"), service("_raop._tcp", name: "C869CD123456@"), service("_hap._tcp", name: " ")]
        #expect(DeviceClassifier.suggestedName(from: generic, hostname: "office-printer.local", host: "10.0.0.9") == "Office Printer")
        #expect(DeviceClassifier.suggestedName(from: generic, hostname: nil, host: "10.0.0.9") == "Device 9")
        let identifiers = [service("_apple-mobdev2._tcp", name: "f0:18:98:aa:bb:cc@fe80::f218:98ff:feaa:bbcc"), service("_matter._tcp", name: "A1B2C3D4E5F60718-00000000000000AB")]
        #expect(DeviceClassifier.suggestedName(from: identifiers, hostname: "annas-iphone.local", host: "10.0.0.9") == "Annas Iphone")
        let workstation = service("_workstation._tcp", name: "nas01 [00:11:32:ab:cd:ef]")
        #expect(DeviceClassifier.suggestedName(from: [workstation], hostname: nil, host: "10.0.0.9") == "nas01")
        let cast = service("_googlecast._tcp", name: "Chromecast-0123456789abcdef0123456789abcdef", txt: ["fn": "Bedroom TV"])
        #expect(DeviceClassifier.suggestedName(from: [cast], hostname: nil, host: "10.0.0.9") == "Bedroom TV")
        let castWithoutTXT = service("_googlecast._tcp", name: "Chromecast-0123456789abcdef0123456789abcdef")
        #expect(DeviceClassifier.suggestedName(from: [castWithoutTXT], hostname: nil, host: "10.0.0.9") == "Chromecast")
    }

    @Test func displayNamePrefersNicknameThenName() {
        var device = DeviceSnapshot(id: UUID(), name: "Office NAS", hostname: "diskstation", host: "10.0.0.7", firstSeen: Date())
        #expect(device.displayName == "Office NAS")
        #expect(device.addressLine == "10.0.0.7 · diskstation")
        device.nickname = "Backups"
        #expect(device.displayName == "Backups")
        device.nickname = nil
        device.name = ""
        #expect(device.displayName == "diskstation")
        #expect(device.addressLine == "10.0.0.7")
        device.hostname = nil
        #expect(device.displayName == "10.0.0.7")
    }

    /// Unit tests run inside the app, so `Bundle.main` is the built app with its merged Info.plist.
    @Test func catalogMatchesInfoPlist() throws {
        let declared = try #require(Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String])
        #expect(Set(declared) == Set(BonjourServiceCatalog.declaredTypes))
        #expect(declared.count == BonjourServiceCatalog.declaredTypes.count)
    }
}

@Suite("Security assessment")
struct SecurityAssessorTests {
    private func device(_ name: String, ports: [UInt16] = [], isTrusted: Bool = true, firstSeen: Date, isGateway: Bool = false, state: ReachabilityState = .online) -> DeviceSnapshot {
        DeviceSnapshot(id: UUID(), name: name, host: "10.0.0.\(name.count)", state: state, firstSeen: firstSeen, isTrusted: isTrusted, isGateway: isGateway, openPorts: ports)
    }

    @Test func perfectNetworkScoresHundred() {
        let now = Date()
        let score = SecurityAssessor.score(devices: [device("Router", firstSeen: now.addingTimeInterval(-86_400 * 3), isGateway: true), device("NAS", ports: [443, 22], firstSeen: now.addingTimeInterval(-86_400 * 3))], now: now)
        #expect(score.value == 100)
        #expect(score.findings.isEmpty)
        #expect(score.grade == "Excellent")
    }

    @Test func deductionsAreCapped() {
        let now = Date()
        let old = now.addingTimeInterval(-86_400 * 10)
        let risky = device("Legacy", ports: [21, 23, 445, 3389, 5900, 80, 8080, 1883, 5000, 554], firstSeen: old)
        let score = SecurityAssessor.score(devices: [risky], now: now)
        // 5 high → 75 capped at 45; 5 medium → 25 capped at 20 → 35
        #expect(score.value == 35)
        #expect(score.findings.count == 10)
        #expect(score.findings.first?.severity == .high)
    }

    @Test func newcomerAndGatewayPenalties() {
        let now = Date()
        let newcomer = device("Mystery", isTrusted: false, firstSeen: now.addingTimeInterval(-600))
        let gateway = device("Router", firstSeen: now.addingTimeInterval(-86_400), isGateway: true, state: .offline)
        let score = SecurityAssessor.score(devices: [newcomer, gateway], now: now)
        #expect(score.value == 80)
        #expect(score.findings.contains { $0.id == "untrusted-new" })
        #expect(score.findings.contains { $0.id == "gateway-unstable" })
    }

    @Test func factorsAddUpToTheScore() {
        let now = Date()
        let old = now.addingTimeInterval(-86_400 * 10)
        let networks: [[DeviceSnapshot]] = [
            [device("Router", firstSeen: old, isGateway: true)],
            [device("Legacy", ports: [21, 80], firstSeen: old)],
            [device("Mystery", isTrusted: false, firstSeen: now.addingTimeInterval(-600)), device("Router", firstSeen: old, isGateway: true, state: .degraded)],
            [device("Legacy", ports: [21, 23, 445, 3389, 5900, 80, 8080, 1883, 5000, 554], firstSeen: old)],
        ]
        for devices in networks {
            let score = SecurityAssessor.score(devices: devices, now: now)
            let lost = score.factors.reduce(0) { $0 + $1.pointsLost }
            #expect(100 - lost == score.value)
            #expect(score.factors.map(\.kind) == [.services, .newcomers, .router])
        }
    }

    @Test func fullyPenalisedNetworkHitsEveryCap() {
        let now = Date()
        let old = now.addingTimeInterval(-86_400 * 10)
        let devices = [
            device("Legacy", ports: [21, 23, 445, 3389, 5900, 80, 8080, 1883, 5000, 554], firstSeen: old),
            device("Mystery", isTrusted: false, firstSeen: now.addingTimeInterval(-600)),
            device("Router", firstSeen: old, isGateway: true, state: .offline),
        ]
        let score = SecurityAssessor.score(devices: devices, now: now)
        #expect(score.factors.map(\.pointsLost) == [65, 10, 10])
        #expect(score.factors.map(\.maximum) == [65, 10, 10])
        #expect(score.value == 15)
    }

    @Test func cleanNetworkLosesNoPoints() {
        let now = Date()
        let old = now.addingTimeInterval(-86_400 * 3)
        let score = SecurityAssessor.score(devices: [device("Router", firstSeen: old, isGateway: true), device("NAS", ports: [443, 22], firstSeen: old)], now: now)
        #expect(score.factors.count == 3)
        #expect(score.factors.allSatisfy { $0.pointsLost == 0 })
        #expect(score.factors.map(\.title) == ["Open services", "Unknown devices", "Router stability"])
    }

    @Test func routerServicesAreExpectedOnlyOnTheGateway() {
        let now = Date()
        let old = now.addingTimeInterval(-86_400 * 10)
        let router = device("Router", ports: [23, 53, 80, 443, 8443], firstSeen: old, isGateway: true)
        let score = SecurityAssessor.score(devices: [router], now: now)
        #expect(score.value == 85)
        #expect(score.findings.map(\.id) == ["port-\(router.id.uuidString)-23"])
        let printer = device("Printer", ports: [53, 80], firstSeen: old)
        #expect(SecurityAssessor.score(devices: [printer], now: now).value == 90)
        #expect(SecurityAssessor.risk(port: 80, isGateway: true) == .low)
        #expect(SecurityAssessor.risk(port: 80, isGateway: false) == .medium)
        #expect(SecurityAssessor.risk(port: 23, isGateway: true) == .high)
    }

    @Test func portKnowledge() {
        #expect(SecurityAssessor.risk(port: 23) == .high)
        #expect(SecurityAssessor.risk(port: 80) == .medium)
        #expect(SecurityAssessor.risk(port: 443) == .low)
        #expect(SecurityAssessor.serviceName(port: 22) == "SSH")
        #expect(SecurityAssessor.serviceName(port: 4242) == "Port 4242")
        #expect(SecurityAssessor.advice(port: 23).contains("Telnet"))
    }
}
