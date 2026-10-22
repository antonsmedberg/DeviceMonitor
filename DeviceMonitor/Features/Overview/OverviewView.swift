import SwiftUI
import UniformTypeIdentifiers

/// The network at a glance, in the order a person asks: is it OK, what needs me, how fast is the router, was
/// the network down, where does it sit on an absolute range, then Check All Now and the shortcuts. Sections sit
/// on the page, separated by whitespace; only the attention rows sit on a card. Two columns on wide screens.
struct OverviewView: View {
    /// Shared with the root, so the Scan and Add Device sheets zoom out of this screen's controls.
    let sheetNamespace: Namespace.ID?

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @Namespace private var ownNamespace
    @State private var model = OverviewModel()
    /// The last reload, moved on every 15 s so the capsule can say "stale" when rounds stop arriving.
    @State private var now = Date()
    @State private var columns: LayoutColumns = .one
    @State private var width: CGFloat = 0
    /// The moment under the finger on the latency chart; its values replace the summary while it is set.
    @State private var selectedDate: Date?
    @State private var showsRangeInfo = false

    /// Without a shared namespace, as in previews, the view uses its own.
    init(sheetNamespace: Namespace.ID? = nil) {
        self.sheetNamespace = sheetNamespace
    }

    private var namespace: Namespace.ID {
        sheetNamespace ?? ownNamespace
    }

    /// Everything the model reads, so a round, a history change, a device edit or a new network reloads once.
    private var reloadKey: OverviewReloadKey {
        OverviewReloadKey(
            lastRoundAt: environment.directory.lastRoundAt,
            historyRevision: environment.directory.historyRevision,
            devices: environment.directory.devices,
            networkKey: environment.currentNetworkKey
        )
    }

    var body: some View {
        let status = environment.monitorStatus(now: now)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSLayout.sectionGap) {
                    banners
                    if environment.directory.devices.isEmpty {
                        emptyState
                    } else {
                        sections
                    }
                }
                .dsContainerMargins()
                .padding(.top, DSLayout.space8)
                .padding(.bottom, DSLayout.space32)
            }
            .accessibilityIdentifier("screen.overview")
            .readLayoutColumns($columns, cardMinimum: 420)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
            .background {
                DSColor.background
                    .ignoresSafeArea()
            }
            .navigationTitle("Overview")
            .navigationBarTitleDisplayMode(.inline)
            // The network capsule takes the title's place.
            .toolbar(removing: .title)
            .toolbar {
                toolbarContent(status: status)
            }
            .refreshable {
                environment.checkAllNow()
                try? await Task.sleep(for: .milliseconds(600))
            }
            .task(id: reloadKey) {
                now = Date()
                model.reload(environment: environment, now: now)
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    now = Date()
                }
            }
        }
    }

    /// One column: every section in reading order. Two: the gateway line across, then the network over time
    /// (Latency, Availability) on the left and the devices now with what to do about them on the right, so the
    /// columns end at about the same height. Top-aligned from one leading edge.
    @ViewBuilder
    private var sections: some View {
        if columns == .one {
            gatewayLine
            attentionSection
            latencySection
            availabilitySection
            latencyRangeSection
            checkAllButton
            shortcutsSection
        } else {
            gatewayLine
            HStack(alignment: .top, spacing: DSLayout.space24) {
                VStack(alignment: .leading, spacing: DSLayout.sectionGap) {
                    latencySection
                    availabilitySection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: DSLayout.sectionGap) {
                    attentionSection
                    latencyRangeSection
                    checkAllButton
                    shortcutsSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Toolbar

    /// The network capsule on the leading side and one Scan circle on the trailing side. Toolbar glyphs are
    /// monochrome; only the capsule's status disc carries colour.
    @ToolbarContentBuilder
    private func toolbarContent(status: MonitorStatus) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            networkMenu(status: status)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                environment.router.present(.scan)
            } label: {
                Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                    .symbolEffect(
                        .variableColor.cumulative.dimInactiveLayers.reversing,
                        options: .repeat(.continuous),
                        isActive: environment.isScanning && !LaunchArguments.current.isScreenshots
                    )
            }
            .tint(DSColor.textPrimary)
            .accessibilityHint("Finds devices on your Wi‑Fi network")
            .accessibilityIdentifier("overview.scan")
        }
        .matchedTransitionSource(id: "scan.overview", in: namespace)
    }

    /// Facts about the network first, then what to do with it. Scan and Check All Now are not here: each
    /// already has a control on this screen.
    private func networkMenu(status: MonitorStatus) -> some View {
        Menu {
            Section {
                Text(networkFacts)
                Text("\(status.headline(now: now)) · every \(Formatters.duration(environment.settings.monitor.baseIntervalSeconds))")
            }
            .disabled(true)
            Button {
                environment.togglePause()
            } label: {
                Label(environment.isPausedByUser ? "Resume Monitoring" : "Pause Monitoring", systemImage: environment.isPausedByUser ? "play" : "pause")
            }
            Button {
                environment.router.present(.addDevice)
            } label: {
                Label("Add Device…", systemImage: "plus")
            }
        } label: {
            DSNetworkCapsuleLabel(title: networkTitle, status: status)
        }
        .accessibilityIdentifier("overview.network")
    }

    /// "Home", else the subnet, else "No network".
    private var networkTitle: String {
        model.networkName ?? environment.currentSubnet?.description ?? "No network"
    }

    /// "192.168.178.0/24 · gateway 192.168.178.1".
    private var networkFacts: String {
        let facts = [environment.currentSubnet?.description, model.gateway.map { "gateway \($0.host)" }].compactMap { $0 }
        return facts.isEmpty ? "No network" : facts.joined(separator: " · ")
    }

    // MARK: - Banners and the empty network

    @ViewBuilder
    private var banners: some View {
        if environment.permissionState == .denied {
            LocalNetworkDeniedBanner()
        } else if !environment.pathStatus.isWiFi && !environment.isDemo {
            InfoBanner(
                title: environment.pathStatus.isSatisfied ? "Not on Wi‑Fi" : "No network",
                message: "Join the Wi‑Fi network your devices are on. Monitoring resumes automatically.",
                systemImage: "wifi.slash",
                tint: DSColor.degraded
            )
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            title: "No devices yet",
            message: "Scan to find routers, printers, speakers and everything else on your Wi‑Fi.",
            systemImage: "dot.radiowaves.left.and.right",
            actionTitle: "Scan"
        ) {
            environment.router.present(.scan)
        }
        .padding(.top, DSLayout.space32)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.empty")
    }

    // MARK: - Gateway line

    /// The router's name and address with the counters on the same first line. When both do not fit on one
    /// line, the name sits over the address; at accessibility sizes the counters wrap under the name.
    private var gatewayLine: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DSLayout.space8) {
                    gatewayName(isStacked: true)
                    counterRow
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: DSLayout.space12) {
                    ViewThatFits(in: .horizontal) {
                        gatewayName(isStacked: false)
                        gatewayName(isStacked: true)
                    }
                    // A flexible frame, not a Spacer, so the name gets all the width the counters leave.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    counterRow
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: DSLayout.minTapTarget, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.header")
    }

    /// "Fritz!Box 7590 192.168.178.1", or the name over the address. Without a router: the subnet and
    /// "No router found".
    private func gatewayName(isStacked: Bool) -> some View {
        let name = model.gateway?.displayName ?? environment.currentSubnet?.description ?? "No network"
        let detail = model.gateway?.host ?? "No router found"
        return Group {
            if isStacked {
                VStack(alignment: .leading, spacing: DSLayout.space2) {
                    Text(name)
                        .font(DSTypography.headerName)
                        .foregroundStyle(DSColor.textPrimary)
                    Text(detail)
                        .font(DSTypography.rowSubtitle)
                        .foregroundStyle(DSColor.textSecondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name)
                        .font(DSTypography.headerName)
                        .foregroundStyle(DSColor.textPrimary)
                    Text(detail)
                        .font(DSTypography.body)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        .accessibilityElement(children: .combine)
    }

    /// Online (online and unstable), Offline, New and Strangers; each count equals the Devices filter it
    /// opens. New and Strangers hide at zero.
    private var counterRow: some View {
        let counts = model.counters
        var counters = [
            DSCounter(id: "online", systemImage: "checkmark.circle", count: counts.online, accessibilityLabel: "\(counts.online) online"),
            DSCounter(id: "offline", systemImage: "xmark.circle", count: counts.offline, tone: .bad, accessibilityLabel: "\(counts.offline) offline"),
        ]
        if counts.recentArrivals > 0 {
            counters.append(DSCounter(id: "new", systemImage: "sparkle", count: counts.recentArrivals, accessibilityLabel: "\(counts.recentArrivals) new"))
        }
        if counts.strangers > 0 {
            counters.append(DSCounter(
                id: "strangers",
                systemImage: "person.crop.circle.badge.questionmark",
                count: counts.strangers,
                accessibilityLabel: Formatters.count(counts.strangers, singular: "stranger", plural: "strangers")
            ))
        }
        // The counter ids are the filters' raw values.
        return DSCounterRow(counters, identifierPrefix: "overview.counter") { id in
            if let filter = DashboardModel.Filter(rawValue: id) {
                environment.router.showDevices(filter: filter)
            }
        }
        .fixedSize()
    }

    // MARK: - Needs attention

    /// The same devices and count as the Devices section of the same name; the title's spoken value is the
    /// sentence the rows below show.
    @ViewBuilder
    private var attentionSection: some View {
        if !model.attention.isEmpty {
            let allOffline = model.attention.allSatisfy { $0.state == .offline }
            VStack(alignment: .leading, spacing: 10) {
                DSTitleRow("Needs attention", qualifier: "(\(model.attention.count))", accessibilityValue: model.attentionSentence) {
                    DSLink("See All", accessibilityLabel: "See all devices that need attention") {
                        environment.router.showDevices(filter: allOffline ? .offline : .all)
                    }
                    .accessibilityIdentifier("overview.attention.seeAll")
                }
                VStack(spacing: 0) {
                    ForEach(Array(model.attention.prefix(OverviewModel.attentionLimit).enumerated()), id: \.element.id) { index, device in
                        if index > 0 {
                            Rectangle()
                                .fill(DSColor.hairline)
                                .frame(height: 1 / displayScale)
                                .padding(.leading, rowTextInset)
                        }
                        Button {
                            environment.router.showDevice(device.id)
                        } label: {
                            DeviceRowView(device: device, samples: model.attentionSamples[device.id] ?? [], now: now)
                                .padding(DeviceRowView.listRowInsets)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the device")
                        .accessibilityIdentifier("overviewRow.\(device.host)")
                    }
                }
                .dsCard(padding: 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("overview.attention")
        }
    }

    /// Where a row's text starts (inset, thumbnail, gap): the dividers start there, as list separators do.
    private var rowTextInset: CGFloat {
        DeviceRowView.listRowInsets.leading + DSLayout.thumbnailRow + DSLayout.space12
    }

    // MARK: - Latency

    /// The router's last hour: its latency word, median, jitter and p95, and the chart. Without a router or
    /// with fewer than two samples, one line says when it appears.
    private var latencySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSTitleRow("Latency", qualifier: "Router · 1H", status: model.routerQuality.map { DSStatusWord($0.title, tone: $0.tone) }) {
                if let gateway = model.gateway {
                    DSLink("See All", accessibilityLabel: "See all router latency") {
                        environment.router.showDevice(gateway.id)
                    }
                    .accessibilityIdentifier("overview.latency.seeAll")
                }
            }
            if let series = model.routerLatency, let summary = series.summary, summary.count >= 2 {
                let line = summaryLine(series: series, summary: summary)
                DSSummaryLine(line.items, trailing: line.trailing)
                    .padding(.top, DSLayout.space12)
                DSAreaChart(
                    series: [series.latency, series.jitter],
                    domain: series.domain,
                    upperBound: series.upperBound,
                    unit: "ms",
                    xLabels: ChartAxis.labels(domain: series.domain, style: series.window.axisStyle),
                    height: width >= 600 ? DSLayout.chartHeightRegular : DSLayout.chartHeightOverview,
                    selection: $selectedDate,
                    accessibilityLabel: "Router latency, last hour",
                    accessibilityValue: "Median \(Self.spoken(summary.median)), jitter \(Self.spoken(summary.jitter)), p95 \(Self.spoken(summary.p95))"
                )
                .padding(.top, DSLayout.space16)
            } else {
                Text("Latency appears after a few checks of the router.")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                    .padding(.top, DSLayout.space12)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.latency")
    }

    /// Median, jitter and p95 over the hour; while the finger is on the chart, the values at that moment.
    private func summaryLine(series: LatencySeries, summary: LatencySummary) -> (items: [DSSummaryItem], trailing: DSSummaryItem) {
        if let selectedDate, let point = Self.nearestPoint(in: series.latency, to: selectedDate), let latency = point.value {
            let jitter = series.jitter.points.first { $0.date == point.date }?.value
            return (
                [
                    DSSummaryItem(id: "latency", label: "Latency", value: Formatters.latency(latency), tone: .latency, spokenValue: Self.spoken(latency)),
                    DSSummaryItem(id: "jitter", label: "Jitter", value: Formatters.latency(jitter), tone: .jitter, spokenValue: Self.spoken(jitter)),
                ],
                DSSummaryItem(id: "time", label: "At", value: point.date.formatted(date: .omitted, time: .shortened))
            )
        }
        return (
            [
                DSSummaryItem(id: "latency", label: "Latency", value: Formatters.latency(summary.median), tone: .latency, spokenValue: Self.spoken(summary.median)),
                DSSummaryItem(id: "jitter", label: "Jitter", value: Formatters.latency(summary.jitter), tone: .jitter, spokenValue: Self.spoken(summary.jitter)),
            ],
            DSSummaryItem(id: "p95", label: "p95", value: Formatters.latency(summary.p95), spokenValue: Self.spoken(summary.p95))
        )
    }

    /// The measured point nearest to `date`, the one the chart marks.
    private static func nearestPoint(in series: DSChartSeries, to date: Date) -> DSChartPoint? {
        series.points
            .filter { $0.value != nil }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// "1.8 milliseconds", "1.2 seconds", or "no reading".
    private static func spoken(_ milliseconds: Double?) -> String {
        let text = Formatters.latency(milliseconds)
        if text.hasSuffix(" ms") { return String(text.dropLast(3)) + " milliseconds" }
        if text.hasSuffix(" s") { return String(text.dropLast(2)) + " seconds" }
        return "no reading"
    }

    // MARK: - Availability

    /// Outages seen and time down over the network's last 24 hours, never a percentage: the app only sees
    /// what happens while it is open, and the strip says so under its bars.
    private var availabilitySection: some View {
        let summary = AvailabilityNarrative.summary(cells: model.availability)
        return VStack(alignment: .leading, spacing: 0) {
            DSTitleRow(
                "Availability",
                qualifier: "24H",
                status: AvailabilityNarrative.statusWord(cells: model.availability, isGatewayDown: model.gateway?.state == .offline)
            ) {
                DSLink("See All", accessibilityLabel: "See all outages") {
                    environment.router.showActivity(filter: .outages)
                }
                .accessibilityIdentifier("overview.availability.seeAll")
            }
            DSSummaryLine(summary.items, trailing: summary.trailing)
                .padding(.top, DSLayout.space12)
            UptimeStripView(
                title: "Network, last 24 hours",
                cells: model.availability,
                leadingCaption: "24h ago",
                trailingCaption: "Now",
                isInteractive: true
            )
            .padding(.top, DSLayout.space12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.availability")
    }

    // MARK: - Latency range

    /// Where the network's median sits on an absolute range, with every answering device as a tick. No status
    /// word: the grades would be a second latency vocabulary beside the Latency title's, so they live in the ⓘ.
    @ViewBuilder
    private var latencyRangeSection: some View {
        if !model.latencies.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                DSTitleRow("Latency range", qualifier: "All devices") {
                    rangeInfoButton
                }
                DSGradientScale(
                    scale: .latency,
                    value: model.medianLatency,
                    marks: model.latencies,
                    markerSymbol: "wifi.router.fill",
                    accessibilityLabel: "Latency range, all devices",
                    accessibilityValue: "Median \(Self.spoken(model.medianLatency))"
                )
                .padding(.top, DSLayout.space16)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("overview.latencyRange")
        }
    }

    /// A 44 pt hit area that does not make the 20 pt title row taller.
    private var rangeInfoButton: some View {
        Button {
            showsRangeInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(DSTypography.body)
                .foregroundStyle(.tint)
                .frame(minWidth: DSLayout.minTapTarget, minHeight: DSLayout.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About latency range")
        .accessibilityIdentifier("overview.latencyRange.info")
        .popover(isPresented: $showsRangeInfo) {
            rangeInfo
                .presentationCompactAdaptation(.popover)
        }
        .padding(.vertical, -12)
    }

    /// The only place the absolute grades appear.
    private var rangeInfo: some View {
        VStack(alignment: .leading, spacing: DSLayout.space12) {
            Text("Where your devices' median latency sits on an absolute scale.")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textPrimary)
            ForEach(LatencyGrade.allCases, id: \.self) { grade in
                VStack(alignment: .leading, spacing: DSLayout.space2) {
                    Text(grade.title)
                        .font(DSTypography.body.weight(.semibold))
                        .foregroundStyle(DSColor.ink(grade.tone))
                    Text(grade.explanation)
                        .font(DSTypography.rowSubtitle)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            Text("The words in the Latency title compare each device with its own usual latency.")
                .font(DSTypography.rowSubtitle)
                .foregroundStyle(DSColor.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(DSLayout.space16)
        .frame(width: 300, alignment: .leading)
    }

    // MARK: - Actions

    private var checkAllButton: some View {
        DSTextButton("Check All Now", systemImage: "arrow.clockwise", surface: .page) {
            checkAll()
        }
        .accessibilityIdentifier("overview.checkAll")
    }

    /// Checks every device now, with a success tap and a spoken confirmation. While monitoring is paused
    /// nothing is checked, and the feedback says so instead.
    private func checkAll() {
        let announcement: String
        if environment.isPausedByUser {
            environment.haptics.warning()
            announcement = "Monitoring is paused"
        } else {
            environment.checkAllNow()
            environment.haptics.success()
            announcement = "Checking all devices"
        }
        AccessibilityNotification.Announcement(announcement).post()
    }

    /// Five ways off this screen, each to somewhere real. Scan has no tile: the toolbar Scan is right above.
    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSTitleRow("Shortcuts")
            DSTileGrid(columns: dynamicTypeSize.isAccessibilitySize ? 3 : 5, spacing: 7) {
                Button {
                    environment.router.showActivity(filter: .outages)
                } label: {
                    DSTileLabel("Outages", systemImage: "wifi.exclamationmark", style: .filled)
                }
                .buttonStyle(DSTileButtonStyle())
                .accessibilityHint("Shows network outages in Activity")
                .accessibilityIdentifier("overview.shortcut.outages")
                Button {
                    environment.router.present(.addDevice)
                } label: {
                    DSTileLabel("Add", systemImage: "plus.circle", style: .filled)
                }
                .buttonStyle(DSTileButtonStyle())
                .matchedTransitionSource(id: "add.overview", in: namespace)
                .accessibilityHint("Adds a device by its address")
                .accessibilityIdentifier("overview.shortcut.add")
                Button {
                    environment.router.showInsights(.map)
                } label: {
                    DSTileLabel("Map", systemImage: "point.3.connected.trianglepath.dotted", style: .filled)
                }
                .buttonStyle(DSTileButtonStyle())
                .accessibilityHint("Opens the network map in Insights")
                .accessibilityIdentifier("overview.shortcut.map")
                Button {
                    environment.router.showInsights(.presence)
                } label: {
                    DSTileLabel("Presence", systemImage: "person.2", style: .filled)
                }
                .buttonStyle(DSTileButtonStyle())
                .accessibilityHint("Opens presence in Insights")
                .accessibilityIdentifier("overview.shortcut.presence")
                ShareLink(item: csvFile, preview: SharePreview("DeviceMonitor.csv")) {
                    DSTileLabel("Export", systemImage: "square.and.arrow.up", style: .filled)
                }
                .buttonStyle(DSTileButtonStyle())
                .accessibilityHint("Shares your devices as a CSV file")
                .accessibilityIdentifier("overview.shortcut.export")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.shortcuts")
    }

    private var csvFile: ExportFile {
        ExportFile(data: Data(environment.exportCSV().utf8), contentType: .commaSeparatedText, filename: "DeviceMonitor.csv")
    }
}

/// What Overview's data depends on; one change of any part reloads the model once.
private nonisolated struct OverviewReloadKey: Hashable {
    let lastRoundAt: Date?
    let historyRevision: Int
    let devices: [DeviceSnapshot]
    let networkKey: String?
}

#Preview("Overview") {
    OverviewView()
        .environment(AppEnvironment.demo())
}
