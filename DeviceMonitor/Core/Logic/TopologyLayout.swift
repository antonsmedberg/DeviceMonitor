import Foundation

nonisolated struct TopologyNode: Sendable, Hashable, Identifiable {
    let id: UUID
    let position: CGPoint
    let radius: CGFloat
    let state: ReachabilityState
    let kind: DeviceKind
    let isGateway: Bool

    init(id: UUID, position: CGPoint, radius: CGFloat, state: ReachabilityState, kind: DeviceKind, isGateway: Bool) {
        self.id = id
        self.position = position
        self.radius = radius
        self.state = state
        self.kind = kind
        self.isGateway = isGateway
    }
}

nonisolated struct TopologyEdge: Sendable, Hashable {
    let from: CGPoint
    let to: CGPoint
    /// Control point of the quadratic link: on the node's sector mid-angle, at 35 % of its distance.
    let control: CGPoint
    let state: ReachabilityState

    init(from: CGPoint, to: CGPoint, control: CGPoint, state: ReachabilityState) {
        self.from = from
        self.to = to
        self.control = control
        self.state = state
    }
}

/// The map's sectors, one per `DSColor.kind` palette.
nonisolated enum KindFamily: Int, Sendable, Hashable, CaseIterable {
    case network, computers, phones, media, things

    init(_ kind: DeviceKind) {
        switch kind {
        case .router, .hub: self = .network
        case .computer, .tablet: self = .computers
        case .phone, .watch: self = .phones
        case .tv, .speaker, .console: self = .media
        case .nas, .camera, .iot, .printer, .unknown: self = .things
        }
    }

    var title: String {
        switch self {
        case .network: return "Network"
        case .computers: return "Computers"
        case .phones: return "Phones & watches"
        case .media: return "Media"
        case .things: return "Things"
        }
    }

    /// A kind whose palette is the family's.
    var representative: DeviceKind {
        switch self {
        case .network: return .router
        case .computers: return .computer
        case .phones: return .phone
        case .media: return .tv
        case .things: return .nas
        }
    }
}

/// Deterministic, still radial layout: the gateway sits in the centre and every other device in its kind
/// family's sector, in name order. Its distance is its latency on the scan radar's log scale, so closer is
/// faster and jitter moves a node along its own spoke without reshuffling the map.
nonisolated enum TopologyLayout {
    /// Latencies of the labelled rings, in milliseconds; the scan radar draws the same rings.
    static let ringLatencies: [Double] = [2, 10, 50]

    private static let innerFraction = 0.30
    private static let outerFraction = 0.92
    private static let sectorGap = 8.0 * Double.pi / 180
    private static let minimumSector = 30.0 * Double.pi / 180

    /// Radians, clockwise from 12 o'clock (−π/2): each family with devices gets an arc in proportion to its
    /// count, at least 30°, with 8° between arcs, renormalised so the arcs fill 2π minus the gaps.
    static func sectors(counts: [KindFamily: Int]) -> [KindFamily: ClosedRange<Double>] {
        let present = KindFamily.allCases.filter { (counts[$0] ?? 0) > 0 }
        let total = present.reduce(0) { $0 + (counts[$1] ?? 0) }
        guard total > 0 else { return [:] }
        let usable = 2 * Double.pi - sectorGap * Double(present.count)
        let raw = present.map { max(minimumSector, usable * Double(counts[$0] ?? 0) / Double(total)) }
        let scale = usable / raw.reduce(0, +)
        var result: [KindFamily: ClosedRange<Double>] = [:]
        var cursor = -Double.pi / 2
        for (family, width) in zip(present, raw) {
            let scaled = width * scale
            result[family] = cursor...(cursor + scaled)
            cursor += scaled + sectorGap
        }
        return result
    }

    /// Distance from the centre of the ring for `latency` milliseconds on a map of `size`.
    static func ringRadius(latency: Double, size: CGSize) -> CGFloat {
        CGFloat(RadarGeometry.distance(latency: latency, inner: innerFraction, outer: outerFraction)) * maxRadius(size)
    }

    /// `division` is the span of x covered by a vertical fold, in the same coordinates as `size`.
    static func nodes(devices: [DeviceSnapshot], gatewayID: UUID?, size: CGSize, division: ClosedRange<CGFloat>?) -> [TopologyNode] {
        guard size.width > 0, size.height > 0, !devices.isEmpty else { return [] }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let scale = min(size.width, size.height) / 320
        let gatewayRadius = 26 * scale
        let nodeRadius = 15 * scale
        let outerRadius = Double(Self.maxRadius(size))

        var result: [TopologyNode] = []
        let gateway = devices.first { $0.id == gatewayID } ?? devices.first { $0.isGateway }
        if let gateway {
            result.append(TopologyNode(id: gateway.id, position: center, radius: gatewayRadius, state: gateway.state, kind: gateway.kind, isGateway: true))
        }

        let families = Dictionary(grouping: devices.filter { $0.id != gateway?.id }) { KindFamily($0.kind) }
        let ranges = sectors(counts: families.mapValues(\.count))
        for family in KindFamily.allCases {
            guard let sector = ranges[family], let members = families[family] else { continue }
            let sorted = members.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            var previous: CGPoint?
            for (index, device) in sorted.enumerated() {
                let angle = sector.lowerBound + (sector.upperBound - sector.lowerBound) * (Double(index) + 0.5) / Double(sorted.count)
                var distance = radiusFraction(for: device) * outerRadius
                var point = polar(center: center, angle: angle, distance: distance)
                // A neighbour closer than 2.2 node radii moves outward by one node diameter.
                if let previous, Self.distance(point, previous) < 2.2 * Double(nodeRadius) {
                    distance += 2 * Double(nodeRadius)
                    point = polar(center: center, angle: angle, distance: distance)
                }
                previous = point
                var x = Double(point.x)
                let y = Double(point.y)

                // Keep nodes off the iPhone Duo fold wherever it crosses the view: a node on it moves to
                // the nearer side that still fits inside the view.
                if let division {
                    let before = Double(division.lowerBound - nodeRadius)
                    let after = Double(division.upperBound + nodeRadius)
                    if x > before, x < after {
                        let sides = [before, after].filter { $0 >= Double(nodeRadius) && $0 <= Double(size.width - nodeRadius) }
                        if let nearest = sides.min(by: { abs($0 - x) < abs($1 - x) }) {
                            x = nearest
                        }
                    }
                }

                let clampedX = min(max(x, Double(nodeRadius)), Double(size.width - nodeRadius))
                let clampedY = min(max(y, Double(nodeRadius)), Double(size.height - nodeRadius))
                result.append(TopologyNode(
                    id: device.id,
                    position: CGPoint(x: clampedX, y: clampedY),
                    radius: nodeRadius,
                    state: device.state,
                    kind: device.kind,
                    isGateway: false
                ))
            }
        }
        return result
    }

    static func edges(_ nodes: [TopologyNode]) -> [TopologyEdge] {
        guard let gateway = nodes.first(where: { $0.isGateway }) else { return [] }
        let others = nodes.filter { !$0.isGateway }
        var counts: [KindFamily: Int] = [:]
        for node in others {
            counts[KindFamily(node.kind), default: 0] += 1
        }
        let ranges = sectors(counts: counts)
        return others.map { node in
            let reach = Self.distance(node.position, gateway.position)
            let midAngle = ranges[KindFamily(node.kind)].map { ($0.lowerBound + $0.upperBound) / 2 }
                ?? atan2(Double(node.position.y - gateway.position.y), Double(node.position.x - gateway.position.x))
            let control = polar(center: gateway.position, angle: midAngle, distance: 0.35 * reach)
            return TopologyEdge(from: gateway.position, to: node.position, control: control, state: node.state)
        }
    }

    /// Answering devices sit at their latency; offline and unknown ones on the outer edge.
    private static func radiusFraction(for device: DeviceSnapshot) -> Double {
        device.state.isUp ? RadarGeometry.distance(latency: device.latencyMilliseconds, inner: innerFraction, outer: outerFraction) : 1
    }

    /// Distance of radius fraction 1: the node stays 8 pt inside the shorter side.
    private static func maxRadius(_ size: CGSize) -> CGFloat {
        min(size.width, size.height) / 2 - 15 * min(size.width, size.height) / 320 - 8
    }

    private static func polar(center: CGPoint, angle: Double, distance: Double) -> CGPoint {
        CGPoint(x: Double(center.x) + distance * cos(angle), y: Double(center.y) + distance * sin(angle))
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
