import SwiftUI

/// Gateway-centred network map that holds still. Devices sit in kind sectors at their latency, so closer
/// means faster; dashed rings mark 2, 10 and 50 ms (the caption under the map names them). Links are hairlines
/// and carry colour only for exceptions; nodes are tappable neutral thumbnails (the gateway a tile, the rest
/// circles) with a state badge only when something is wrong.
struct TopologyView: View {
    let devices: [DeviceSnapshot]
    let gatewayID: UUID?
    let showsNames: Bool
    let onSelect: (UUID) -> Void

    @Environment(\.dsMotion) private var motion
    @Environment(\.displayScale) private var displayScale
    @State private var division: ClosedRange<CGFloat>?

    init(devices: [DeviceSnapshot], gatewayID: UUID?, showsNames: Bool, onSelect: @escaping (UUID) -> Void) {
        self.devices = devices
        self.gatewayID = gatewayID
        self.showsNames = showsNames
        self.onSelect = onSelect
    }

    private struct Connection: Identifiable {
        let id: UUID
        let edge: TopologyEdge
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let nodes = TopologyLayout.nodes(devices: devices, gatewayID: gatewayID, size: size, division: division)
            let connections = zip(nodes.filter { !$0.isGateway }, TopologyLayout.edges(nodes)).map { Connection(id: $0.0.id, edge: $0.1) }
            let hairline = 1 / displayScale
            ZStack {
                Canvas { canvas, _ in
                    for latency in TopologyLayout.ringLatencies {
                        let radius = TopologyLayout.ringRadius(latency: latency, size: size)
                        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                        canvas.stroke(Path(ellipseIn: rect), with: .color(DSColor.grid), style: StrokeStyle(lineWidth: hairline, dash: [2, 2]))
                    }
                }
                ForEach(connections) { connection in
                    let look = linkStyle(for: connection.edge.state, hairline: hairline)
                    MapLink(from: connection.edge.from, to: connection.edge.to, control: connection.edge.control)
                        .stroke(look.color, style: StrokeStyle(lineWidth: look.width, lineCap: .round, dash: look.dash))
                }
                let labelled = showsNames ? Self.labelledNodes(nodes) : []
                ForEach(nodes) { node in
                    TopologyNodeView(node: node, name: devices.first { $0.id == node.id }?.displayName ?? "Device", showsName: labelled.contains(node.id)) {
                        onSelect(node.id)
                    }
                    .position(node.position)
                }
            }
            .animation(DSMotion.animation(DSMotion.springSoft, reduceMotion: motion.reduceMotion), value: nodes)
        }
        .duoVerticalDivision($division)
    }

    /// Nodes whose name fits under them without touching another name or another node, gateway first. The
    /// rest stay unlabelled on screen; VoiceOver still reads every name.
    private static func labelledNodes(_ nodes: [TopologyNode]) -> Set<UUID> {
        let ordered = nodes.filter(\.isGateway) + nodes.filter { !$0.isGateway }
        var placed: [CGRect] = []
        var labelled: Set<UUID> = []
        for node in ordered {
            let frameHeight = max(node.radius * 2 + 10, DSLayout.minTapTarget)
            let label = CGRect(x: node.position.x - 40, y: node.position.y + frameHeight / 2, width: 80, height: 14)
            let hitsNode = nodes.contains { other in
                other.id != node.id && label.intersects(CGRect(
                    x: other.position.x - other.radius, y: other.position.y - other.radius,
                    width: other.radius * 2, height: other.radius * 2
                ))
            }
            if !hitsNode, !placed.contains(where: { $0.intersects(label) }) {
                placed.append(label)
                labelled.insert(node.id)
            }
        }
        return labelled
    }

    /// Colour appears on a link only where it means something: unstable and offline links. Answering devices
    /// hang on a hairline; dashed means not answering.
    private func linkStyle(for state: ReachabilityState, hairline: CGFloat) -> (color: Color, width: CGFloat, dash: [CGFloat]) {
        switch state {
        case .online: return (DSColor.hairline, hairline, [])
        case .degraded: return (DSColor.degradedFill, 1.5, [])
        case .offline: return (DSColor.offlineFill.opacity(0.5), 1, [3, 4])
        case .unknown: return (DSColor.hairline, hairline, [3, 4])
        }
    }
}

/// A quadratic link whose end points and control point animate with the nodes.
nonisolated private struct MapLink: Shape {
    var from: CGPoint
    var to: CGPoint
    var control: CGPoint

    var animatableData: AnimatablePair<AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>, CGPoint.AnimatableData> {
        get { AnimatablePair(AnimatablePair(from.animatableData, to.animatableData), control.animatableData) }
        set {
            from.animatableData = newValue.first.first
            to.animatableData = newValue.first.second
            control.animatableData = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addQuadCurve(to: to, control: control)
        return path
    }
}

private struct TopologyNodeView: View {
    let node: TopologyNode
    let name: String
    let showsName: Bool
    let onTap: () -> Void

    init(node: TopologyNode, name: String, showsName: Bool, onTap: @escaping () -> Void) {
        self.node = node
        self.name = name
        self.showsName = showsName
        self.onTap = onTap
    }

    /// The kind's thumbnail: flat below 42 pt, the render from there; a badge only for offline and unstable.
    var body: some View {
        let diameter = node.radius * 2
        Button(action: onTap) {
            DeviceThumbnail(kind: node.kind, state: node.state, size: diameter, style: node.isGateway ? .tile : .circle)
                .frame(width: max(diameter + 10, DSLayout.minTapTarget), height: max(diameter + 10, DSLayout.minTapTarget))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showsName {
                Text(name)
                    .font(DSTypography.axis)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 80)
                    .alignmentGuide(.bottom) { dimensions in dimensions[.top] }
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(name)
        .accessibilityValue(node.state.title)
    }
}
