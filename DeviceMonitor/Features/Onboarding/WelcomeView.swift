import SwiftUI

/// First-run welcome, the app's one brand surface: the mark sending a ping over the brand gradient, what the
/// app does, what stays private, then the Local Network prompt. Everything sits on one leading edge in a
/// column of at most 520 pt. Swiping the sheet away is disabled, so the choice is always made with a button.
struct WelcomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    /// The real appearance: the content below is forced dark, the gradient and the mark are not.
    @Environment(\.colorScheme) private var colorScheme
    @State private var isRequesting = false
    /// Feature icons: 24 pt line icons in a 28 pt column, scaled with the text.
    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 24
    @ScaledMetric(relativeTo: .title2) private var iconColumn: CGFloat = 28

    init() {}

    private struct Feature: Identifiable {
        let id: String
        let title: String
        let message: String
        let systemImage: String
    }

    private let features = [
        Feature(id: "see", title: "Every device on your Wi‑Fi", message: "Finds routers, computers, printers, speakers and smart-home gear, then keeps checking them.", systemImage: "wifi.router"),
        Feature(id: "honest", title: "Honest status", message: "Reported offline only after several missed checks, so one dropped packet is never an alarm.", systemImage: "waveform.path.ecg"),
        Feature(id: "strangers", title: "Spot strangers", message: "New and untrusted devices stand out, with a security score that explains itself.", systemImage: "person.crop.circle.badge.questionmark"),
        Feature(id: "private", title: "Private by design", message: "No account, no ads, no location. Everything stays on this iPhone.", systemImage: "lock.shield"),
    ]

    /// Cobalt-700: 7.03:1 on the white Continue capsule.
    private static let continueInk = Color(red: 35.0 / 255, green: 71.0 / 255, blue: 218.0 / 255)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PingMark(style: .onBrand(isDark: colorScheme == .dark), isLive: true, isRippling: true)
                    .frame(height: 112)
                VStack(alignment: .leading, spacing: DSLayout.space8) {
                    Text("Know every device on your network")
                        .font(Font.largeTitle.bold())
                        .foregroundStyle(Color.white)
                        .accessibilityAddTraits(.isHeader)
                    Text("DeviceMonitor watches your Wi‑Fi so you don't have to.")
                        .font(.body)
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DSLayout.space32)
                VStack(alignment: .leading, spacing: DSLayout.space20) {
                    ForEach(features) { feature in
                        featureRow(feature)
                    }
                }
                .padding(.top, DSLayout.space32)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal, DSLayout.space20)
            .padding(.top, 48)
            .padding(.bottom, DSLayout.space24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: DSLayout.space12) {
                Text("Next, iOS asks whether DeviceMonitor may find devices on your local network.")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: finish) {
                    Group {
                        if isRequesting {
                            ProgressView()
                                .tint(Self.continueInk)
                        } else {
                            Text("Continue")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(Self.continueInk)
                    .frame(maxWidth: .infinity, minHeight: DSLayout.actionHeight)
                    .background {
                        Capsule().fill(Color.white)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isRequesting)
                .accessibilityIdentifier("welcome.continue")
                Button {
                    environment.settings.hasCompletedOnboarding = true
                    dismiss()
                } label: {
                    Text("Not Now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(minHeight: DSLayout.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("welcome.notNow")
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, DSLayout.space20)
            .padding(.bottom, DSLayout.space8)
        }
        // System controls render light on the dark brand surface.
        .environment(\.colorScheme, .dark)
        .background {
            DSColor.brandGradient(colorScheme)
                .ignoresSafeArea()
        }
        .interactiveDismissDisabled(true)
    }

    /// A line icon, the bold title and the message, on one leading edge.
    private func featureRow(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: DSLayout.space16) {
            Image(systemName: feature.systemImage)
                .font(.system(size: iconSize))
                .environment(\.symbolVariants, SymbolVariants.none)
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: iconColumn)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DSLayout.space2) {
                Text(feature.title)
                    .font(DSTypography.headerName)
                    .foregroundStyle(Color.white)
                Text(feature.message)
                    .font(DSTypography.body)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func finish() {
        isRequesting = true
        Task {
            await environment.requestLocalNetworkPermission()
            environment.settings.hasCompletedOnboarding = true
            isRequesting = false
            dismiss()
            try? await Task.sleep(for: .milliseconds(400))
            environment.router.present(.scan)
        }
    }
}

#Preview("Welcome") {
    WelcomeView()
        .environment(AppEnvironment.demo())
}
