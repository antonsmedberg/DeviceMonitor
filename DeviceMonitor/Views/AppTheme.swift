import SwiftUI

enum AppTheme {
    enum Layout {
        static let screenInset: CGFloat = 16
        static let contentSpacing: CGFloat = 16
        static let cardCornerRadius: CGFloat = 24
        static let secondaryCardCornerRadius: CGFloat = 20
        static let compactCardCornerRadius: CGFloat = 18
        static let fieldCornerRadius: CGFloat = 18
        static let controlCornerRadius: CGFloat = 18
        static let buttonHeight: CGFloat = 52
        static let minimumTapTarget: CGFloat = 44
        static let iconButtonSize: CGFloat = 48
        static let compactIconButtonSize: CGFloat = 40
        static let smallIconButtonSize: CGFloat = 36
        static let microIconButtonSize: CGFloat = 34
        static let modalCardPadding: CGFloat = 16
    }

    static let backgroundBase = Color(red: 0.03, green: 0.05, blue: 0.11)
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.20, green: 0.31, blue: 0.50),
            Color(red: 0.11, green: 0.17, blue: 0.30),
            Color(red: 0.04, green: 0.07, blue: 0.14)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let accentGlow = RadialGradient(
        colors: [
            Color(red: 0.41, green: 0.71, blue: 0.99).opacity(0.24),
            Color(red: 0.25, green: 0.45, blue: 0.76).opacity(0.11),
            .clear
        ],
        center: .topTrailing,
        startRadius: 12,
        endRadius: 260
    )
    static let secondaryGlow = RadialGradient(
        colors: [
            Color(red: 0.17, green: 0.29, blue: 0.51).opacity(0.13),
            .clear
        ],
        center: .bottomLeading,
        startRadius: 8,
        endRadius: 220
    )

    static let primaryText = Color(red: 0.95, green: 0.97, blue: 0.99)
    static let secondaryText = Color(red: 0.78, green: 0.84, blue: 0.91)
    static let tertiaryText = Color(red: 0.62, green: 0.70, blue: 0.80)
    static let accent = Color(red: 0.41, green: 0.71, blue: 0.99)

    static let online = Color(red: 0.28, green: 0.84, blue: 0.60)
    static let offline = Color(red: 0.95, green: 0.53, blue: 0.46)
    static let warning = Color(red: 0.98, green: 0.73, blue: 0.28)

    static let cardFill = Color(red: 0.09, green: 0.13, blue: 0.24).opacity(0.96)
    static let elevatedCardFill = Color(red: 0.11, green: 0.18, blue: 0.31).opacity(0.98)
    static let sheetCardFill = Color(red: 0.10, green: 0.16, blue: 0.28).opacity(0.97)
    static let inputFieldFill = Color(red: 0.08, green: 0.12, blue: 0.22).opacity(0.96)
    static let controlFill = Color(red: 0.09, green: 0.14, blue: 0.24).opacity(0.95)
    static let selectedControlFill = accent.opacity(0.15)
    static let highlightFill = Color.white.opacity(0.06)
    static let accentFill = accent.opacity(0.12)
    static let emptyStateIconFill = Color.white.opacity(0.08)

    static let cardStroke = Color.white.opacity(0.14)
    static let strongStroke = Color.white.opacity(0.20)
    static let fieldStroke = Color.white.opacity(0.12)
    static let shadow = Color.black.opacity(0.38)

}

struct AppScreenBackground: View {
    var body: some View {
        ZStack {
            AppTheme.backgroundBase
            AppTheme.backgroundGradient
            AppTheme.accentGlow
            AppTheme.secondaryGlow

            LinearGradient(
                colors: [
                    Color.white.opacity(0.04),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    func appCardStyle(
        cornerRadius: CGFloat = AppTheme.Layout.compactCardCornerRadius,
        fill: Color = AppTheme.cardFill,
        stroke: Color = AppTheme.cardStroke,
        shadow: Color = AppTheme.shadow,
        shadowRadius: CGFloat = 22,
        shadowY: CGFloat = 14
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )
        )
        .shadow(color: shadow, radius: shadowRadius, y: shadowY)
    }

    func appGlassButton(cornerRadius: CGFloat = AppTheme.Layout.controlCornerRadius) -> some View {
        buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: cornerRadius))
            .glassEffectTransition(.materialize)
    }

    func appProminentGlassButton(
        cornerRadius: CGFloat = AppTheme.Layout.controlCornerRadius,
        tint: Color = AppTheme.accent
    ) -> some View {
        buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: cornerRadius))
            .tint(tint)
            .glassEffectTransition(.materialize)
    }

    func appCircularGlassButton() -> some View {
        buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .clipShape(Circle())
            .glassEffectTransition(.materialize)
    }

    func appCompactCircularGlassButton() -> some View {
        buttonStyle(.glass)
            .controlSize(.mini)
            .buttonBorderShape(.circle)
            .clipShape(Circle())
            .glassEffectTransition(.materialize)
    }
}
