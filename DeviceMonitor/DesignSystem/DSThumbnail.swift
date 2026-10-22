import SwiftUI

/// The corner badge of a thumbnail: a device's state, or an open service's risk.
nonisolated enum DSThumbnailBadge: Sendable, Hashable {
    case offline, unstable, risk(PortRisk)
}

/// A glyph on a tile or circle. From 42 pt it is the "product render": a lit tile gradient, a rim that
/// catches the top edge, a metal glyph gradient and, in dark mode, a 1 pt depth line. Below 42 pt the render
/// would be invisible, so it is a flat raised well with a grey glyph. Offline glyphs fade to 45 %; the badge
/// and the row's words carry the state, so the thumbnail is hidden from VoiceOver.
struct DSThumbnail: View {
    nonisolated enum Style: Sendable, Hashable {
        case tile, circle
    }

    private let systemImage: String
    private let size: CGFloat
    private let style: DSThumbnail.Style
    private let isDimmed: Bool
    private let badge: DSThumbnailBadge?

    @Environment(\.colorScheme) private var colorScheme

    init(
        systemImage: String,
        size: CGFloat = DSLayout.thumbnailRow,
        style: DSThumbnail.Style = .tile,
        isDimmed: Bool = false,
        badge: DSThumbnailBadge? = nil
    ) {
        self.systemImage = systemImage
        self.size = size
        self.style = style
        self.isDimmed = isDimmed
        self.badge = badge
    }

    private var isRender: Bool { size >= DSLayout.thumbnailService }

    var body: some View {
        surface
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    badgeView(badge)
                        .offset(x: 3, y: 3)
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var surface: some View {
        switch style {
        case .tile: layers(in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        case .circle: layers(in: Circle())
        }
    }

    private func layers<S: InsettableShape>(in shape: S) -> some View {
        ZStack {
            if isRender {
                shape
                    .fill(LinearGradient(colors: [DSColor.thumbnailTop, DSColor.thumbnailBottom], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0), radius: 1, x: 0, y: 1)
                shape
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                Gradient.Stop(color: DSColor.thumbnailEdge, location: 0),
                                Gradient.Stop(color: DSColor.thumbnailEdge.opacity(0), location: 0.6),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            } else {
                shape.fill(DSColor.cardElevated)
            }
            glyph
                .opacity(isDimmed ? 0.45 : 1)
        }
    }

    @ViewBuilder
    private var glyph: some View {
        let image = Image(systemName: systemImage)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: size * 0.54))
        if isRender {
            image.foregroundStyle(LinearGradient(colors: [DSColor.glyphTop, DSColor.glyphBottom], startPoint: .top, endPoint: .bottom))
        } else {
            image.foregroundStyle(DSColor.textSecondary)
        }
    }

    /// State badges are 0.43 of the thumbnail on a 1.5 pt card ring: a white cross on red, a black mark on
    /// amber (never white on amber). Risk badges are 0.38 rounded squares in the risk's fill.
    @ViewBuilder
    private func badgeView(_ badge: DSThumbnailBadge) -> some View {
        switch badge {
        case .offline:
            stateBadge(fill: DSColor.offlineFill, glyph: "xmark", ink: .white)
        case .unstable:
            stateBadge(fill: DSColor.degradedFill, glyph: "exclamationmark", ink: .black)
        case .risk(let risk):
            let side = size * 0.38
            RoundedRectangle(cornerRadius: DSLayout.badgeRadius, style: .continuous)
                .fill(DSColor.fill(DSTone.forRisk(risk)))
                .frame(width: side, height: side)
                .overlay {
                    if risk != .low {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: side * 0.6, weight: .bold))
                            .foregroundStyle(risk == .high ? Color.white : Color.black)
                    }
                }
                .padding(1.5)
                .background {
                    RoundedRectangle(cornerRadius: DSLayout.badgeRadius + 1.5, style: .continuous)
                        .fill(DSColor.card)
                }
        }
    }

    private func stateBadge(fill: Color, glyph: String, ink: Color) -> some View {
        let diameter = size * 0.43
        return Circle()
            .fill(fill)
            .frame(width: diameter, height: diameter)
            .overlay {
                Image(systemName: glyph)
                    .font(.system(size: diameter * 0.6, weight: .bold))
                    .foregroundStyle(ink)
            }
            .padding(1.5)
            .background {
                Circle().fill(DSColor.card)
            }
    }
}

/// A device kind's thumbnail, with a state badge only for exceptions (offline, unstable). Offline devices
/// fade.
struct DeviceThumbnail: View {
    private let kind: DeviceKind
    private let state: ReachabilityState
    private let size: CGFloat
    private let style: DSThumbnail.Style
    private let showsStateBadge: Bool

    init(
        kind: DeviceKind,
        state: ReachabilityState = .online,
        size: CGFloat = DSLayout.thumbnailRow,
        style: DSThumbnail.Style = .tile,
        showsStateBadge: Bool = true
    ) {
        self.kind = kind
        self.state = state
        self.size = size
        self.style = style
        self.showsStateBadge = showsStateBadge
    }

    var body: some View {
        DSThumbnail(systemImage: Self.symbol(for: kind), size: size, style: style, isDimmed: state == .offline, badge: badge)
    }

    private var badge: DSThumbnailBadge? {
        guard showsStateBadge else { return nil }
        switch state {
        case .offline: return .offline
        case .degraded: return .unstable
        case .online, .unknown: return nil
        }
    }

    /// The kind's filled glyph. `DeviceKind.systemImage` stays for Edit's kind picker.
    nonisolated static func symbol(for kind: DeviceKind) -> String {
        switch kind {
        case .router: return "wifi.router.fill"
        case .computer: return "laptopcomputer"
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .printer: return "printer.fill"
        case .tv: return "tv.fill"
        case .speaker: return "hifispeaker.fill"
        case .camera: return "web.camera.fill"
        case .nas: return "externaldrive.fill"
        case .iot: return "lightbulb.led.fill"
        case .console: return "gamecontroller.fill"
        case .watch: return "applewatch"
        case .hub: return "house.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}
