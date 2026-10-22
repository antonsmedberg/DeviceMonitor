import SwiftUI
import UIKit

/// Semantic colours. Colour means one thing: the accent (through `.tint`) means "you can act here", mint,
/// amber and red mean state, cyan and violet are the latency and jitter series, and everything else is
/// graphite. Inks (text and symbols) reach 4.5:1 on the page, cards and raised controls, 7:1 with Increase
/// Contrast. Fills (dots, cells, bars) reach 3:1 on cards and always sit next to a word or a symbol.
enum DSColor {
    // Surfaces and lines
    /// The page behind cards, and the dashboard's on-page sections.
    static let background = dynamic(0xF2F3F6, dark: 0x131417, hcLight: 0xE9EBEF, hcDark: 0x0B0C0E)
    /// Cards, list rows and form rows.
    static let card = dynamic(0xFFFFFF, dark: 0x1C1E22, hcLight: 0xFFFFFF, hcDark: 0x17191C)
    /// Controls on a card: unselected pills, text buttons on cards, pressed tiles, wells.
    static let cardElevated = dynamic(0xF0F1F4, dark: 0x25282D, hcLight: 0xE4E7EC, hcDark: 0x24272C)
    /// Unselected chips, shortcut tiles and text buttons on the page.
    static let chip = dynamic(0xFFFFFF, dark: 0x1C1E22, hcLight: 0xFFFFFF, hcDark: 0x17191C)
    /// Row separators, subtitle dividers and scale ticks.
    static let hairline = dynamic(0xE1E4E9, dark: 0x30343A, hcLight: 0x9AA0AA, hcDark: 0x5C626C)
    /// The outline of action and shortcut tiles.
    static let stroke = dynamic(0xCDD2D9, dark: 0x41454D, hcLight: 0x7B828D, hcDark: 0x858C97)
    /// The card's edge in light mode and with Increase Contrast; clear in standard dark.
    static let cardEdge = dynamicEdge(0xE1E4E9, hcLight: 0x7B828D, hcDark: 0x858C97)
    /// Dashed chart gridlines, radar and map rings.
    static let grid = dynamic(0xE1E4E9, dark: 0x353940, hcLight: 0xAEB4BD, hcDark: 0x5C626C)
    /// The container of the container-style segmented control.
    static let segmentTrack = dynamic(0xE6E8EC, dark: 0x1C1E22, hcLight: 0xD5D9DF, hcDark: 0x24272C)
    /// The selected segment's well; it always carries an edge, because the fill alone is close to the track.
    static let segmentWell = dynamic(0xFFFFFF, dark: 0x131417, hcLight: 0xFFFFFF, hcDark: 0x0B0C0E)

    // Text
    static let textPrimary = dynamic(0x121418, dark: 0xF5F6F8, hcLight: 0x000000, hcDark: 0xFFFFFF)
    static let textSecondary = dynamic(0x5A6170, dark: 0xB4B9C1, hcLight: 0x3B414A, hcDark: 0xD3D7DD)
    /// Idle values ("MAC unknown"), y-axis labels, the unit label and "Checking".
    static let textTertiary = dynamic(0x646B76, dark: 0x8F96A1, hcLight: 0x424952, hcDark: 0xBAC0C8)

    // Data series
    static let latency = dynamic(0x0A7099, dark: 0x5CC3EA, hcLight: 0x004B68, hcDark: 0x8AD6F2)
    static let jitter = dynamic(0x7F45BE, dark: 0xB37CDE, hcLight: 0x5F2A9C, hcDark: 0xC694F0)

    // Status inks (text and symbols)
    static let online = dynamic(0x046F4B, dark: 0x52DEA8, hcLight: 0x034D33, hcDark: 0xA1ECCB)
    static let degraded = dynamic(0x845001, dark: 0xF6B40A, hcLight: 0x6D3F01, hcDark: 0xFAD483)
    static let offline = dynamic(0xD00E2B, dark: 0xFF7171, hcLight: 0x950216, hcDark: 0xFDA6A3)
    static let unknown = textSecondary

    // Status fills (dots, cells, bars, discs)
    static let onlineFill = dynamic(0x009469, dark: 0x52DEA8, hcLight: 0x07855B, hcDark: 0xA1ECCB)
    static let degradedFill = dynamic(0xB97D06, dark: 0xF6B40A, hcLight: 0x996302, hcDark: 0xF6B40A)
    static let offlineFill = dynamic(0xB0051F, dark: 0xF13D48, hcLight: 0x910215, hcDark: 0xFF7171)
    /// Healthy history (up cells), known radar blips, rug ticks and kind-mix bars.
    static let neutralMark = dynamic(0x868D98, dark: 0x6F7682, hcLight: 0x5E6570, hcDark: 0x9AA1AC)
    /// Cells with no measurement.
    static let noData = dynamic(0xE3E6EA, dark: 0x2E3238, hcLight: 0xC9CED6, hcDark: 0x3C4148)

    // Interaction
    /// The two filled buttons (Scan Again, Continue) behind white labels. Interactive ink is `.tint`.
    static let accentFill = dynamic(0x2D5CF6, dark: 0x2D5CF6, hcLight: 0x2347DA, hcDark: 0x2347DA)

    // Device thumbnails ("product render", 42 and 48 pt)
    static let thumbnailTop = dynamic(0xFFFFFF, dark: 0x353A42, hcLight: 0xFFFFFF, hcDark: 0x2E3238)
    static let thumbnailBottom = dynamic(0xE7EAEF, dark: 0x23262B, hcLight: 0xE4E7EC, hcDark: 0x1E2125)
    static let thumbnailEdge = dynamic(0xD5DAE1, dark: 0x4A4F57, hcLight: 0x7B828D, hcDark: 0x858C97)
    static let glyphTop = dynamic(0x5E6672, dark: 0xFFFFFF, hcLight: 0x2B3036, hcDark: 0xFFFFFF)
    static let glyphBottom = dynamic(0x22262C, dark: 0xAAB1BB, hcLight: 0x000000, hcDark: 0xD3D7DD)

    /// The mark's bowl on the brand gradient.
    static let brandBowl = fixed(0xC6DAFF)
    /// The mark's dot on the brand gradient: mint, because the dot is a device answering.
    static let brandSignal = fixed(0x52DEA8)

    /// The filled-button colour for an accent choice.
    static func accentFill(for choice: AccentChoice) -> Color {
        switch choice {
        case .blue: return accentFill
        case .graphite: return graphiteFill
        }
    }

    /// The brand surface (Welcome and the Settings tile), top to bottom, as the light and dark app icons.
    static func brandGradient(_ scheme: ColorScheme) -> LinearGradient {
        let colors = scheme == .dark
            ? [fixed(0x1A3089), fixed(0x0B1233)]
            : [fixed(0x2D5CF6), fixed(0x1A3089), fixed(0x111F59)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    static func tint(for state: ReachabilityState) -> Color {
        switch state {
        case .online: return online
        case .degraded: return degraded
        case .offline: return offline
        case .unknown: return unknown
        }
    }

    static func tint(for risk: PortRisk) -> Color {
        ink(DSTone.forRisk(risk))
    }

    static func tint(forHealth score: Double) -> Color {
        switch score {
        case 0.85...: return online
        case 0.5..<0.85: return degraded
        default: return offline
        }
    }

    /// Mark colour for a current state: map cells and dots.
    static func fill(for state: ReachabilityState) -> Color {
        switch state {
        case .online: return onlineFill
        case .degraded: return degradedFill
        case .offline: return offlineFill
        case .unknown: return noData
        }
    }

    /// Mark colour for a health fraction, in the same bands as `tint(forHealth:)`.
    static func fill(forHealth score: Double) -> Color {
        switch score {
        case 0.85...: return onlineFill
        case 0.5..<0.85: return degradedFill
        default: return offlineFill
        }
    }

    /// Cell colour for a stretch of history. Up time is grey, so red means down and nothing else.
    static func fill(forUptime state: UptimeState) -> Color {
        switch state {
        case .online: return neutralMark
        case .unstable: return degradedFill
        case .offline: return offlineFill
        case .noData: return noData
        }
    }

    /// Text and symbol colour for a tone.
    static func ink(_ tone: DSTone) -> Color {
        switch tone {
        case .neutral: return textSecondary
        case .good: return online
        case .warn: return degraded
        case .bad: return offline
        case .latency: return latency
        case .jitter: return jitter
        }
    }

    /// Mark colour for a tone: dots, cells, bars and scale stops.
    static func fill(_ tone: DSTone) -> Color {
        switch tone {
        case .neutral: return neutralMark
        case .good: return onlineFill
        case .warn: return degradedFill
        case .bad: return offlineFill
        case .latency: return latency
        case .jitter: return jitter
        }
    }

    private static let graphiteFill = dynamic(0x545C6B, dark: 0x545C6B, hcLight: 0x414853, hcDark: 0x414853)

    /// A colour per appearance: light, dark and their Increase Contrast variants, as 0xRRGGBB. Nonisolated, so
    /// UIKit may resolve the colour on any thread.
    nonisolated private static func dynamic(_ light: UInt32, dark: UInt32, hcLight: UInt32, hcDark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let highContrast = traits.accessibilityContrast == .high
            switch (traits.userInterfaceStyle == .dark, highContrast) {
            case (true, true): return DSColor.uiColor(hcDark)
            case (true, false): return DSColor.uiColor(dark)
            case (false, true): return DSColor.uiColor(hcLight)
            case (false, false): return DSColor.uiColor(light)
            }
        })
    }

    /// Like `dynamic`, but clear in standard dark: `uiColor(_:)` always builds alpha 1.
    nonisolated private static func dynamicEdge(_ light: UInt32, hcLight: UInt32, hcDark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            switch (traits.userInterfaceStyle == .dark, traits.accessibilityContrast == .high) {
            case (true, true): return DSColor.uiColor(hcDark)
            case (true, false): return .clear
            case (false, true): return DSColor.uiColor(hcLight)
            case (false, false): return DSColor.uiColor(light)
            }
        })
    }

    /// The same colour in every appearance, as 0xRRGGBB.
    private static func fixed(_ hex: UInt32) -> Color {
        Color(uiColor: uiColor(hex))
    }

    nonisolated private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// What a value's colour means. Presentation code picks a tone; only DSColor turns it into a colour.
nonisolated enum DSTone: String, Sendable, Hashable, CaseIterable {
    case neutral, good, warn, bad, latency, jitter

    /// Online good, unstable warn, offline bad, checking neutral.
    static func forState(_ state: ReachabilityState) -> DSTone {
        switch state {
        case .online: return .good
        case .degraded: return .warn
        case .offline: return .bad
        case .unknown: return .neutral
        }
    }

    /// Low neutral, medium warn, high bad.
    static func forRisk(_ risk: PortRisk) -> DSTone {
        switch risk {
        case .low: return .neutral
        case .medium: return .warn
        case .high: return .bad
        }
    }

    /// The security score in the bands of `SecurityScore.grade`: 75 and up good, 50 to 74 warn, else bad.
    static func forScore(_ value: Int) -> DSTone {
        switch value {
        case 75...: return .good
        case 50..<75: return .warn
        default: return .bad
        }
    }
}

/// Dynamic Type text styles only. Hierarchy comes from weight and grey, not size; numbers that update live
/// use monospaced digits.
enum DSTypography {
    /// Device, port, settings and feed row titles.
    static let rowTitle: Font = .callout
    /// A row's primary metric.
    static let rowValue: Font = Font.callout.monospacedDigit()
    /// The detail header name, the network capsule title and the gateway name.
    static let headerName: Font = Font.callout.bold()
    /// Card and section titles.
    static let cardTitle: Font = Font.subheadline.bold()
    /// Qualifiers, summary lines, the info grid, links, segment and chip labels, text buttons and stat rows.
    static let body: Font = .subheadline
    static let bodyValue: Font = Font.subheadline.monospacedDigit()
    /// The selected segment or chip: weight is the non-colour cue.
    static let segmentSelected: Font = Font.subheadline.weight(.semibold)
    static let rowSubtitle: Font = .footnote
    static let rowSecondaryValue: Font = Font.footnote.monospacedDigit()
    /// List section headers ("Online (11)").
    static let listHeader: Font = .footnote
    /// Tile and scale labels.
    static let tileLabel: Font = .caption
    static let badge: Font = Font.caption2.weight(.semibold)
    /// Chart axes, the unit label, strip captions and legends.
    static let axis: Font = Font.caption2.monospacedDigit()
}

/// Spacing, sizes, radii and shapes on one 16-pt grid.
enum DSLayout {
    static let space2: CGFloat = 2
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32

    static let cardRadius: CGFloat = 26
    /// Pills, chips, tiles, text buttons and the segment well.
    static let controlRadius: CGFloat = 8
    /// The segmented control's track; its well is 8 = 12 − 4, concentric.
    static let segmentRadius: CGFloat = 12
    /// The risk badge on a service thumbnail.
    static let badgeRadius: CGFloat = 4

    /// Device rows, with list insets 8 / 16 / 8 / 16 around 40 pt of content.
    static let rowHeight: CGFloat = 56
    static let settingsRowHeight: CGFloat = 44
    static let statRowHeight: CGFloat = 40
    /// The container-style segmented control; outlined pills are `pillHeight`.
    static let segmentHeight: CGFloat = 44
    /// Visual heights; the hit area is `minTapTarget`.
    static let pillHeight: CGFloat = 32
    static let chipHeight: CGFloat = 32
    /// Action and shortcut tiles, at least; they grow with text.
    static let tileHeight: CGFloat = 50
    static let textButtonHeight: CGFloat = 36
    /// Welcome's Continue.
    static let actionHeight: CGFloat = 50

    static let thumbnailRow: CGFloat = 28
    static let thumbnailService: CGFloat = 42
    static let thumbnailHeader: CGFloat = 48

    static let scaleHeight: CGFloat = 8
    static let markerSize: CGFloat = 24
    static let stripHeight: CGFloat = 24
    static let chartHeightOverview: CGFloat = 148
    static let chartHeightDetail: CGFloat = 180
    /// Chart height when the container is at least 600 pt wide.
    static let chartHeightRegular: CGFloat = 220

    /// Between on-page dashboard sections.
    static let sectionGap: CGFloat = 28
    /// Between cards and list sections.
    static let cardGap: CGFloat = 20
    static let minTapTarget: CGFloat = 44

    /// The screen margin: 16 pt below 600 pt wide, 20 pt from there.
    static func margin(forWidth width: CGFloat) -> CGFloat {
        width >= 600 ? 20 : 16
    }

    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
    }

    static var controlShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: controlRadius, style: .continuous)
    }
}

/// One set of numbers for every "ping" motion, so the ripple, the scan waves and the breathing dots read as
/// one language.
nonisolated enum PingMotion {
    /// Seconds per wave cycle.
    static let ripplePeriod: Double = 2.4
    /// Waves in flight.
    static let rippleCount: Int = 3
    /// A wave's opacity as it leaves; it fades to 0, easing out.
    static let rippleStartOpacity: Double = 0.55
    /// End stroke ÷ start stroke.
    static let strokeTaper: Double = 12.0 / 44.0
    /// Seconds for one direction of a breath.
    static let breathHalfPeriod: Double = 1.1
    /// Breathing scale for dots of 12 pt and more.
    static let breathScale: Double = 0.84
    /// Breathing opacity for dots under 12 pt.
    static let breathOpacity: Double = 0.45
}
