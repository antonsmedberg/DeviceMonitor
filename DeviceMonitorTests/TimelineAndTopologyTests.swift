import Foundation
import Testing
@testable import DeviceMonitor

@Suite("Network timeline")
struct NetworkTimelineBuilderTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(_ device: UUID, _ state: ReachabilityState, _ offset: TimeInterval) -> StatusEventSnapshot {
        StatusEventSnapshot(id: UUID(), deviceID: device, timestamp: base.addingTimeInterval(offset), state: state)
    }

    private func snapshot(_ id: UUID, _ name: String, isGateway: Bool = false) -> DeviceSnapshot {
        DeviceSnapshot(id: id, name: name, host: name, firstSeen: base, isGateway: isGateway)
    }

    @Test func newJoinedLeftReturned() {
        let cam = UUID()
        let devices = [cam: snapshot(cam, "Camera")]
        let entries = NetworkTimelineBuilder.entries(
            events: [event(cam, .online, 0), event(cam, .offline, 600), event(cam, .online, 1200)],
            devices: devices, gatewayID: nil, outageWindowSeconds: 90, outageFraction: 0.6, now: base.addingTimeInterval(2000)
        )
        #expect(entries.map(\.kind) == [.returned, .left, .newDevice])
        #expect(entries.allSatisfy { $0.title == "Camera" })
    }

    @Test func recoveringFromUnstableIsNotAReturn() {
        let speaker = UUID()
        let devices = [speaker: snapshot(speaker, "Speaker")]
        let events = [
            event(speaker, .online, 0), event(speaker, .degraded, 600), event(speaker, .online, 700),
            event(speaker, .degraded, 800), event(speaker, .offline, 900), event(speaker, .online, 1000),
        ]
        let entries = NetworkTimelineBuilder.entries(events: events, devices: devices, gatewayID: nil, outageWindowSeconds: 90, outageFraction: 0.6, now: base.addingTimeInterval(2000))
        #expect(entries.map(\.kind) == [.returned, .left, .newDevice])
    }

    @Test func gatewayDropCollapsesIntoOutage() {
        let gateway = UUID(), a = UUID(), b = UUID()
        let devices = [gateway: snapshot(gateway, "Router", isGateway: true), a: snapshot(a, "A"), b: snapshot(b, "B")]
        let events = [
            event(gateway, .online, 0), event(a, .online, 1), event(b, .online, 2),
            event(gateway, .offline, 300), event(a, .offline, 310), event(b, .offline, 320),
            event(gateway, .online, 900), event(a, .online, 905), event(b, .online, 910),
        ]
        let entries = NetworkTimelineBuilder.entries(events: events, devices: devices, gatewayID: gateway, outageWindowSeconds: 90, outageFraction: 0.6, now: base.addingTimeInterval(2000))
        let kinds = entries.map(\.kind)
        #expect(kinds.contains(.outageStarted))
        #expect(kinds.contains(.outageEnded))
        #expect(kinds.contains(.left) == false)
        #expect(kinds.filter { $0 == .newDevice }.count == 3)
        #expect(kinds.filter { $0 == .returned }.count == 2)
    }

    @Test func massDropWithoutGatewayAlsoCollapses() {
        let ids = (0..<5).map { _ in UUID() }
        var devices: [UUID: DeviceSnapshot] = [:]
        var events: [StatusEventSnapshot] = []
        for (index, id) in ids.enumerated() {
            devices[id] = snapshot(id, "D\(index)")
            events.append(event(id, .online, Double(index)))
        }
        for (index, id) in ids.prefix(4).enumerated() {
            events.append(event(id, .offline, 500 + Double(index * 10)))
        }
        let entries = NetworkTimelineBuilder.entries(events: events, devices: devices, gatewayID: nil, outageWindowSeconds: 90, outageFraction: 0.6, now: base.addingTimeInterval(2000))
        #expect(entries.filter { $0.kind == .outageStarted }.count == 1)
        #expect(entries.contains { $0.kind == .left } == false)
    }

    @Test func outageClosesWhenMostMembersReturnAndOthersKeepTheirRows() {
        let ids = (0..<6).map { _ in UUID() }
        var devices: [UUID: DeviceSnapshot] = [:]
        for (index, id) in ids.enumerated() {
            devices[id] = snapshot(id, "D\(index)")
        }
        var events = ids.enumerated().map { index, id in event(id, .online, Double(index)) }
        for (index, id) in ids.prefix(4).enumerated() {
            events.append(event(id, .offline, 1000 + Double(index)))
        }
        // An unrelated device comes back while the outage is open; it keeps its own row.
        events.append(event(ids[5], .offline, 1100))
        events.append(event(ids[5], .online, 1200))
        // Two of the four members return: that is half, so the outage ends.
        events.append(event(ids[0], .online, 2000))
        events.append(event(ids[1], .online, 2010))
        // A later departure of one device is an ordinary row again.
        events.append(event(ids[2], .offline, 5000))

        let entries = NetworkTimelineBuilder.entries(events: events, devices: devices, gatewayID: nil, outageWindowSeconds: 90, outageFraction: 0.6, now: base.addingTimeInterval(6000))
        let kinds = entries.map(\.kind)
        #expect(kinds.filter { $0 == .outageStarted }.count == 1)
        #expect(kinds.filter { $0 == .outageEnded }.count == 1)
        #expect(entries.first?.kind == .left)
        #expect(entries.first?.deviceID == ids[2])
    }

    @Test func twoPhonesLeavingIsNotAnOutage() {
        let ids = (0..<8).map { _ in UUID() }
        var devices: [UUID: DeviceSnapshot] = [:]
        for (index, id) in ids.enumerated() {
            devices[id] = snapshot(id, "D\(index)")
        }
        let events = [event(ids[0], .offline, 3000), event(ids[1], .offline, 3030)]
        let entries = NetworkTimelineBuilder.entries(events: events, devices: devices, gatewayID: nil, outageWindowSeconds: 90, outageFraction: 0.6, now: base.addingTimeInterval(4000))
        #expect(entries.map(\.kind) == [.left, .left])
    }

    @Test func returningKnownDeviceIsNotNew() {
        let phone = UUID()
        let devices = [phone: DeviceSnapshot(id: phone, name: "Phone", host: "10.0.0.8", firstSeen: base.addingTimeInterval(-86_400 * 30))]
        let entries = NetworkTimelineBuilder.entries(events: [event(phone, .online, 0)], devices: devices, gatewayID: nil, outageWindowSeconds: 90, outageFraction: 0.6, now: base.addingTimeInterval(100))
        #expect(entries.map(\.kind) == [.returned])
    }

    @Test func sectionsByDayNewestFirst() {
        let id = UUID()
        let entries = [
            TimelineEntry(id: "1", date: base, kind: .returned, deviceID: id, title: "A", subtitle: nil),
            TimelineEntry(id: "2", date: base.addingTimeInterval(-86_400 * 2), kind: .left, deviceID: id, title: "A", subtitle: nil),
            TimelineEntry(id: "3", date: base.addingTimeInterval(60), kind: .left, deviceID: id, title: "A", subtitle: nil),
        ]
        let sections = NetworkTimelineBuilder.sectionedByDay(entries, calendar: Calendar(identifier: .gregorian))
        #expect(sections.count == 2)
        #expect(sections[0].entries.map(\.id) == ["3", "1"])
        #expect(sections[1].entries.map(\.id) == ["2"])
    }
}

@Suite("Topology layout")
struct TopologyLayoutTests {
    @Test func gatewayCenteredAndNodesInsideBounds() {
        let base = Date()
        let gateway = DeviceSnapshot(id: UUID(), name: "Router", host: "10.0.0.1", firstSeen: base, isGateway: true)
        let others = (0..<25).map { index in
            DeviceSnapshot(id: UUID(), name: "D\(index)", host: "10.0.0.\(index + 2)", state: index % 3 == 0 ? .offline : .online, firstSeen: base)
        }
        let size = CGSize(width: 360, height: 300)
        let nodes = TopologyLayout.nodes(devices: [gateway] + others, gatewayID: gateway.id, size: size, division: 160...200)
        #expect(nodes.count == 26)
        let center = nodes.first { $0.isGateway }
        #expect(center?.position == CGPoint(x: 180, y: 150))
        for node in nodes where !node.isGateway {
            #expect(node.position.x >= node.radius && node.position.x <= size.width - node.radius)
            #expect(node.position.y >= node.radius && node.position.y <= size.height - node.radius)
            #expect(abs(node.position.x - 180) >= 20 + node.radius - 0.001)
        }
        let edges = TopologyLayout.edges(nodes)
        #expect(edges.count == 25)
        #expect(TopologyLayout.nodes(devices: [], gatewayID: nil, size: size, division: nil).isEmpty)
    }

    /// A map in a leading column meets the fold near its trailing edge, not at its centre.
    @Test func nodesAvoidAnOffCentreFold() {
        let base = Date(timeIntervalSince1970: 0)
        let devices = (0..<12).map { index in DeviceSnapshot(id: UUID(), name: "D\(index)", host: "10.0.0.\(index + 2)", firstSeen: base) }
        let size = CGSize(width: 320, height: 320)
        let fold: ClosedRange<CGFloat> = 250...262
        let unfolded = TopologyLayout.nodes(devices: devices, gatewayID: nil, size: size, division: nil)
        #expect(unfolded.contains { $0.position.x > fold.lowerBound - $0.radius && $0.position.x < fold.upperBound + $0.radius })

        let nodes = TopologyLayout.nodes(devices: devices, gatewayID: nil, size: size, division: fold)
        #expect(nodes.count == 12)
        for node in nodes {
            #expect(node.position.x <= fold.lowerBound - node.radius + 0.001 || node.position.x >= fold.upperBound + node.radius - 0.001)
            #expect(node.position.x >= node.radius && node.position.x <= size.width - node.radius)
        }
    }

    @Test func layoutIsDeterministic() {
        let base = Date(timeIntervalSince1970: 0)
        let ids = (0..<6).map { index in UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")! }
        let devices = ids.enumerated().map { index, id in DeviceSnapshot(id: id, name: "N\(index)", host: "h\(index)", firstSeen: base) }
        let a = TopologyLayout.nodes(devices: devices, gatewayID: nil, size: CGSize(width: 200, height: 200), division: nil)
        let b = TopologyLayout.nodes(devices: devices, gatewayID: nil, size: CGSize(width: 200, height: 200), division: nil)
        #expect(a == b)
    }

    @Test func sectorsFillTheCircleLessTheGaps() {
        let sectors = TopologyLayout.sectors(counts: [.network: 1, .computers: 2, .media: 3, .things: 6, .phones: 0])
        #expect(sectors.count == 4)
        #expect(sectors[.phones] == nil)
        let total = sectors.values.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        #expect(abs(total - (2 * Double.pi - 4 * 8 * Double.pi / 180)) < 0.000001)
        #expect(abs((sectors[.network]?.lowerBound ?? 0) + Double.pi / 2) < 0.000001)
        #expect(TopologyLayout.sectors(counts: [:]).isEmpty)
    }

    @Test func anglesStayInsideTheirFamilysSector() throws {
        let base = Date(timeIntervalSince1970: 0)
        let gateway = DeviceSnapshot(id: UUID(), name: "Router", host: "10.0.0.1", kind: .router, state: .online, firstSeen: base, isGateway: true)
        let kinds: [DeviceKind] = [.computer, .tablet, .phone, .watch, .phone, .tv, .speaker, .nas, .printer, .iot]
        // Offline devices all sit on the outer ring, so no neighbour is nudged and no node is clamped.
        let others = kinds.enumerated().map { index, kind in
            DeviceSnapshot(id: UUID(), name: "D\(index)", host: "10.0.0.\(index + 2)", kind: kind, state: .offline, firstSeen: base)
        }
        let size = CGSize(width: 320, height: 320)
        let nodes = TopologyLayout.nodes(devices: [gateway] + others, gatewayID: gateway.id, size: size, division: nil)
        var counts: [KindFamily: Int] = [:]
        for device in others {
            counts[KindFamily(device.kind), default: 0] += 1
        }
        let sectors = TopologyLayout.sectors(counts: counts)
        #expect(sectors[.network] == nil)
        for device in others {
            let node = try #require(nodes.first { $0.id == device.id })
            let sector = try #require(sectors[KindFamily(device.kind)])
            var angle = atan2(Double(node.position.y - 160), Double(node.position.x - 160))
            while angle < sector.lowerBound {
                angle += 2 * .pi
            }
            #expect(sector.contains(angle))
        }
    }

    @Test func fasterDevicesSitCloserAndOfflineOnTheOuterRing() throws {
        let base = Date(timeIntervalSince1970: 0)
        let latencies: [Double?] = [100, 1, 10, nil]
        let devices = latencies.enumerated().map { index, latency in
            DeviceSnapshot(id: UUID(), name: "D\(index)", host: "10.0.0.\(index + 2)", kind: .nas, state: latency == nil ? .offline : .online, latencyMilliseconds: latency, firstSeen: base)
        }
        let size = CGSize(width: 320, height: 320)
        let center = CGPoint(x: 160, y: 160)
        let nodes = TopologyLayout.nodes(devices: devices, gatewayID: nil, size: size, division: nil)
        func distance(_ index: Int) throws -> Double {
            let node = try #require(nodes.first { $0.id == devices[index].id })
            return Self.distance(node.position, from: center)
        }
        let fastest = try distance(1)
        let middle = try distance(2)
        let slowest = try distance(0)
        #expect(fastest < middle)
        #expect(middle < slowest)
        let outer = try #require(nodes.first { $0.id == devices[3].id })
        #expect(abs(Self.distance(outer.position, from: center) - Double(160 - outer.radius - 8)) < 0.001)
    }

    @Test func edgesCurveThroughTheSectorMidAngle() throws {
        let base = Date(timeIntervalSince1970: 0)
        let gateway = DeviceSnapshot(id: UUID(), name: "Router", host: "10.0.0.1", kind: .router, state: .online, firstSeen: base, isGateway: true)
        let printer = DeviceSnapshot(id: UUID(), name: "Printer", host: "10.0.0.2", kind: .printer, state: .online, latencyMilliseconds: 4, firstSeen: base)
        let size = CGSize(width: 320, height: 320)
        let nodes = TopologyLayout.nodes(devices: [gateway, printer], gatewayID: gateway.id, size: size, division: nil)
        let edge = try #require(TopologyLayout.edges(nodes).first)
        let center = CGPoint(x: 160, y: 160)
        #expect(edge.from == center)
        let reach = Self.distance(edge.to, from: center)
        #expect(abs(Self.distance(edge.control, from: center) - 0.35 * reach) < 0.001)
        let sector = try #require(TopologyLayout.sectors(counts: [.things: 1])[.things])
        let mid = (sector.lowerBound + sector.upperBound) / 2
        #expect(abs(Double(edge.control.x - center.x) - 0.35 * reach * cos(mid)) < 0.001)
        #expect(abs(Double(edge.control.y - center.y) - 0.35 * reach * sin(mid)) < 0.001)
    }

    @Test func ringsMarkTwoTenAndFiftyMilliseconds() {
        #expect(TopologyLayout.ringLatencies == [2, 10, 50])
        let size = CGSize(width: 320, height: 320)
        let radii = TopologyLayout.ringLatencies.map { TopologyLayout.ringRadius(latency: $0, size: size) }
        #expect(radii == radii.sorted())
        #expect(KindFamily(.tablet) == .computers)
        #expect(KindFamily(.unknown) == .things)
        #expect(KindFamily.allCases.map { KindFamily($0.representative) } == KindFamily.allCases)
    }

    private static func distance(_ point: CGPoint, from center: CGPoint) -> Double {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}

@Suite("Formatters")
struct FormattersTests {
    @Test func latencyStrings() {
        #expect(Formatters.latency(nil) == "—")
        #expect(Formatters.latency(3.14) == "3.1 ms")
        #expect(Formatters.latency(42.6) == "43 ms")
        #expect(Formatters.latency(1500) == "1.5 s")
        #expect(Formatters.percent(0.456) == "46%")
        #expect(Formatters.percent(2) == "100%")
    }

    @Test func percentShowsHundredOnlyWhenExact() {
        #expect(Formatters.percent(0.996) == "99.6%")
        #expect(Formatters.percent(0.9999) == "99.9%")
        #expect(Formatters.percent(0.99) == "99.0%")
        #expect(Formatters.percent(0.98) == "98%")
        #expect(Formatters.percent(1) == "100%")
    }

    @Test func relativeStrings() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(Formatters.relative(nil, now: now) == "Never")
        #expect(Formatters.relative(now.addingTimeInterval(-10), now: now) == "Just now")
        #expect(Formatters.relative(now.addingTimeInterval(-300), now: now) == "5 min ago")
        #expect(Formatters.relative(now.addingTimeInterval(-7200), now: now) == "2 hours ago")
        let lastYear = now.addingTimeInterval(-86_400 * 400)
        #expect(Formatters.relative(lastYear, now: now) == lastYear.formatted(date: .abbreviated, time: .omitted))
        #expect(Formatters.duration(45) == "45 s")
        #expect(Formatters.duration(600) == "10 min")
        #expect(Formatters.count(1, singular: "device", plural: "devices") == "1 device")
    }
}
