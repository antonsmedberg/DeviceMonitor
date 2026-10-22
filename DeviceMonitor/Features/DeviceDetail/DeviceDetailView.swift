import SwiftUI
import UIKit

/// Device detail: a header on the page, the info card with the device's actions, then latency, availability,
/// open services and the rest as cards. One column, at most 680 pt wide; where two 420 pt columns fit, the
/// header spans both and the cards keep a fixed order in each.
struct DeviceDetailView: View {
    let deviceID: UUID
    let sheetNamespace: Namespace.ID?

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Namespace private var ownNamespace
    @State private var model: DeviceDetailModel?
    @State private var pulseTrigger = 0
    @State private var now = Date()
    @State private var unopenedLink: String?
    @State private var columns: LayoutColumns = .one
    /// The detail column's width: Edit opens the inspector from 700 pt.
    @State private var width: CGFloat = 0
    @State private var isEditing = false
    @State private var isConfirmingRemoval = false

    init(deviceID: UUID, sheetNamespace: Namespace.ID? = nil) {
        self.deviceID = deviceID
        self.sheetNamespace = sheetNamespace
    }

    private var device: DeviceSnapshot? { environment.directory.device(id: deviceID) }

    /// Whether monitoring is live, for the breathing dot of an online device's state.
    private var isLive: Bool {
        MonitorStatus.make(
            isScanning: environment.isScanning,
            scanProgress: environment.scanProgress,
            isPausedByUser: environment.isPausedByUser,
            pauseReason: environment.pauseReason,
            isOnWiFi: environment.pathStatus.isWiFi,
            isDemo: environment.isDemo,
            hasDevices: !environment.directory.devices.isEmpty,
            lastRoundAt: environment.directory.lastRoundAt,
            intervalSeconds: environment.settings.monitor.baseIntervalSeconds,
            now: now
        ).isLive
    }

    var body: some View {
        Group {
            if let device, let model {
                content(device: device, model: model)
            } else if device == nil {
                EmptyStateView(title: "Device removed", message: "This device is no longer in your list.", systemImage: "trash")
            } else {
                ProgressView()
            }
        }
        .task(id: deviceID) {
            let detail = DeviceDetailModel(deviceID: deviceID)
            detail.load(from: environment)
            model = detail
            if let device {
                await detail.loadInsight(environment: environment, snapshot: device)
            }
        }
        .onChange(of: device?.state) { old, new in
            guard old != nil, old != new else { return }
            pulseTrigger += 1
        }
        // A state change arrives before its event is stored, so the history reloads on the revision instead.
        .onChange(of: environment.directory.historyRevision) { _, _ in
            model?.load(from: environment)
        }
        .onChange(of: environment.directory.lastRoundAt) { _, _ in
            now = Date()
            model?.load(from: environment, now: now)
        }
        .alert(
            "No app can open this link",
            isPresented: Binding(get: { unopenedLink != nil }, set: { if !$0 { unopenedLink = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Install \(unopenedLink ?? "an app") to open this device directly.")
        }
    }

    private func content(device: DeviceSnapshot, model: DeviceDetailModel) -> some View {
        let samples = model.latency.map(\.milliseconds)
        let quality = device.state.isUp ? LatencyQuality.assess(latest: device.latencyMilliseconds, samples: samples) : nil

        return ScrollView {
            VStack(alignment: .leading, spacing: DSLayout.cardGap) {
                DetailHeader(device: device, quality: quality, isLive: isLive, pulseTrigger: pulseTrigger, now: now)
                if columns == .one {
                    infoCard(device: device, model: model, samples: samples)
                    pingCard(model: model)
                    latencyCard(device: device, model: model, quality: quality)
                    AvailabilityCard(device: device, events: model.events, now: now)
                    servicesCard(device: device, model: model)
                    aboutCard(model: model)
                    logCard(device: device, model: model)
                    DeviceDetailsCard(device: device, now: now)
                    notesCard(device: device)
                } else {
                    HStack(alignment: .top, spacing: DSLayout.cardGap) {
                        VStack(alignment: .leading, spacing: DSLayout.cardGap) {
                            infoCard(device: device, model: model, samples: samples)
                            latencyCard(device: device, model: model, quality: quality)
                            AvailabilityCard(device: device, events: model.events, now: now)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        VStack(alignment: .leading, spacing: DSLayout.cardGap) {
                            pingCard(model: model)
                            servicesCard(device: device, model: model)
                            aboutCard(model: model)
                            logCard(device: device, model: model)
                            DeviceDetailsCard(device: device, now: now)
                            notesCard(device: device)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
            .frame(maxWidth: columns == .one ? 680 : nil, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsContainerMargins()
            .padding(.top, DSLayout.space8)
            .padding(.bottom, DSLayout.space32)
        }
        .accessibilityIdentifier("screen.detail")
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
        .navigationTitle(device.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarContent(device: device)
        }
        .inspector(isPresented: $isEditing) {
            // Built only while open: a closed inspector's content still reaches the detail's navigation bar.
            // The editor's own header carries its title, Cancel and Save, so it needs no stack or toolbar.
            if isEditing {
                EditDeviceView(deviceID: device.id, presentation: .inspector)
                    .inspectorColumnWidth(min: 300, ideal: 320, max: 360)
                    .environment(\.dismissEditInspector, { isEditing = false })
            }
        }
        .confirmationDialog("Remove \(device.displayName)?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                environment.remove(deviceIDs: [device.id])
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its history will be deleted. It will reappear if a scan finds it again.")
        }
    }

    /// Favorite as a star and everything else in More; the two items share one glass background. More is the
    /// source the Edit sheet zooms out of.
    @ToolbarContentBuilder
    private func toolbarContent(device: DeviceSnapshot) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                environment.toggleFavorite(device.id)
            } label: {
                Label(device.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: device.isFavorite ? "star.fill" : "star")
            }
            .contentTransition(.symbolEffect(.replace))
            .tint(Color.primary)
            .accessibilityValue(device.isFavorite ? "On" : "Off")
            .accessibilityIdentifier("detail.favorite")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    edit(device)
                } label: {
                    Label("Edit…", systemImage: "pencil")
                }
                .accessibilityIdentifier("detail.edit")
                Button {
                    UIPasteboard.general.string = device.host
                } label: {
                    Label("Copy Address", systemImage: "document.on.document")
                }
                ShareLink(item: shareText(for: device)) {
                    Label("Share Details", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(role: .destructive) {
                    isConfirmingRemoval = true
                } label: {
                    Label("Remove…", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .tint(Color.primary)
            .accessibilityIdentifier("detail.more")
        }
        .matchedTransitionSource(id: "edit", in: sheetNamespace ?? ownNamespace)
    }

    /// The inspector beside a regular-width detail column of 700 pt or more. Otherwise the zoomed form sheet:
    /// a 360 pt inspector would crowd the cards, and in a compact width (an iPhone in landscape) it would
    /// become a plain sheet that does not zoom from More.
    private func edit(_ device: DeviceSnapshot) {
        if isEditing || (sizeClass == .regular && width >= 700) {
            isEditing.toggle()
        } else {
            environment.router.present(.editDevice(device.id))
        }
    }

    // MARK: - Cards

    /// The four-row info grid, then every action on the device as tiles. The card's bottom padding is 12, not 16.
    private func infoCard(device: DeviceSnapshot, model: DeviceDetailModel, samples: [Double]) -> some View {
        let daily = UptimeCells.days(count: 30, events: model.events, currentState: device.state, firstSeen: device.firstSeen, now: now)
        let outagesSeen: Int? = daily.contains { $0.state != .noData } ? AvailabilityNarrative.outagesSeen(daily) : nil
        let openPortCount: Int? = model.ports.isEmpty ? nil : model.ports.filter(\.isOpen).count

        return VStack(alignment: .leading, spacing: DSLayout.space12) {
            DSInfoGrid(rows: DeviceInfoGrid.rows(device: device, samples: samples, outagesSeen: outagesSeen, openPortCount: openPortCount, now: now))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("detail.infoGrid")
            ActionTiles(device: device, model: model) { url, appKind in
                open(url, appKind: appKind)
            }
        }
        .padding(.bottom, -DSLayout.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    /// After a ping, or while one runs.
    @ViewBuilder
    private func pingCard(model: DeviceDetailModel) -> some View {
        if !model.pingSamples.isEmpty || model.isPinging {
            PingCard(samples: model.pingSamples)
        }
    }

    private func latencyCard(device: DeviceSnapshot, model: DeviceDetailModel, quality: LatencyQuality?) -> some View {
        LatencyCard(
            samples: model.latency,
            quality: quality,
            kind: device.kind,
            gapSeconds: max(3 * environment.settings.monitor.baseIntervalSeconds, 120),
            now: now
        )
    }

    private func servicesCard(device: DeviceSnapshot, model: DeviceDetailModel) -> some View {
        ServicesCard(ports: model.ports, services: device.services, isScanning: model.isScanningPorts) {
            Task { await model.scanPorts(environment: environment) }
        }
    }

    @ViewBuilder
    private func aboutCard(model: DeviceDetailModel) -> some View {
        if model.insight != nil || model.isLoadingInsight {
            AboutDeviceCard(insight: model.insight)
        }
    }

    /// Hidden until there is a state change to show.
    @ViewBuilder
    private func logCard(device: DeviceSnapshot, model: DeviceDetailModel) -> some View {
        if !model.events.isEmpty {
            ConnectionLogCard(entries: ConnectionLog.entries(events: model.events, host: device.host, now: now))
        }
    }

    @ViewBuilder
    private func notesCard(device: DeviceSnapshot) -> some View {
        if !device.notes.isEmpty {
            NotesCard(notes: device.notes)
        }
    }

    /// Opens a device link; when no installed app handles the scheme, says so instead of failing silently.
    private func open(_ url: URL, appKind: String) {
        Task {
            let accepted = await UIApplication.shared.open(url)
            if !accepted {
                unopenedLink = appKind
            }
        }
    }

    private func shareText(for device: DeviceSnapshot) -> String {
        var lines = ["\(device.displayName) (\(device.kind.title))", "Address: \(device.host)"]
        if let hostname = device.hostname { lines.append("Hostname: \(hostname)") }
        if let vendor = device.vendor { lines.append("Vendor: \(vendor)") }
        lines.append("Status: \(device.state.title)")
        if !device.openPorts.isEmpty { lines.append("Open ports: \(device.openPorts.map(String.init).joined(separator: ", "))") }
        return lines.joined(separator: "\n")
    }
}

/// The device on the page, above the cards: its 48 pt render, the name, "Synology · Storage" and the state
/// with when it was checked. One VoiceOver element: "DiskStation, Online", "1.8 milliseconds, fast". The pulse
/// ring fires behind the thumbnail when the state changes.
private struct DetailHeader: View {
    let device: DeviceSnapshot
    /// The latest reading's word; nil while the device does not answer.
    let quality: LatencyQuality?
    let isLive: Bool
    let pulseTrigger: Int
    let now: Date

    @Environment(\.dsMotion) private var motion

    init(device: DeviceSnapshot, quality: LatencyQuality?, isLive: Bool, pulseTrigger: Int, now: Date) {
        self.device = device
        self.quality = quality
        self.isLive = isLive
        self.pulseTrigger = pulseTrigger
        self.now = now
    }

    var body: some View {
        HStack(alignment: .center, spacing: DSLayout.space12) {
            DeviceThumbnail(kind: device.kind, state: device.state, size: DSLayout.thumbnailHeader)
                .background {
                    PulseRingView(trigger: pulseTrigger, tint: UIColor(DSColor.fill(for: device.state)), isEnabled: !motion.reduceMotion)
                        .frame(width: 2 * DSLayout.thumbnailHeader, height: 2 * DSLayout.thumbnailHeader)
                        .allowsHitTesting(false)
                }
            VStack(alignment: .leading, spacing: DSLayout.space2) {
                Text(device.displayName)
                    .font(DSTypography.headerName)
                    .foregroundStyle(DSColor.textPrimary)
                Text(device.modelLine)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textPrimary)
                HStack(alignment: .firstTextBaseline, spacing: DSLayout.space4) {
                    DSStateLabel(state: device.state, isLive: isLive)
                    checkedText
                        .font(DSTypography.rowSubtitle)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .animation(DSMotion.animation(DSMotion.springSoft, reduceMotion: motion.reduceMotion), value: device.state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.displayName), \(device.state.title)")
        .accessibilityValue(spokenValue)
        .accessibilityIdentifier("detail.hero")
    }

    /// "· checked 20 sec ago", or "· last seen 2 hours ago" while offline.
    @ViewBuilder
    private var checkedText: some View {
        if device.state == .offline {
            Text("· last seen \(Self.lowercasingFirst(Formatters.relative(device.lastSeen, now: now)))")
        } else if let lastChecked = device.lastChecked {
            let checked = Text(.currentDate, format: .reference(to: lastChecked))
            Text("· checked \(checked)")
        }
    }

    /// "1.8 milliseconds, fast", or when an offline device last answered.
    private var spokenValue: String {
        switch device.state {
        case .online, .degraded:
            guard let latency = device.latencyMilliseconds else { return "No reading yet" }
            let reading = Formatters.spokenLatency(latency)
            return quality.map { "\(reading), \($0.title.lowercased())" } ?? reading
        case .offline:
            return "Last seen \(Self.lowercasingFirst(Formatters.relative(device.lastSeen, now: now)))"
        case .unknown:
            return "No reading yet"
        }
    }

    /// "Yesterday, 6:05 PM" becomes "yesterday, 6:05 PM" after "last seen".
    private static func lowercasingFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }
}

/// Every action on the device as outlined tiles, at most six: Check Now, Ping, Scan Ports, Open (when the
/// device has a link), Wake (when its MAC is known) and Trust. Three columns (3 + 3), every tile in one row
/// from a 600 pt card, two columns at accessibility sizes. Busy tiles show a spinner and keep their size.
private struct ActionTiles: View {
    let device: DeviceSnapshot
    let model: DeviceDetailModel
    let openLink: (URL, String) -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// When the last check finished; the tile reads "Checked" for 2 s after it.
    @State private var confirmedAt: Date?
    /// Set when a check finishes and never reset: Check Now's accessibility value, which VoiceOver and the
    /// flow tests read, because the 2 s label is too brief to poll for.
    @State private var lastCheckedAt: Date?
    @State private var width: CGFloat = 0

    init(device: DeviceSnapshot, model: DeviceDetailModel, openLink: @escaping (URL, String) -> Void) {
        self.device = device
        self.model = model
        self.openLink = openLink
    }

    private var hasLinks: Bool {
        device.webURL != nil || device.sshURL != nil || device.vncURL != nil
    }

    private var columnCount: Int {
        if dynamicTypeSize.isAccessibilitySize { return 2 }
        let tileCount = 4 + (hasLinks ? 1 : 0) + (device.canWake ? 1 : 0)
        return width >= 600 ? tileCount : 3
    }

    var body: some View {
        DSTileGrid(columns: columnCount) {
            checkTile
            Button {
                Task { await model.ping(environment: environment) }
            } label: {
                DSTileLabel("Ping", systemImage: "arrow.left.arrow.right", isBusy: model.isPinging)
            }
            .buttonStyle(DSTileButtonStyle())
            .accessibilityIdentifier("detail.ping")
            Button {
                Task { await model.scanPorts(environment: environment) }
            } label: {
                DSTileLabel("Scan Ports", systemImage: "network.badge.shield.half.filled", isBusy: model.isScanningPorts)
            }
            .buttonStyle(DSTileButtonStyle())
            .accessibilityIdentifier("detail.scanPorts")
            if hasLinks {
                openMenu
            }
            if device.canWake {
                Button {
                    Task { await model.wake(environment: environment) }
                } label: {
                    DSTileLabel("Wake", systemImage: "power", isBusy: model.isWaking)
                }
                .buttonStyle(DSTileButtonStyle())
                .accessibilityIdentifier("detail.wake")
            }
            Button {
                environment.toggleTrusted(device.id)
            } label: {
                DSTileLabel(device.isTrusted ? "Trusted" : "Trust", systemImage: device.isTrusted ? "checkmark.shield.fill" : "checkmark.shield")
            }
            .buttonStyle(DSTileButtonStyle())
            .accessibilityLabel("Trust")
            .accessibilityValue(device.isTrusted ? "On" : "Off")
            .accessibilityIdentifier("detail.trust")
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .onChange(of: model.isChecking) { wasChecking, isChecking in
            guard wasChecking, !isChecking else { return }
            let finished = Date()
            confirmedAt = finished
            lastCheckedAt = finished
            // Off Wi‑Fi nothing was probed, and the environment has already warned.
            guard environment.isDemo || environment.pathStatus.isWiFi else { return }
            if environment.directory.device(id: device.id)?.state.isUp == true {
                environment.haptics.success()
            } else {
                environment.haptics.warning()
            }
        }
        .task(id: confirmedAt) {
            guard confirmedAt != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            confirmedAt = nil
        }
    }

    private var checkTile: some View {
        Button {
            Task { await model.checkNow(environment: environment) }
        } label: {
            DSTileLabel(
                confirmedAt == nil ? "Check Now" : "Checked",
                systemImage: confirmedAt == nil ? "arrow.clockwise" : "checkmark",
                isBusy: model.isChecking
            )
        }
        .buttonStyle(DSTileButtonStyle())
        .accessibilityValue(lastCheckedAt == nil ? "" : "Checked")
        .accessibilityIdentifier("detail.checkNow")
    }

    /// Web, SSH and Screen Sharing, whichever the device offers.
    private var openMenu: some View {
        Menu {
            if let url = device.webURL {
                Button {
                    openLink(url, "a web browser")
                } label: {
                    Label("Open Web Interface", systemImage: "globe")
                }
            }
            if let url = device.sshURL {
                Button {
                    openLink(url, "an SSH terminal app")
                } label: {
                    Label("Open SSH", systemImage: "terminal")
                }
            }
            if let url = device.vncURL {
                Button {
                    openLink(url, "a VNC screen-sharing app")
                } label: {
                    Label("Open Screen Sharing", systemImage: "rectangle.inset.filled.and.cursorarrow")
                }
            }
        } label: {
            DSTileLabel("Open", systemImage: "arrow.up.forward.app")
        }
        .menuStyle(.button)
        .buttonStyle(DSTileButtonStyle())
        .accessibilityIdentifier("detail.open")
    }
}

#Preview("Device detail") {
    let environment = AppEnvironment.demo()
    NavigationStack {
        if let nas = environment.directory.devices.first(where: { $0.kind == .nas }) {
            DeviceDetailView(deviceID: nas.id)
        }
    }
    .environment(environment)
}
