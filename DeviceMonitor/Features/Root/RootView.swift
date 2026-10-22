import SwiftUI

/// Tab root. Tabs are never hidden (a hidden selected tab crashes on the iOS 27 SDK).
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dsMotion) private var motion
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Sheets zoom out of the controls that share this namespace: Scan and Add Device on Devices and on
    /// Overview, Edit on the device detail.
    @Namespace private var sheetNamespace
    /// Moves on by itself, so the accessory can say "stale" when rounds stop arriving.
    @State private var now = Date()

    init() {}

    /// The system setting or the in-app "Reduce visual effects", which this view injects below itself.
    private var reducesMotion: Bool {
        motion.reduceMotion || environment.settings.reduceEffects
    }

    var body: some View {
        @Bindable var router = environment.router
        let status = environment.monitorStatus(now: now)

        Group {
            if let error = environment.startupError {
                StartupFailureView(error: error)
            } else {
                TabView(selection: $router.selectedTab) {
                    Tab("Overview", systemImage: "gauge.with.needle", value: AppTab.overview) {
                        OverviewView(sheetNamespace: sheetNamespace)
                    }
                    .accessibilityIdentifier("tab.overview")
                    Tab("Devices", systemImage: "square.grid.2x2", value: AppTab.devices) {
                        DashboardView(sheetNamespace: sheetNamespace)
                    }
                    .accessibilityIdentifier("tab.devices")
                    Tab("Activity", systemImage: "clock", value: AppTab.activity) {
                        ActivityTimelineView()
                    }
                    .accessibilityIdentifier("tab.activity")
                    Tab("Insights", systemImage: "shield.lefthalf.filled", value: AppTab.insights) {
                        InsightsView()
                    }
                    .accessibilityIdentifier("tab.insights")
                    Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                        SettingsView()
                    }
                    .accessibilityIdentifier("tab.settings")
                }
                .tabViewStyle(.tabBarOnly)
                .tabBarMinimizeBehavior(.onScrollDown)
                // Only news earns the accessory, and only on compact widths: Overview's network capsule says it.
                .tabViewBottomAccessory(isEnabled: sizeClass == .compact && status.showsAccessory) {
                    MonitorStatusStrip(status: status, now: now)
                }
                .symbolEffectsRemoved(reducesMotion)
                .overlay(alignment: .top) {
                    VStack {
                        toast
                    }
                    .animation(DSMotion.animation(DSMotion.springSoft, reduceMotion: motion.reduceMotion), value: environment.bannerError)
                }
            }
        }
        .environment(\.dsReduceEffects, environment.settings.reduceEffects)
        .sheet(item: $router.sheet) { sheet in
            sheetContent(for: sheet)
                .environment(\.dsReduceEffects, environment.settings.reduceEffects)
                .symbolEffectsRemoved(reducesMotion)
        }
        .onAppear {
            if !environment.settings.hasCompletedOnboarding && !environment.isDemo {
                environment.router.present(.welcome)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceMonitorScanRequested)) { _ in
            environment.settings.pendingScanRequested = false
            environment.router.selectedTab = .overview
            environment.router.present(.scan)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                now = Date()
            }
        }
    }

    /// Errors raised anywhere (Settings actions, background work) surface on every tab.
    @ViewBuilder
    private var toast: some View {
        if let error = environment.bannerError, environment.router.sheet == nil {
            DSGlassToast(error: error) {
                environment.dismissBannerError()
            }
            .padding(.top, DSLayout.space8)
            .transition(DSMotion.bannerTransition(reduceMotion: motion.reduceMotion))
            .task(id: error) {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                environment.dismissBannerError()
            }
            .onAppear {
                AccessibilityNotification.Announcement(error.errorDescription ?? "Something went wrong.").post()
            }
        }
    }

    /// Scan and Add Device zoom out of the control on the tab they were opened from (the Devices toolbar, or
    /// Overview's Scan button and Add shortcut) and Edit out of the detail's More button. On a tab without
    /// such a control the sheet slides up as usual; under Reduce Motion every sheet cross-fades.
    @ViewBuilder
    private func sheetContent(for sheet: AppSheet) -> some View {
        switch sheet {
        case .addDevice:
            transitioned(AddDeviceView(), from: zoomSource(onDevices: "add", onOverview: "add.overview"))
        case .scan:
            transitioned(ScanView(), from: zoomSource(onDevices: "scan", onOverview: "scan.overview"))
        case .welcome:
            WelcomeView()
        case .editDevice(let id):
            transitioned(EditDeviceView(deviceID: id), from: "edit")
        }
    }

    /// The selected tab's zoom source, or nil on a tab without one.
    private func zoomSource(onDevices: String, onOverview: String) -> String? {
        switch environment.router.selectedTab {
        case .devices: return onDevices
        case .overview: return onOverview
        case .activity, .insights, .settings: return nil
        }
    }

    /// The zoom and the cross-fade are different types, so each branches instead of using a ternary.
    @ViewBuilder
    private func transitioned<Content: View>(_ content: Content, from sourceID: String?) -> some View {
        if reducesMotion {
            content
                .navigationTransition(.crossFade)
        } else if let sourceID {
            content
                .navigationTransition(.zoom(sourceID: sourceID, in: sheetNamespace))
        } else {
            content
        }
    }
}

/// Shown instead of the tabs when local storage cannot be opened at all.
struct StartupFailureView: View {
    let error: DeviceMonitorError

    var body: some View {
        VStack(spacing: DSLayout.space20) {
            ContentUnavailableView {
                Label("Storage Problem", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                VStack(spacing: DSLayout.space8) {
                    Text(error.errorDescription ?? "")
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                    }
                }
            }
        }
        .padding()
        .background {
            DSColor.background
                .ignoresSafeArea()
        }
    }
}

/// The bottom accessory above the tab bar, there only when monitoring has news: scanning, paused, off Wi‑Fi or
/// stale. Rather than shrink its text it steps down from the full headline to the short one to the symbol
/// alone. When the tab bar is minimised it shows the state without the Pause button.
struct MonitorStatusStrip: View {
    let status: MonitorStatus
    let now: Date

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.dsMotion) private var motion

    init(status: MonitorStatus, now: Date) {
        self.status = status
        self.now = now
    }

    private var isInline: Bool { placement == .inline }

    private var isScanning: Bool {
        if case .scanning = status.kind { return true }
        return false
    }

    /// Off Wi‑Fi and stale are warnings; scanning and paused are not.
    private var symbolColor: Color {
        switch status.kind {
        case .offWiFi, .stale: return DSColor.degraded
        case .scanning: return DSColor.textPrimary
        case .empty, .live, .paused: return DSColor.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: DSLayout.space8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DSLayout.space8) {
                    symbol
                    Text(status.headline(now: now))
                    if environment.isDemo && !isInline && !LaunchArguments.current.isScreenshots {
                        Text("Demo")
                            .font(DSTypography.badge)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                HStack(spacing: DSLayout.space8) {
                    symbol
                    Text(status.shortHeadline(now: now))
                }
                symbol
            }
            .font(DSTypography.rowSubtitle.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(DSColor.textPrimary)
            .lineLimit(1)
            Spacer(minLength: 0)
            if !isInline {
                Button {
                    environment.togglePause()
                } label: {
                    Image(systemName: environment.isPausedByUser ? "play.fill" : "pause.fill")
                        .font(DSTypography.rowSubtitle.weight(.bold))
                        .foregroundStyle(DSColor.textPrimary)
                        .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
                        .frame(width: DSLayout.minTapTarget, height: DSLayout.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(environment.isPausedByUser ? "Resume Monitoring" : "Pause Monitoring")
            }
        }
        .padding(.horizontal, DSLayout.space16)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("devices.accessory")
    }

    private var symbol: some View {
        Image(systemName: status.symbol)
            .font(DSTypography.rowSubtitle.weight(.semibold))
            .foregroundStyle(symbolColor)
            .symbolEffect(.variableColor.iterative, isActive: isScanning && !motion.reduceMotion && !LaunchArguments.current.isScreenshots)
            .accessibilityHidden(true)
    }
}

extension AppEnvironment {
    /// What monitoring is doing at `now`, for the accessory, Overview's network capsule and Settings.
    func monitorStatus(now: Date) -> MonitorStatus {
        MonitorStatus.make(
            isScanning: isScanning,
            scanProgress: scanProgress,
            isPausedByUser: isPausedByUser,
            pauseReason: pauseReason,
            isOnWiFi: pathStatus.isWiFi,
            isDemo: isDemo,
            hasDevices: !directory.devices.isEmpty,
            lastRoundAt: directory.lastRoundAt,
            intervalSeconds: settings.monitor.baseIntervalSeconds,
            now: now
        )
    }
}

#Preview("App") {
    RootView()
        .environment(AppEnvironment.demo())
}
