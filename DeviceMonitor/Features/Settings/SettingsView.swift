import SwiftUI
import UniformTypeIdentifiers

/// Settings as one grouped list on the page colour: the app's header, monitoring, then one row per page with a
/// line icon in the tint, and Restore Defaults. The search field finds every control on every page and shows
/// the controls themselves, each with the page it lives on.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var query = ""

    init() {}

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The controls that match the query and exist right now, in page order.
    private var results: [SettingsControl] {
        SettingsControl.allCases.filter { control in
            control.matches(query) && control.isAvailable(in: environment)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isSearching {
                    searchResults
                } else {
                    groups
                }
            }
            .accessibilityIdentifier("screen.settings")
            .dsGroupedList()
            .dsFormColumn()
            // 8 pt under the search field, here and on the first section: it has no header, so the grouped style
            // would leave about 45 pt.
            .contentMargins(.top, DSLayout.space8, for: .scrollContent)
            .overlay {
                if isSearching && results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        }
        // On the stack, so a change made on a pushed page applies as well.
        .onChange(of: environment.settings.monitor) { _, _ in
            environment.applySettings()
        }
        .onChange(of: environment.settings.policy) { _, _ in
            environment.applySettings()
        }
    }

    @ViewBuilder
    private var groups: some View {
        Section {
            SettingsHeaderRow()
                .dsListRow()
        }
        .listSectionMargins(.top, DSLayout.space8)
        Section {
            Group {
                SettingsControlRow(.status)
                SettingsControlRow(.checkInterval)
            }
            .dsListRow()
        } header: {
            DSListHeader("Monitoring")
        }
        Section {
            Group {
                pageLink(.probes)
                pageLink(.sensitivity)
                pageLink(.networks)
            }
            .dsListRow()
        }
        Section {
            Group {
                pageLink(.appearance)
                SettingsControlRow(.haptics)
                pageLink(.privacy)
            }
            .dsListRow()
        }
        Section {
            pageLink(.data)
                .dsListRow()
        }
        Section {
            pageLink(.about)
                .dsListRow()
        }
        Section {
            SettingsControlRow(.restoreDefaults)
                .dsListRow()
        }
    }

    /// One section of the matching controls, each with its page under its title. With no match the list is
    /// empty and the search placeholder covers it.
    @ViewBuilder
    private var searchResults: some View {
        let matches = results
        if !matches.isEmpty {
            Section {
                ForEach(matches) { control in
                    SettingsControlRow(control, showsPage: true)
                }
                .dsListRow()
            } header: {
                DSListHeader("Results", count: matches.count)
            }
        }
    }

    private func pageLink(_ page: SettingsPage) -> some View {
        NavigationLink {
            SettingsPageView(page: page)
        } label: {
            DSSettingsLabel(page.title, systemImage: page.systemImage)
        }
        .accessibilityIdentifier(page.identifier)
    }
}

// MARK: - Pages and controls

/// The pages behind the top-level rows.
private nonisolated enum SettingsPage: String, CaseIterable {
    case probes, sensitivity, networks, appearance, privacy, data, about

    var title: String {
        switch self {
        case .probes: return "Probes"
        case .sensitivity: return "Sensitivity"
        case .networks: return "Networks"
        case .appearance: return "Appearance"
        case .privacy: return "Privacy"
        case .data: return "Data"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .probes: return "dot.scope"
        case .sensitivity: return "slider.horizontal.3"
        case .networks: return "network"
        case .appearance: return "paintpalette"
        case .privacy: return "hand.raised"
        case .data: return "archivebox"
        case .about: return "info.circle"
        }
    }

    var identifier: String {
        switch self {
        case .probes: return "settings.row.probes"
        case .sensitivity: return "settings.row.sensitivity"
        case .networks: return "settings.row.networks"
        case .appearance: return "settings.row.appearance"
        case .privacy: return "settings.row.privacy"
        case .data: return "settings.row.data"
        case .about: return "settings.row.about"
        }
    }

    var footer: String? {
        switch self {
        case .probes:
            return "Devices are checked with a TCP connection first; ping and UDP help when a device refuses connections. Unstable devices are checked more often, long-offline ones less often."
        case .privacy:
            return "No account, no analytics, no location. Everything stays on this iPhone."
        case .about:
            return "Demo data shows a sample home network instead of your Wi‑Fi after the next launch. iOS does not let apps keep scanning in the background, read MAC addresses, or scan networks larger than /22; everything else happens while the app is open."
        case .sensitivity, .networks, .appearance, .data:
            return nil
        }
    }
}

/// Every control in Settings, registered once: where it lives and the words people search for it with. The
/// same control view appears on its page and in search results, never both at once.
private nonisolated enum SettingsControl: String, CaseIterable, Identifiable {
    case status, checkInterval
    case icmp, udp, pauseOffWiFi
    case missesToOffline, recoveryHits, giveUpAfter
    case accent, reduceEffects
    case haptics
    case localNetwork, openSettings, unavailableProbes, privacyPolicy
    case exportCSV, exportJSON, trimHistory, resetNicknames, deleteHistory
    case version, demoData, sourceCode
    case restoreDefaults

    var id: String { rawValue }

    /// The page it sits on; nil for the top level.
    var page: SettingsPage? {
        switch self {
        case .status, .checkInterval, .haptics, .restoreDefaults: return nil
        case .icmp, .udp, .pauseOffWiFi: return .probes
        case .missesToOffline, .recoveryHits, .giveUpAfter: return .sensitivity
        case .accent, .reduceEffects: return .appearance
        case .localNetwork, .openSettings, .unavailableProbes, .privacyPolicy: return .privacy
        case .exportCSV, .exportJSON, .trimHistory, .resetNicknames, .deleteHistory: return .data
        case .version, .demoData, .sourceCode: return .about
        }
    }

    /// The name shown under a search result.
    var pageTitle: String {
        if let page { return page.title }
        switch self {
        case .status, .checkInterval: return "Monitoring"
        default: return "Settings"
        }
    }

    var title: String {
        switch self {
        case .status: return "Status"
        case .checkInterval: return "Check every"
        case .icmp: return "Ping (ICMP)"
        case .udp: return "UDP probes"
        case .pauseOffWiFi: return "Pause off Wi‑Fi"
        case .missesToOffline: return "Misses before offline"
        case .recoveryHits: return "Answers to come back"
        case .giveUpAfter: return "Give up after"
        case .accent: return "Accent"
        case .reduceEffects: return "Reduce visual effects"
        case .haptics: return "Haptics"
        case .localNetwork: return "Local network"
        case .openSettings: return "Open Settings"
        case .unavailableProbes: return "Unavailable probes"
        case .privacyPolicy: return "Privacy policy"
        case .exportCSV: return "Export as CSV"
        case .exportJSON: return "Prepare JSON export"
        case .trimHistory: return "Trim old history now"
        case .resetNicknames: return "Reset nicknames"
        case .deleteHistory: return "Delete all history"
        case .version: return "Version"
        case .demoData: return "Use demo data"
        case .sourceCode: return "Source code"
        case .restoreDefaults: return "Restore Defaults"
        }
    }

    /// One glyph per concept: Ping is the round trip, Status the monitoring glyph, Export the share glyph of
    /// Overview's Export shortcut, Give up after a stopwatch (the hourglass means "stale").
    var systemImage: String {
        switch self {
        case .status: return "waveform.path.ecg"
        case .checkInterval: return "timer"
        case .icmp: return "arrow.left.arrow.right"
        case .udp: return "paperplane"
        case .pauseOffWiFi: return "wifi.slash"
        case .missesToOffline: return "xmark.circle"
        case .recoveryHits: return "checkmark.circle"
        case .giveUpAfter: return "stopwatch"
        case .accent: return "paintpalette"
        case .reduceEffects: return "circle.lefthalf.filled"
        case .haptics: return "hand.tap"
        case .localNetwork: return "network"
        case .openSettings: return "gear"
        case .unavailableProbes: return "exclamationmark.triangle"
        case .privacyPolicy: return "hand.raised"
        case .exportCSV: return "square.and.arrow.up"
        case .exportJSON: return "curlybraces"
        case .trimHistory: return "scissors"
        case .resetNicknames: return "textformat"
        case .deleteHistory: return "trash"
        case .version: return "info.circle"
        case .demoData: return "theatermasks"
        case .sourceCode: return "chevron.left.forwardslash.chevron.right"
        case .restoreDefaults: return "arrow.counterclockwise"
        }
    }

    /// The words people type for it beyond its title and page.
    var keywords: [String] {
        switch self {
        case .status: return ["monitor", "live", "paused", "running"]
        case .checkInterval: return ["interval", "frequency", "how often", "seconds", "minutes", "refresh"]
        case .icmp: return ["ping", "icmp", "echo", "probe"]
        case .udp: return ["udp", "probe", "datagram"]
        case .pauseOffWiFi: return ["wifi", "wi-fi", "cellular", "mobile data", "pause"]
        case .missesToOffline: return ["offline", "misses", "threshold", "false alarm"]
        case .recoveryHits: return ["online", "recover", "come back"]
        case .giveUpAfter: return ["timeout", "time out", "wait", "seconds", "probe"]
        case .accent: return ["color", "colour", "tint", "theme", "cobalt", "graphite"]
        case .reduceEffects: return ["motion", "animation", "effects", "glow"]
        case .haptics: return ["vibration", "feedback", "taps"]
        case .localNetwork: return ["permission", "access"]
        case .openSettings: return ["permission", "access"]
        case .unavailableProbes: return ["probes", "unsupported"]
        case .privacyPolicy: return ["policy"]
        case .exportCSV: return ["export", "csv", "spreadsheet", "share", "backup"]
        case .exportJSON: return ["export", "json", "share", "backup"]
        case .trimHistory: return ["history", "prune", "storage"]
        case .resetNicknames: return ["names", "rename"]
        case .deleteHistory: return ["history", "erase", "clear", "storage"]
        case .version: return ["build"]
        case .demoData: return ["demo", "sample", "example"]
        case .sourceCode: return ["github", "open source"]
        case .restoreDefaults: return ["reset", "defaults"]
        }
    }

    /// Every word of the query appears in the title, the page name or a keyword.
    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace })
        let fields = [title, pageTitle] + keywords
        return !words.isEmpty && words.allSatisfy { word in
            fields.contains { $0.localizedCaseInsensitiveContains(word) }
        }
    }
}

extension SettingsControl {
    /// Open Settings exists only while local network access is denied, Unavailable probes only when a probe
    /// failed to start.
    @MainActor
    func isAvailable(in environment: AppEnvironment) -> Bool {
        switch self {
        case .openSettings: return environment.permissionState == .denied
        case .unavailableProbes: return !environment.unsupportedProbes.isEmpty
        default: return true
        }
    }
}

/// A page behind a top-level row: its controls on one card, with the page's footer.
private struct SettingsPageView: View {
    let page: SettingsPage

    @Environment(AppEnvironment.self) private var environment

    init(page: SettingsPage) {
        self.page = page
    }

    private var controls: [SettingsControl] {
        SettingsControl.allCases.filter { $0.page == page && $0.isAvailable(in: environment) }
    }

    var body: some View {
        Form {
            if page == .networks {
                KnownNetworksSection()
            } else {
                Section {
                    ForEach(controls) { control in
                        SettingsControlRow(control)
                    }
                    .dsListRow()
                } footer: {
                    if let footer = page.footer {
                        SettingsFooter(footer)
                    }
                }
            }
        }
        .dsGroupedList()
        .dsFormColumn()
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One control, the same view on its page and in search results; in results the page name sits under its
/// title. Accessibility identifiers stay on the control in both places.
private struct SettingsControlRow: View {
    let control: SettingsControl
    let showsPage: Bool

    @Environment(AppEnvironment.self) private var environment

    private static let intervalTitles: [Double: String] = [
        15: "15 seconds",
        30: "30 seconds",
        60: "1 minute",
        120: "2 minutes",
        300: "5 minutes",
    ]
    private static let offeredTimeouts: [Double] = [1, 2.5, 5]

    init(_ control: SettingsControl, showsPage: Bool = false) {
        self.control = control
        self.showsPage = showsPage
    }

    private var subtitle: String? {
        showsPage ? control.pageTitle : nil
    }

    private func label(value: String? = nil) -> SettingsRowLabel {
        SettingsRowLabel(control.title, systemImage: control.systemImage, value: value, subtitle: subtitle)
    }

    private var actionLabel: SettingsActionLabel {
        SettingsActionLabel(control.title, systemImage: control.systemImage, subtitle: subtitle)
    }

    var body: some View {
        @Bindable var settings = environment.settings
        switch control {
        case .status:
            MonitoringStatusRow(label: label())
        case .checkInterval:
            Picker(selection: $settings.monitor.baseIntervalSeconds) {
                ForEach(Self.intervals(including: settings.monitor.baseIntervalSeconds), id: \.self) { seconds in
                    Text(Self.intervalTitle(seconds))
                        .tag(seconds)
                }
            } label: {
                label()
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("settings.checkInterval")
        case .icmp:
            Toggle(isOn: $settings.monitor.isICMPEnabled) {
                label()
            }
        case .udp:
            Toggle(isOn: $settings.monitor.isUDPEnabled) {
                label()
            }
        case .pauseOffWiFi:
            Toggle(isOn: $settings.monitor.pauseOnCellular) {
                label()
            }
        case .missesToOffline:
            Stepper(value: $settings.policy.missesToOffline, in: 1...8) {
                label(value: "\(settings.policy.missesToOffline)")
            }
            .accessibilityValue("\(settings.policy.missesToOffline)")
        case .recoveryHits:
            Stepper(value: $settings.policy.offlineRecoveryHits, in: 1...5) {
                label(value: "\(settings.policy.offlineRecoveryHits)")
            }
            .accessibilityValue("\(settings.policy.offlineRecoveryHits)")
        case .giveUpAfter:
            Picker(selection: $settings.monitor.probeTimeoutSeconds) {
                ForEach(Self.timeouts(including: settings.monitor.probeTimeoutSeconds), id: \.self) { seconds in
                    Text(String(format: "%g s", seconds))
                        .tag(seconds)
                }
            } label: {
                label()
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("settings.giveUpAfter")
        case .accent:
            AccentRow(label: label())
        case .reduceEffects:
            Toggle(isOn: $settings.reduceEffects) {
                label()
            }
        case .haptics:
            Toggle(isOn: $settings.hapticsEnabled) {
                label()
            }
            .accessibilityIdentifier("settings.haptics")
        case .localNetwork:
            label(value: permissionText)
                .accessibilityElement(children: .combine)
        case .openSettings:
            OpenSettingsButton(label: actionLabel)
        case .unavailableProbes:
            label(value: environment.unsupportedProbes.map(\.title).sorted().joined(separator: ", "))
                .accessibilityElement(children: .combine)
        case .privacyPolicy:
            if let url = URL(string: "https://github.com/antonsmedberg/DeviceMonitor/blob/main/Docs/PrivacyPolicy.md") {
                Link(destination: url) {
                    actionLabel
                }
            }
        case .exportCSV:
            ShareLink(item: csvFile, preview: SharePreview("DeviceMonitor.csv")) {
                actionLabel
            }
        case .exportJSON:
            JSONExportRows(label: actionLabel, subtitle: subtitle)
        case .trimHistory:
            Button {
                environment.pruneHistory()
            } label: {
                actionLabel
            }
        case .resetNicknames:
            ResetNicknamesButton(label: SettingsActionLabel(control.title, systemImage: control.systemImage, isDestructive: true, subtitle: subtitle))
        case .deleteHistory:
            DeleteHistoryButton(label: SettingsActionLabel(control.title, systemImage: control.systemImage, isDestructive: true, subtitle: subtitle))
        case .version:
            label(value: Self.versionText)
                .accessibilityElement(children: .combine)
        case .demoData:
            DemoDataToggle(label: label())
        case .sourceCode:
            if let url = URL(string: "https://github.com/antonsmedberg/DeviceMonitor") {
                Link(destination: url) {
                    actionLabel
                }
            }
        case .restoreDefaults:
            Button {
                environment.settings.resetToDefaults()
                environment.applySettings()
            } label: {
                actionLabel
            }
            .accessibilityIdentifier("settings.restoreDefaults")
        }
    }

    private var permissionText: String {
        switch environment.permissionState {
        case .undetermined: return "Not asked yet"
        case .likelyGranted: return "Allowed"
        case .denied: return "Denied"
        }
    }

    private var csvFile: ExportFile {
        ExportFile(data: Data(environment.exportCSV().utf8), contentType: .commaSeparatedText, filename: "DeviceMonitor.csv")
    }

    private static var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"
        return "\(version) (\(build))"
    }

    /// The offered intervals, plus a stored one that is not among them, so the menu never reads blank.
    private static func intervals(including current: Double) -> [Double] {
        Set(intervalTitles.keys).union([current]).sorted()
    }

    private static func intervalTitle(_ seconds: Double) -> String {
        intervalTitles[seconds] ?? "Every \(Int(seconds)) seconds"
    }

    /// The offered timeouts, plus a stored one that is not among them.
    private static func timeouts(including current: Double) -> [Double] {
        Set(offeredTimeouts).union([current]).sorted()
    }
}

// MARK: - Rows

/// The app's own row: the mark, the name and the facts; it opens About.
private struct SettingsHeaderRow: View {
    @Environment(AppEnvironment.self) private var environment

    /// Facts only: live or paused is said once, in the Status row.
    private var facts: String {
        var parts = [Formatters.count(environment.directory.devices.count, singular: "device", plural: "devices")]
        if let subnet = environment.currentSubnet {
            parts.append(subnet.description)
        }
        if environment.isDemo && !LaunchArguments.current.isScreenshots {
            parts.append("Demo data")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationLink {
            SettingsPageView(page: .about)
        } label: {
            HStack(spacing: DSLayout.space12) {
                // The mark's dot breathes while monitoring is live.
                PingMarkTile(size: 32, isLive: environment.monitorStatus(now: Date()).isLive)
                VStack(alignment: .leading, spacing: DSLayout.space2) {
                    Text("DeviceMonitor")
                        .font(DSTypography.headerName)
                        .foregroundStyle(DSColor.textPrimary)
                    Text(facts)
                        .font(DSTypography.rowSubtitle)
                        .monospacedDigit()
                        .foregroundStyle(DSColor.textSecondary)
                }
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            }
            // With the row's insets the header is at least 60 pt: a card row, never a capsule.
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("settings.header")
    }
}

/// Whether monitoring runs, said once in Settings; "Local network access is off" in the bad ink.
private struct MonitoringStatusRow: View {
    let label: SettingsRowLabel

    @Environment(AppEnvironment.self) private var environment

    init(label: SettingsRowLabel) {
        self.label = label
    }

    var body: some View {
        let now = Date()
        let isDenied = environment.permissionState == .denied
        HStack(spacing: DSLayout.space8) {
            label
            Spacer(minLength: DSLayout.space8)
            Text(isDenied ? "Local network access is off" : environment.monitorStatus(now: now).headline(now: now))
                .font(DSTypography.body)
                .foregroundStyle(isDenied ? DSColor.offline : DSColor.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.status")
    }
}

/// The accent swatches under their row title.
private struct AccentRow: View {
    let label: SettingsRowLabel

    @Environment(AppEnvironment.self) private var environment
    @ScaledMetric(relativeTo: .title3) private var iconColumn: CGFloat = 28

    init(label: SettingsRowLabel) {
        self.label = label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSLayout.space12) {
            label
            HStack(spacing: DSLayout.space16) {
                ForEach(AccentChoice.allCases, id: \.self) { choice in
                    AccentSwatch(choice: choice, isSelected: environment.settings.accent == choice) {
                        environment.settings.accent = choice
                        environment.haptics.selection()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, iconColumn + DSLayout.space12)
        }
        .padding(.vertical, DSLayout.space4)
    }
}

/// A 32 pt swatch of the choice's button fill with its name under it; the selected one is ringed in the tint
/// and its name is semibold.
private struct AccentSwatch: View {
    let choice: AccentChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DSLayout.space4) {
                Circle()
                    .fill(DSColor.accentFill(for: choice))
                    .frame(width: 32, height: 32)
                    .padding(3)
                    .overlay {
                        if isSelected {
                            Circle().strokeBorder(.tint, lineWidth: 2)
                        }
                    }
                Text(choice.title)
                    .font(isSelected ? DSTypography.tileLabel.weight(.semibold) : DSTypography.tileLabel)
                    .foregroundStyle(isSelected ? DSColor.textPrimary : DSColor.textSecondary)
            }
            .frame(minWidth: DSLayout.minTapTarget, minHeight: DSLayout.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Opens the app's page in the Settings app, where local network access is turned back on.
private struct OpenSettingsButton: View {
    let label: SettingsActionLabel

    @Environment(\.openURL) private var openURL

    init(label: SettingsActionLabel) {
        self.label = label
    }

    var body: some View {
        Button {
            if let url = LocalNetworkPermission.settingsURL() {
                openURL(url)
            }
        } label: {
            label
        }
    }
}

/// Prepare writes the JSON file; Share appears once it exists, an error in its place when it fails.
private struct JSONExportRows: View {
    let label: SettingsActionLabel
    let subtitle: String?

    @Environment(AppEnvironment.self) private var environment
    @State private var exportJSON: ExportFile?
    @State private var exportError: String?

    init(label: SettingsActionLabel, subtitle: String?) {
        self.label = label
        self.subtitle = subtitle
    }

    var body: some View {
        Button {
            prepareJSON()
        } label: {
            label
        }
        if let exportJSON {
            ShareLink(item: exportJSON, preview: SharePreview("DeviceMonitor.json")) {
                SettingsActionLabel("Share JSON export", systemImage: "square.and.arrow.up", subtitle: subtitle)
            }
        }
        if let exportError {
            Text(exportError)
                .font(DSTypography.rowSubtitle)
                .foregroundStyle(DSColor.offline)
        }
    }

    private func prepareJSON() {
        do {
            let data = try environment.exportJSON()
            exportJSON = ExportFile(data: data, contentType: .json, filename: "DeviceMonitor.json")
            exportError = nil
        } catch {
            exportError = error.errorDescription
        }
    }
}

private struct ResetNicknamesButton: View {
    let label: SettingsActionLabel

    @Environment(AppEnvironment.self) private var environment
    @State private var isConfirming = false

    init(label: SettingsActionLabel) {
        self.label = label
    }

    var body: some View {
        Button(role: .destructive) {
            isConfirming = true
        } label: {
            label
        }
        .confirmationDialog("Reset all nicknames?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                environment.resetNicknames()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct DeleteHistoryButton: View {
    let label: SettingsActionLabel

    @Environment(AppEnvironment.self) private var environment
    @State private var isConfirming = false

    init(label: SettingsActionLabel) {
        self.label = label
    }

    var body: some View {
        Button(role: .destructive) {
            isConfirming = true
        } label: {
            label
        }
        .confirmationDialog("Delete all history?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                environment.deleteAllHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Status changes and latency samples for every device are removed. Devices, nicknames and notes stay.")
        }
    }
}

/// Takes effect on the next launch, so it is stored for launch rather than in the running settings.
private struct DemoDataToggle: View {
    let label: SettingsRowLabel

    @State private var useDemoData = SettingsStore.usesDemoDataOnLaunch

    init(label: SettingsRowLabel) {
        self.label = label
    }

    var body: some View {
        Toggle(isOn: $useDemoData) {
            label
        }
        .onChange(of: useDemoData) { _, value in
            SettingsStore.usesDemoDataOnLaunch = value
        }
    }
}

/// Every network the app has monitored, so moving between home and office is visible.
private struct KnownNetworksSection: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let networks = environment.knownNetworks()
        let now = Date()
        Section {
            if networks.isEmpty {
                Text("No networks yet. Each Wi‑Fi network DeviceMonitor monitors appears here.")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .dsListRow()
            } else {
                ForEach(networks, id: \.key) { network in
                    SettingsRowLabel(
                        network.displayName,
                        systemImage: "wifi",
                        value: Formatters.relative(network.lastSeen, now: now),
                        subtitle: network.key == environment.currentNetworkKey ? "Current network" : nil
                    )
                    .accessibilityElement(children: .combine)
                }
                .dsListRow()
            }
        }
    }
}

// MARK: - Labels

/// A control's label: `DSSettingsLabel`, with a grey line under the title in search results (the page) and in
/// the network list ("Current network").
private struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    let value: String?
    let subtitle: String?

    @ScaledMetric(relativeTo: .title3) private var iconColumn: CGFloat = 28

    init(_ title: String, systemImage: String, value: String? = nil, subtitle: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.subtitle = subtitle
    }

    var body: some View {
        if let subtitle {
            VStack(alignment: .leading, spacing: DSLayout.space2) {
                DSSettingsLabel(title, systemImage: systemImage, value: value)
                Text(subtitle)
                    .font(DSTypography.rowSubtitle)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.leading, iconColumn + DSLayout.space12)
            }
        } else {
            DSSettingsLabel(title, systemImage: systemImage, value: value)
        }
    }
}

/// The label of a row that does something (export, open, restore): the line icon and the title in the tint,
/// or in the bad ink when it destroys data. The colour is set here, so a button role or a link cannot change it.
private struct SettingsActionLabel: View {
    let title: String
    let systemImage: String
    let isDestructive: Bool
    let subtitle: String?

    @ScaledMetric(relativeTo: .title3) private var iconColumn: CGFloat = 28

    init(_ title: String, systemImage: String, isDestructive: Bool = false, subtitle: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.subtitle = subtitle
    }

    var body: some View {
        if isDestructive {
            content
                .foregroundStyle(DSColor.offline)
        } else {
            content
                .foregroundStyle(.tint)
        }
    }

    private var content: some View {
        HStack(spacing: DSLayout.space12) {
            Image(systemName: systemImage)
                .font(.title3)
                .environment(\.symbolVariants, SymbolVariants.none)
                .frame(width: iconColumn)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DSLayout.space2) {
                Text(title)
                    .font(DSTypography.rowTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(DSTypography.rowSubtitle)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
    }
}

private struct SettingsFooter: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(DSTypography.rowSubtitle)
            .foregroundStyle(DSColor.textSecondary)
    }
}

#Preview("Settings") {
    SettingsView()
        .environment(AppEnvironment.demo())
}
