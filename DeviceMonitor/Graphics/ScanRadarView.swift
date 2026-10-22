import SwiftUI

/// One host on the scan radar: `angle` in radians clockwise from 3 o'clock (12 o'clock is −π/2), which the
/// radar squeezes out of the ring labels' wedge (`RadarGeometry.bearing`), and `distance` as a fraction of the
/// radar's radius (`ScanRadarView.distance(latency:)`).
nonisolated struct ScanBlip: Identifiable, Hashable, Sendable {
    let id: String
    let angle: Double
    let distance: Double
    let isNew: Bool

    init(id: String, angle: Double, distance: Double, isNew: Bool) {
        self.id = id
        self.angle = angle
        self.distance = distance
        self.isNew = isNew
    }
}

/// The scan radar: the gateway in the centre, dashed range rings at 2, 10 and 50 ms on the network map's
/// latency scale, labelled up the 12 o'clock spoke where no blip goes, and one blip per host found: a grey dot
/// when known, a hollow ring when new (shape, not colour). While scanning, ping waves in the tint leave the
/// gateway and light the blips they pass; in dark mode the waves and blips carry a soft glow, the rings and
/// labels never do. The status line under it owns every number. It fills its proposed square and is hidden
/// from VoiceOver, because the status line, the stages and the Found list say the same.
struct ScanRadarView: View {
    let blips: [ScanBlip]
    let isScanning: Bool

    @Environment(\.dsMotion) private var motion
    @Environment(\.displayScale) private var displayScale

    /// Blips sit between these fractions of the radius; the inner quarter keeps the gateway clear.
    private static let inner = 0.25
    private static let outer = 0.94

    init(blips: [ScanBlip], isScanning: Bool) {
        self.blips = blips
        self.isScanning = isScanning
    }

    /// Where a host answering in `latency` milliseconds sits, as a fraction of the radius: closer is faster.
    /// Hosts without a latency sit on the outer ring.
    static func distance(latency: Double?) -> Double {
        RadarGeometry.distance(latency: latency, inner: inner, outer: outer)
    }

    /// No waves under Reduce Motion, "Reduce visual effects" or in screenshot runs; the blips hold still.
    private var showsWaves: Bool {
        isScanning && !motion.reduceMotion && !LaunchArguments.current.isScreenshots
    }

    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                rangeRings(radius: radius, center: center)
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !showsWaves)) { timeline in
                    let waves = showsWaves ? PingMotion.waveProgress(at: timeline.date.timeIntervalSinceReferenceDate) : []
                    pings(waves: waves, radius: radius, center: center, size: proxy.size)
                }
                .dsGlow()
                gateway
                    .position(center)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(DSMotion.animation(DSMotion.springFast, reduceMotion: motion.reduceMotion), value: blips)
        .accessibilityHidden(true)
    }

    /// The outer edge and the 2, 10 and 50 ms rings, 1 px dashed. The labels sit up the spoke in
    /// `RadarGeometry.labelWedge`, the unit once on the outermost, as on the latency scale; that wedge is
    /// sized for them up to xxxLarge.
    @ViewBuilder
    private func rangeRings(radius: CGFloat, center: CGPoint) -> some View {
        let hairline = 1 / displayScale
        Canvas { context, _ in
            let fractions = [1.0] + TopologyLayout.ringLatencies.map { Self.distance(latency: $0) }
            for fraction in fractions {
                let ring = min(radius * CGFloat(fraction), radius - hairline / 2)
                context.stroke(Self.circle(center: center, radius: ring), with: .color(DSColor.grid), style: StrokeStyle(lineWidth: hairline, dash: [2, 2]))
            }
        }
        ForEach(TopologyLayout.ringLatencies, id: \.self) { latency in
            let ring = radius * CGFloat(Self.distance(latency: latency))
            let isOutermost = latency == TopologyLayout.ringLatencies.last
            Text(isOutermost ? "\(Int(latency)) ms" : "\(Int(latency))")
                .font(DSTypography.axis)
                .foregroundStyle(DSColor.textTertiary)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(.horizontal, 2)
                .background {
                    Capsule().fill(DSColor.background)
                }
                .position(
                    x: center.x + ring * CGFloat(cos(RadarGeometry.labelBearing)),
                    y: center.y + ring * CGFloat(sin(RadarGeometry.labelBearing))
                )
        }
    }

    /// The ping waves in flight (`waves` holds each one's eased progress) and the blips they light. Each wave
    /// is a tapering ring in the tint that fades as it travels.
    private func pings(waves: [Double], radius: CGFloat, center: CGPoint, size: CGSize) -> some View {
        ZStack {
            ForEach(Array(waves.enumerated()), id: \.offset) { _, progress in
                let ring = radius * CGFloat(Self.waveFront(progress))
                Circle()
                    .stroke(.tint, lineWidth: CGFloat(2 * (1 - (1 - PingMotion.strokeTaper) * progress)))
                    .frame(width: 2 * ring, height: 2 * ring)
                    .position(center)
                    .opacity(PingMotion.rippleStartOpacity * (1 - progress))
            }
            ForEach(blips) { blip in
                let bearing = RadarGeometry.bearing(blip.angle)
                let point = CGPoint(
                    x: center.x + CGFloat(cos(bearing) * blip.distance) * radius,
                    y: center.y + CGFloat(sin(bearing) * blip.distance) * radius
                )
                blipView(blip, lit: waves.isEmpty ? nil : Self.lit(blip, waves: waves))
                    .position(point)
                    .transition(pingIn(at: point, in: size))
            }
        }
    }

    /// The gateway: a 10 pt dot on a 2 pt card ring, and no text.
    private var gateway: some View {
        Circle()
            .fill(DSColor.textPrimary)
            .frame(width: 10, height: 10)
            .padding(2)
            .background {
                Circle().fill(DSColor.card)
            }
    }

    /// A known host is a 7 pt grey dot, a new one a 9 pt hollow ring. While a wave passes (`lit` 0…1) a blip
    /// grows by up to 3 pt and goes from half to full opacity.
    @ViewBuilder
    private func blipView(_ blip: ScanBlip, lit: Double?) -> some View {
        let growth = lit.map { 3 * CGFloat($0) } ?? 0
        let opacity = lit.map { 0.5 + 0.5 * $0 } ?? 1
        if blip.isNew {
            Circle()
                .strokeBorder(DSColor.textPrimary, lineWidth: 1.5)
                .frame(width: 9 + growth, height: 9 + growth)
                .opacity(opacity)
        } else {
            Circle()
                .fill(DSColor.neutralMark)
                .frame(width: 7 + growth, height: 7 + growth)
                .opacity(opacity)
        }
    }

    /// A newly found host pings in from 2.4 × its size. A positioned blip fills the radar, so the scale is
    /// anchored on the blip's own spot.
    private func pingIn(at point: CGPoint, in size: CGSize) -> AnyTransition {
        if motion.reduceMotion {
            return DSMotion.rowTransition(reduceMotion: true)
        }
        let anchor = UnitPoint(x: point.x / max(size.width, 1), y: point.y / max(size.height, 1))
        return AnyTransition.scale(scale: 2.4, anchor: anchor).combined(with: .opacity)
    }

    /// A wave's radius as a fraction of the radar's: from the inner ring out to the edge.
    private static func waveFront(_ progress: Double) -> Double {
        inner + (1 - inner) * progress
    }

    /// How brightly the nearest wave lights a blip: 1 on the wavefront, falling off with distance from it.
    private static func lit(_ blip: ScanBlip, waves: [Double]) -> Double {
        waves.map { exp(-abs(waveFront($0) - blip.distance) * 12) }.max() ?? 0
    }

    private static func circle(center: CGPoint, radius: CGFloat) -> Path {
        Circle().path(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
    }
}

#Preview("Scan radar") {
    ScanRadarView(
        blips: (0..<12).map { index in
            ScanBlip(id: "\(index)", angle: -Double.pi / 2 + Double(index) * 0.52, distance: 0.3 + Double(index % 5) * 0.14, isNew: index == 3)
        },
        isScanning: true
    )
    .frame(width: 240, height: 240)
    .padding()
    .background {
        DSColor.background
    }
}
