import SwiftUI

/// Map of the /24 the phone is on: one still tile per address in 32 columns by 8 rows on every width,
/// drawn by a single Metal pass whenever the devices change. The short grid leaves room for the feed
/// below it on iPhone. Tap a lit tile to open its device; VoiceOver gets one action per device instead.
struct SubnetHeatmapView: View {
    let devices: [DeviceSnapshot]
    let subnet: IPv4Subnet?
    let onSelect: (UUID) -> Void

    init(devices: [DeviceSnapshot], subnet: IPv4Subnet?, onSelect: @escaping (UUID) -> Void) {
        self.devices = devices
        self.subnet = subnet
        self.onSelect = onSelect
    }

    private let columns = 32
    private let rows = 8

    /// The /24 that is drawn: the phone's own, or the one holding most known devices.
    private var mapBase: UInt32 {
        if let subnet { return subnet.network.rawValue & 0xFFFF_FF00 }
        let prefixes = devices.compactMap { IPv4Host($0.host).map { $0.rawValue & 0xFFFF_FF00 } }
        let counts = Dictionary(prefixes.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value < $1.value }?.key ?? 0
    }

    private func occupancy(base: UInt32) -> [Int: DeviceSnapshot] {
        var byOffset: [Int: DeviceSnapshot] = [:]
        for device in devices {
            if let host = IPv4Host(device.host), host.rawValue & 0xFFFF_FF00 == base {
                byOffset[Int(host.rawValue - base)] = device
            }
        }
        return byOffset
    }

    var body: some View {
        let base = mapBase
        let occupied = occupancy(base: base)
        let heats: [Float] = (0..<256).map { offset in
            guard let device = occupied[offset] else { return 0 }
            switch device.state {
            case .online: return 1
            case .degraded: return 0.75
            case .offline: return 0.6
            case .unknown: return 0.3
            }
        }
        // Free addresses keep the shader's 7 % floor of the no-data colour.
        let tints: [Color] = (0..<256).map { offset in
            occupied[offset].map { Self.tint(for: $0.state) } ?? DSColor.noData
        }

        VStack(alignment: .leading, spacing: DSLayout.space12) {
            DSTitleRow("Address map", qualifier: "\(IPv4Host(rawValue: base).description)/24")
            Rectangle()
                .fill(ShaderLibrary.dm_addressMap(
                    .boundingRect,
                    .float(Float(columns)),
                    .float(Float(rows)),
                    .floatArray(heats),
                    .colorArray(tints)
                ))
                .aspectRatio(CGFloat(columns) / CGFloat(rows), contentMode: .fit)
                .contentShape(Rectangle())
                .overlay {
                    GeometryReader { proxy in
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                if let id = device(at: location, in: proxy.size, occupied: occupied) {
                                    onSelect(id)
                                }
                            }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Address map")
                .accessibilityValue("\(occupied.count) of 254 addresses in use")
                .accessibilityActions {
                    ForEach(occupied.values.sorted { $0.host.localizedStandardCompare($1.host) == .orderedAscending }) { device in
                        Button("Open \(device.displayName), \(device.state.title)") {
                            onSelect(device.id)
                        }
                    }
                }
            legend(inUse: occupied.count)
        }
        .dsCard()
    }

    /// A tile's colour: the state fills, and the neutral mark while a device is being checked.
    private static func tint(for state: ReachabilityState) -> Color {
        switch state {
        case .online: return DSColor.onlineFill
        case .degraded: return DSColor.degradedFill
        case .offline: return DSColor.offlineFill
        case .unknown: return DSColor.neutralMark
        }
    }

    /// The tile colours with their words, then "14 of 254 in use". It stacks when one line does not fit.
    private func legend(inUse: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DSLayout.space12) {
                legendKeys
                Text("· \(inUse) of 254 in use")
            }
            .lineLimit(1)
            VStack(alignment: .leading, spacing: DSLayout.space4) {
                legendKeys
                Text("\(inUse) of 254 in use")
            }
        }
        .font(DSTypography.axis)
        .foregroundStyle(DSColor.textSecondary)
        .accessibilityElement(children: .combine)
    }

    private var legendKeys: some View {
        HStack(spacing: DSLayout.space12) {
            ForEach([ReachabilityState.online, .degraded, .offline], id: \.self) { state in
                DSLegendSwatch(color: Self.tint(for: state), title: state.title)
            }
        }
    }

    /// The device whose tile is nearest the tap, within one and a half tiles or half a minimum tap
    /// target, whichever is larger, so the small iPhone tiles stay easy to hit.
    private func device(at location: CGPoint, in size: CGSize, occupied: [Int: DeviceSnapshot]) -> UUID? {
        let cell = CGSize(width: size.width / CGFloat(columns), height: size.height / CGFloat(rows))
        guard cell.width > 0, cell.height > 0 else { return nil }
        let reach = max(1.5 * max(cell.width, cell.height), DSLayout.minTapTarget / 2)
        var best: (distance: CGFloat, id: UUID)?
        for (offset, device) in occupied {
            let center = CGPoint(x: (CGFloat(offset % columns) + 0.5) * cell.width, y: (CGFloat(offset / columns) + 0.5) * cell.height)
            let distance = hypot(center.x - location.x, center.y - location.y)
            if distance <= reach, distance < (best?.distance ?? .infinity) {
                best = (distance, device.id)
            }
        }
        return best?.id
    }
}

extension View {
    /// Dark-mode halo for the scan radar's moving waves and blips. Off in light mode, with Increase Contrast,
    /// Reduce Transparency and "Reduce visual effects".
    func dsGlow(radius: CGFloat = 5, intensity: Double = 0.6) -> some View {
        modifier(DSGlowModifier(radius: radius, intensity: intensity))
    }
}

/// Runs `dm_glow` over the content; `isEnabled: false` draws the content unchanged.
private struct DSGlowModifier: ViewModifier {
    let radius: CGFloat
    let intensity: Double
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dsReduceEffects) private var reduceEffects

    init(radius: CGFloat, intensity: Double) {
        self.radius = radius
        self.intensity = intensity
    }

    func body(content: Content) -> some View {
        let isEnabled = colorScheme == .dark && contrast == .standard && !reduceTransparency && !reduceEffects
        content.layerEffect(
            ShaderLibrary.dm_glow(.float(radius), .float(intensity)),
            maxSampleOffset: CGSize(width: radius, height: radius),
            isEnabled: isEnabled
        )
    }
}
