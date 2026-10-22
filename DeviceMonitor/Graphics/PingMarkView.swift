import SwiftUI
import UIKit   // the placeholder style's UIColor greys; member import visibility

/// The DeviceMonitor mark: a stem joined to a bowl, the D, with a dot in its counter, a device answering a
/// ping. Bowl, stem and dot stack as the icon's layers do, at the glyph's 464 : 576 aspect, so
/// `.frame(height: 72)` is 58 pt wide. A live mark's dot breathes; a rippling mark sends arcs out of the
/// bowl to the right. It is decorative, so VoiceOver skips it.
struct PingMark: View {
    enum Style: Sendable, Hashable {
        /// On the brand gradient, in the light or the dark icon's colours.
        case onBrand(isDark: Bool)
        /// Greys, for an empty state.
        case placeholder
    }

    let style: PingMark.Style
    let isLive: Bool
    let isRippling: Bool

    @State private var height: CGFloat = 0

    /// The dark icon's stem (cobalt-100) and bowl (cobalt-400).
    private static let darkStem = Color(red: 225.0 / 255, green: 236.0 / 255, blue: 254.0 / 255)
    private static let darkBowl = Color(red: 120.0 / 255, green: 162.0 / 255, blue: 252.0 / 255)

    init(style: PingMark.Style, isLive: Bool = false, isRippling: Bool = false) {
        self.style = style
        self.isLive = isLive
        self.isRippling = isRippling
    }

    private var palette: (stem: Color, bowl: Color, dot: Color) {
        switch style {
        case .onBrand(let isDark):
            if isDark {
                return (Self.darkStem, Self.darkBowl, DSColor.brandSignal)
            }
            return (Color.white, DSColor.brandBowl, DSColor.brandSignal)
        case .placeholder:
            return (Color(uiColor: .tertiaryLabel), Color(uiColor: .quaternaryLabel), Color(uiColor: .quaternaryLabel))
        }
    }

    private var rippleColor: Color {
        switch style {
        case .onBrand: return DSColor.brandBowl
        case .placeholder: return palette.bowl
        }
    }

    var body: some View {
        let colors = palette
        // Dots of 12 pt and more breathe in scale around their own centre, smaller ones in opacity.
        let dotDiameter = height * 124 / 576
        ZStack {
            PingMarkPart(kind: .bowl)
                .fill(colors.bowl)
            PingMarkPart(kind: .stem)
                .fill(colors.stem)
            PingMarkPart(kind: .dot)
                .fill(colors.dot)
                .dsBreathing(isActive: isLive, mode: dotDiameter >= 12 ? .scale(anchor: UnitPoint(x: 236.0 / 464.0, y: 0.5)) : .opacity)
        }
        .aspectRatio(464.0 / 576.0, contentMode: .fit)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            height = newHeight
        }
        .overlay {
            if isRippling {
                // A square of 1.8 × the mark's height, centred on the bowl's centre (glyph point 176, 288),
                // holds the whole sweep.
                GeometryReader { proxy in
                    PingRipple(color: rippleColor)
                        .frame(width: 1.8 * proxy.size.height, height: 1.8 * proxy.size.height)
                        .position(x: proxy.size.width * 176 / 464, y: proxy.size.height / 2)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The mark on the brand gradient, in the app icon's proportions, for the Settings header. It follows the
/// colour scheme like the Home Screen icon.
struct PingMarkTile: View {
    let size: CGFloat
    let isLive: Bool

    @Environment(\.colorScheme) private var colorScheme

    init(size: CGFloat, isLive: Bool = false) {
        self.size = size
        self.isLive = isLive
    }

    var body: some View {
        PingMark(style: .onBrand(isDark: colorScheme == .dark), isLive: isLive)
            .frame(height: size * 0.56)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                    .fill(DSColor.brandGradient(colorScheme))
            }
            .accessibilityHidden(true)
    }
}

/// One part of the DeviceMonitor mark, drawn from the icon's layer geometry so the app and the icon
/// never drift apart. The glyph box is 464 × 576 units; the part fits `rect` with that aspect, centred.
nonisolated struct PingMarkPart: Shape {
    nonisolated enum Kind: Sendable, Hashable { case stem, bowl, dot }
    let kind: Kind

    init(kind: Kind) {
        self.kind = kind
    }

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width / 464, rect.height / 576)
        let origin = CGPoint(x: rect.midX - 232 * unit, y: rect.midY - 288 * unit)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * unit, y: origin.y + y * unit)
        }
        switch kind {
        case .stem:
            return Capsule().path(in: CGRect(x: origin.x, y: origin.y, width: 132 * unit, height: 576 * unit))
        case .dot:
            return Circle().path(in: CGRect(x: origin.x + 174 * unit, y: origin.y + 226 * unit, width: 124 * unit, height: 124 * unit))
        case .bowl:
            // SwiftUI's y axis points down, so clockwise: false runs top → right → bottom on screen.
            var path = Path()
            let centre = point(176, 288)
            path.move(to: point(66, 0))
            path.addLine(to: point(176, 0))
            path.addArc(center: centre, radius: 288 * unit, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: point(66, 576))
            path.addLine(to: point(66, 444))
            path.addLine(to: point(176, 444))
            path.addArc(center: centre, radius: 156 * unit, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
            path.addLine(to: point(66, 132))
            path.closeSubpath()
            return path
        }
    }
}

extension PingMotion {
    /// How far each wave in flight has travelled at `time` seconds, eased out: 0 as it leaves, 1 as it is
    /// gone. One wave leaves every `ripplePeriod / rippleCount` seconds.
    nonisolated static func waveProgress(at time: TimeInterval) -> [Double] {
        (0..<rippleCount).map { index in
            let phase = (time / ripplePeriod + Double(index) / Double(rippleCount)).truncatingRemainder(dividingBy: 1)
            return 1 - (1 - phase) * (1 - phase)
        }
    }
}

/// The arc ripple: `PingMotion.rippleCount` open arcs from −60° to +60° around the centre of a square that
/// is 1.8 × the mark's height, growing from 328 to 488 glyph units while their stroke tapers from 44 to 12
/// units and they fade out. Under Reduce Motion, "Reduce visual effects" and screenshot runs it draws three
/// still arcs instead, with no timeline at all, so captures never catch a random frame.
private struct PingRipple: View {
    let color: Color

    @Environment(\.dsMotion) private var motion

    /// The still ripple: three arcs that still say "signal".
    private static let stillArcs: [(radius: CGFloat, opacity: Double)] = [(340, 0.45), (400, 0.28), (460, 0.14)]

    init(color: Color) {
        self.color = color
    }

    var body: some View {
        if motion.reduceMotion || LaunchArguments.current.isScreenshots {
            Canvas { context, size in
                for arc in Self.stillArcs {
                    Self.drawArc(in: &context, size: size, radius: arc.radius, opacity: arc.opacity, color: color)
                }
            }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                Canvas { context, size in
                    for progress in PingMotion.waveProgress(at: timeline.date.timeIntervalSinceReferenceDate) {
                        let radius = 328 + 160 * CGFloat(progress)
                        Self.drawArc(in: &context, size: size, radius: radius, opacity: PingMotion.rippleStartOpacity * (1 - progress), color: color)
                    }
                }
            }
        }
    }

    /// An arc of `radius` glyph units; its stroke follows the radius from 44 units at 328 to 12 at 488.
    private static func drawArc(in context: inout GraphicsContext, size: CGSize, radius: CGFloat, opacity: Double, color: Color) {
        let unit = size.height / (1.8 * 576)
        let travelled = (radius - 328) / 160
        let lineWidth = 44 * (1 - (1 - CGFloat(PingMotion.strokeTaper)) * travelled)
        var arc = Path()
        arc.addArc(center: CGPoint(x: size.width / 2, y: size.height / 2), radius: radius * unit, startAngle: .degrees(-60), endAngle: .degrees(60), clockwise: false)
        context.stroke(arc, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: lineWidth * unit, lineCap: .round))
    }
}

#Preview("Ping mark") {
    VStack(spacing: 32) {
        PingMark(style: .onBrand(isDark: false), isLive: true, isRippling: true)
            .frame(height: 112)
            .frame(maxWidth: .infinity, minHeight: 220)
            .background {
                DSColor.brandGradient(.light)
            }
        HStack(spacing: 24) {
            PingMarkTile(size: 56, isLive: true)
            PingMark(style: .placeholder)
                .frame(height: 72)
        }
    }
    .padding()
}
