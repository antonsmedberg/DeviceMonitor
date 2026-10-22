import Foundation
import SwiftUI
import Testing
import UIKit
@testable import DeviceMonitor

@Suite("Design tokens")
@MainActor
struct DesignTokenTests {
    /// Status, text and accent inks stay readable on the card, the page and raised controls in all four
    /// appearances: WCAG 4.5:1, or 7:1 with Increase Contrast. The series inks never sit on raised controls,
    /// so they are checked on the card and the page.
    @Test func inksAreReadableOnSurfaces() throws {
        let accent = try #require(UIColor(named: "AccentColor"))
        let surfaces: [(name: String, color: UIColor)] = [
            ("card", UIColor(DSColor.card)),
            ("background", UIColor(DSColor.background)),
            ("cardElevated", UIColor(DSColor.cardElevated)),
        ]
        let inks: [(name: String, color: UIColor, onRaised: Bool)] = [
            ("online", UIColor(DSColor.online), true),
            ("degraded", UIColor(DSColor.degraded), true),
            ("offline", UIColor(DSColor.offline), true),
            ("latency", UIColor(DSColor.latency), false),
            ("jitter", UIColor(DSColor.jitter), false),
            ("textSecondary", UIColor(DSColor.textSecondary), true),
            ("textTertiary", UIColor(DSColor.textTertiary), true),
            ("accent", accent, true),
        ]
        for traits in Self.appearances {
            let minimum = traits.accessibilityContrast == .high ? 7.0 : 4.5
            for surface in surfaces {
                let background = surface.color.resolvedColor(with: traits)
                for ink in inks where ink.onRaised || surface.name != "cardElevated" {
                    let ratio = Self.contrastRatio(ink.color.resolvedColor(with: traits), background)
                    #expect(ratio >= minimum, "\(ink.name) on \(surface.name): \(ratio) in \(Self.describe(traits))")
                }
            }
        }
    }

    /// Status fills and healthy-history marks stand out from the card by 3:1 in all four appearances
    /// (WCAG 1.4.11).
    @Test func fillsStandOutFromCards() {
        let fills: [(name: String, color: UIColor)] = [
            ("onlineFill", UIColor(DSColor.onlineFill)),
            ("degradedFill", UIColor(DSColor.degradedFill)),
            ("offlineFill", UIColor(DSColor.offlineFill)),
            ("neutralMark", UIColor(DSColor.neutralMark)),
        ]
        for traits in Self.appearances {
            let card = UIColor(DSColor.card).resolvedColor(with: traits)
            for fill in fills {
                let ratio = Self.contrastRatio(fill.color.resolvedColor(with: traits), card)
                #expect(ratio >= 3, "\(fill.name): \(ratio) in \(Self.describe(traits))")
            }
        }
    }

    /// White labels on every accent choice's filled buttons: 4.5:1, or 7:1 with Increase Contrast.
    @Test func whiteLabelsAreReadableOnAccentFills() {
        for choice in AccentChoice.allCases {
            let fill = UIColor(DSColor.accentFill(for: choice))
            for traits in Self.appearances {
                let minimum = traits.accessibilityContrast == .high ? 7.0 : 4.5
                let ratio = Self.contrastRatio(.white, fill.resolvedColor(with: traits))
                #expect(ratio >= minimum, "\(choice.rawValue): \(ratio) in \(Self.describe(traits))")
            }
        }
    }

    @Test func fillsFollowStateHealthUptimeAndTone() {
        #expect(DSColor.fill(for: .online) == DSColor.onlineFill)
        #expect(DSColor.fill(for: .degraded) == DSColor.degradedFill)
        #expect(DSColor.fill(for: .offline) == DSColor.offlineFill)
        #expect(DSColor.fill(for: .unknown) == DSColor.noData)
        #expect(DSColor.fill(forHealth: 0.9) == DSColor.onlineFill)
        #expect(DSColor.fill(forHealth: 0.6) == DSColor.degradedFill)
        #expect(DSColor.fill(forHealth: 0.2) == DSColor.offlineFill)
        #expect(DSColor.fill(forUptime: .online) == DSColor.neutralMark)
        #expect(DSColor.fill(forUptime: .unstable) == DSColor.degradedFill)
        #expect(DSColor.fill(forUptime: .offline) == DSColor.offlineFill)
        #expect(DSColor.fill(forUptime: .noData) == DSColor.noData)
        #expect(DSColor.ink(.good) == DSColor.online)
        #expect(DSColor.ink(.warn) == DSColor.degraded)
        #expect(DSColor.ink(.bad) == DSColor.offline)
        #expect(DSColor.fill(.neutral) == DSColor.neutralMark)
        let cobalt: Color = DSColor.accentFill
        #expect(DSColor.accentFill(for: .blue) == cobalt)
    }

    /// Tile strokes and card edges stand out from the page by 3:1 with Increase Contrast. In standard dark the
    /// card has no edge: `cardEdge` resolves to clear, so no contrast check applies to it there.
    @Test func edgesStandOutWithIncreaseContrast() {
        let edges: [(name: String, color: UIColor)] = [
            ("stroke", UIColor(DSColor.stroke)),
            ("cardEdge", UIColor(DSColor.cardEdge)),
        ]
        for traits in Self.appearances where traits.accessibilityContrast == .high {
            let page = UIColor(DSColor.background).resolvedColor(with: traits)
            for edge in edges {
                let ratio = Self.contrastRatio(edge.color.resolvedColor(with: traits), page)
                #expect(ratio >= 3, "\(edge.name): \(ratio) in \(Self.describe(traits))")
            }
        }
        let standardDark = UITraitCollection { mutations in
            mutations.userInterfaceStyle = .dark
            mutations.accessibilityContrast = .normal
        }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        UIColor(DSColor.cardEdge).resolvedColor(with: standardDark).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(alpha == 0)
    }

    /// The screen margin is 16 pt below 600 pt wide and 20 pt from there.
    @Test func marginsFollowTheWidth() {
        #expect(DSLayout.margin(forWidth: 402) == 16)
        #expect(DSLayout.margin(forWidth: 440) == 16)
        #expect(DSLayout.margin(forWidth: 599) == 16)
        #expect(DSLayout.margin(forWidth: 600) == 20)
        #expect(DSLayout.margin(forWidth: 1032) == 20)
    }

    /// Columns follow the measured width at the default card minimum of 300 pt.
    @Test func columnsFollowTheMeasuredWidth() {
        #expect(LayoutColumns.fitting(width: 402, cardMinimum: 300) == .one)
        #expect(LayoutColumns.fitting(width: 659, cardMinimum: 300) == .one)
        #expect(LayoutColumns.fitting(width: 660, cardMinimum: 300) == .two)
        #expect(LayoutColumns.fitting(width: 979, cardMinimum: 300) == .two)
        #expect(LayoutColumns.fitting(width: 980, cardMinimum: 300) == .three)
    }

    /// Light and dark, each with and without Increase Contrast.
    private static var appearances: [UITraitCollection] {
        [UIUserInterfaceStyle.light, .dark].flatMap { style in
            [UIAccessibilityContrast.normal, .high].map { contrast in
                UITraitCollection { mutations in
                    mutations.userInterfaceStyle = style
                    mutations.accessibilityContrast = contrast
                }
            }
        }
    }

    private static func describe(_ traits: UITraitCollection) -> String {
        "style \(traits.userInterfaceStyle.rawValue), contrast \(traits.accessibilityContrast.rawValue)"
    }

    private static func contrastRatio(_ first: UIColor, _ second: UIColor) -> Double {
        let a = relativeLuminance(first)
        let b = relativeLuminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func relativeLuminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ channel: CGFloat) -> Double {
            let value = Double(channel)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
