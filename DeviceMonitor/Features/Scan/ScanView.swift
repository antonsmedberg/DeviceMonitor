import SwiftUI

/// Subnet scan sheet: the radar, one status line under it that owns every number, the stages while scanning,
/// errors in place, then the hosts found, new ones first. The finished state says what the scan found in one
/// line. Scan Again is the sheet's one filled button.
struct ScanView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dsMotion) private var motion
    @Environment(\.displayScale) private var displayScale
    @State private var hasStarted = false
    @State private var wasStopped = false

    init() {}

    /// Only the scan this sheet runs or follows; an earlier scan's results are not shown as current.
    private var progress: ScanProgress? { (hasStarted || environment.isScanning) ? environment.scanProgress : nil }
    private var fraction: Double { progress?.fraction ?? 0 }

    private var canScan: Bool {
        guard environment.permissionState != .denied else { return false }
        if environment.isDemo { return true }
        guard environment.pathStatus.isWiFi, let subnet = environment.currentSubnet else { return false }
        return subnet.isScannable
    }

    /// This sheet's scan ran to the end: not running, stopped or failed.
    private var isFinished: Bool {
        hasStarted && !wasStopped && !environment.isScanning && progress != nil && environment.permissionState != .denied
    }

    private var statusText: String {
        if environment.permissionState == .denied { return "Local network access is off" }
        if environment.isScanning, let progress { return "Checked \(progress.scanned) of \(progress.total) · \(progress.found) found" }
        if wasStopped, let progress { return "Stopped · \(progress.found) found" }
        guard let subnet = environment.currentSubnet else { return "Join a Wi‑Fi network to scan" }
        if let last = environment.lastScanAt {
            return "Ready to scan \(subnet.description) · last scan \(Formatters.relative(last, now: Date()).lowercased())"
        }
        return "Ready to scan \(subnet.description)"
    }

    /// Known devices by address, to name, classify and place the hosts the scan finds.
    private var devicesByHost: [String: DeviceSnapshot] {
        Dictionary(environment.directory.devices.map { ($0.host, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let known = devicesByHost
        let now = Date()
        NavigationStack {
            ScrollView {
                VStack(spacing: DSLayout.space20) {
                    radar(known: known, now: now)
                    overview(known: known, now: now)

                    if progress != nil && !environment.scanFound.isEmpty {
                        foundCard(known: known, now: now)
                    }

                    Text("Scanning checks every address on your subnet with short connection attempts. Nothing is sent to the internet.")
                        .font(DSTypography.rowSubtitle)
                        .foregroundStyle(DSColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DSLayout.space24)
                }
                .dsContainerMargins()
                .padding(.bottom, DSLayout.space32)
                .animation(DSMotion.animation(DSMotion.springSoft, reduceMotion: motion.reduceMotion), value: environment.bannerError)
                // The stages leave without a transition under Reduce Motion.
                .animation(motion.reduceMotion ? nil : DSMotion.springSoft, value: environment.isScanning)
            }
            .background {
                DSColor.background
                    .ignoresSafeArea()
            }
            .accessibilityIdentifier("screen.scan")
            .navigationTitle("Scan Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if environment.isScanning {
                        Button {
                            environment.cancelScan()
                            wasStopped = true
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .tint(DSColor.textPrimary)
                        .accessibilityIdentifier("scan.stop")
                    } else {
                        Button(role: .close) {
                            dismiss()
                        }
                        .tint(DSColor.textPrimary)
                        .accessibilityIdentifier("scan.close")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if environment.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(hasStarted ? "Scan Again" : "Scan") {
                            start()
                        }
                        .buttonStyle(.glassProminent)
                        .tint(DSColor.accentFill(for: environment.settings.accent))
                        .disabled(!canScan)
                        .accessibilityIdentifier("scan.again")
                    }
                }
            }
            .task {
                // A scan still running from an earlier visit carries on as this sheet's scan.
                if environment.isScanning {
                    hasStarted = true
                    return
                }
                guard !hasStarted else { return }
                if environment.permissionState == .undetermined {
                    await environment.requestLocalNetworkPermission()
                }
                // The sheet may have been closed while the permission alert was up. Without access or
                // Wi‑Fi the banners below already say why no scan runs; other failures show their error.
                guard !Task.isCancelled, environment.permissionState != .denied, environment.pathStatus.isWiFi || environment.isDemo else { return }
                start()
            }
            .onChange(of: environment.isScanning) { _, isScanning in
                // A scan that ends with an error stopped early, so it never reads as done.
                if !isScanning && environment.bannerError != nil {
                    wasStopped = true
                }
            }
        }
        .presentationDetents([.large])
        .presentationSizing(.form)
    }

    /// The radar is hidden from VoiceOver; the status line, the stages and Found say what it shows.
    private func radar(known: [String: DeviceSnapshot], now: Date) -> some View {
        ScanRadarView(blips: blips(known: known, now: now), isScanning: environment.isScanning)
            .frame(width: 240, height: 240)
            .padding(.top, DSLayout.space12)
    }

    /// The status line, any banner, and the stages while scanning. The status line is always `scan.status`, with the
    /// value "Finished" once this sheet's scan has finished, so a test waits on an element that exists.
    @ViewBuilder
    private func overview(known: [String: DeviceSnapshot], now: Date) -> some View {
        statusLine(isFinished ? ScanSummary.text(found: environment.scanFound, known: environment.directory.devices, networkKey: environment.currentNetworkKey, now: now) : statusText)
            .accessibilityValue(isFinished ? "Finished" : "")
            .accessibilityIdentifier("scan.status")

        if let error = environment.bannerError {
            ErrorBanner(error: error, onDismiss: { environment.dismissBannerError() })
                .transition(DSMotion.bannerTransition(reduceMotion: motion.reduceMotion))
        }
        if environment.permissionState == .denied {
            LocalNetworkDeniedBanner()
        } else if !environment.pathStatus.isWiFi && !environment.isDemo {
            InfoBanner(title: "Not on Wi‑Fi", message: "Scanning only works on the Wi‑Fi network your devices use.", systemImage: "wifi.slash", tint: DSColor.degraded)
        }

        if environment.isScanning {
            stagesCard(known: known)
                .transition(.opacity)
        }
    }

    private func statusLine(_ text: String) -> some View {
        Text(text)
            .font(DSTypography.bodyValue)
            .foregroundStyle(DSColor.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .contentTransition(.numericText())
            .animation(DSMotion.animation(DSMotion.springSoft, reduceMotion: motion.reduceMotion), value: fraction)
    }

    // MARK: - Radar

    /// One blip per host found, except the gateway, which is the radar's centre. Each kind family gets a
    /// sector, as on the network map, and its hosts spread across it in address order; hosts the app does
    /// not know yet count as things.
    private func blips(known: [String: DeviceSnapshot], now: Date) -> [ScanBlip] {
        guard progress != nil else { return [] }
        let gatewayHosts = Set(environment.pathStatus.gatewayHosts)
        let hosts = environment.scanFound.filter { host in
            !gatewayHosts.contains(host.host) && known[host.host]?.isGateway != true
        }
        let families = Dictionary(grouping: hosts) { host in
            known[host.host].map { KindFamily($0.kind) } ?? .things
        }
        let sectors = TopologyLayout.sectors(counts: families.mapValues(\.count))
        return KindFamily.allCases.flatMap { family -> [ScanBlip] in
            guard let sector = sectors[family], let members = families[family] else { return [] }
            let ordered = members.sorted { lhs, rhs in
                (IPv4Host(lhs.host)?.rawValue ?? .max) < (IPv4Host(rhs.host)?.rawValue ?? .max)
            }
            let step = (sector.upperBound - sector.lowerBound) / Double(ordered.count)
            return ordered.enumerated().map { index, host in
                ScanBlip(
                    id: host.id,
                    angle: sector.lowerBound + step * (Double(index) + 0.5),
                    distance: ScanRadarView.distance(latency: host.probe?.outcome.latencyMilliseconds),
                    isNew: ScanSummary.isNew(known[host.host], now: now)
                )
            }
        }
    }

    // MARK: - Stages

    private func stagesCard(known: [String: DeviceSnapshot]) -> some View {
        let found = environment.scanFound
        let measured = found.filter { $0.probe?.outcome.latencyMilliseconds != nil }.count
        let identified = found.filter { isIdentified($0, snapshot: known[$0.host]) }.count
        let stages = ScanStage.stages(progress: progress, isScanning: environment.isScanning, isFinished: isFinished, measured: measured, identified: identified)
        return VStack(spacing: 0) {
            ForEach(stages) { stage in
                stageRow(stage)
            }
        }
        .padding(.horizontal, DSLayout.space8)
        .dsCard(padding: DSLayout.space8)
        .animation(DSMotion.animation(DSMotion.springSoft, reduceMotion: motion.reduceMotion), value: fraction)
    }

    private func stageRow(_ stage: ScanStage) -> some View {
        HStack(spacing: DSLayout.space12) {
            stageSymbol(stage.phase)
                .font(DSTypography.body)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(stage.title)
                .font(DSTypography.body)
                .foregroundStyle(stage.phase == .waiting ? DSColor.textSecondary : DSColor.textPrimary)
            Spacer(minLength: DSLayout.space8)
            if let count = stage.count {
                Text("\(count)")
                    .font(DSTypography.bodyValue)
                    .foregroundStyle(DSColor.textSecondary)
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
        .accessibilityValue(stage.phase.rawValue)
        .accessibilityIdentifier(identifier(for: stage.step))
    }

    /// Waiting is a ring in the tertiary grey, running a pulsing dotted ring in the tint, done a grey check:
    /// mint would say "online", not "done".
    @ViewBuilder
    private func stageSymbol(_ phase: ScanStage.Phase) -> some View {
        switch phase {
        case .waiting:
            Image(systemName: "circle")
                .foregroundStyle(DSColor.textTertiary)
        case .running:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: !motion.reduceMotion && !LaunchArguments.current.isScreenshots)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    private func identifier(for step: ScanStage.Step) -> String {
        switch step {
        case .sweep: return "scan.stage.sweep"
        case .measure: return "scan.stage.measure"
        case .identify: return "scan.stage.identify"
        case .compare: return "scan.stage.compare"
        }
    }

    /// A found host has a name from the network, or the app already knows its kind or its name.
    private func isIdentified(_ host: DiscoveredHost, snapshot: DeviceSnapshot?) -> Bool {
        if let hostname = host.hostname, !hostname.isEmpty { return true }
        guard let snapshot else { return false }
        return snapshot.kind != .unknown || snapshot.displayName != snapshot.host
    }

    // MARK: - Found

    /// The same anatomy as a Devices row: the kind's thumbnail, the name with a New badge, address and vendor,
    /// and the latency in the primary text colour, because a scan has no usual latency to compare with.
    private func foundCard(known: [String: DeviceSnapshot], now: Date) -> some View {
        let hosts = ScanSummary.ordered(found: environment.scanFound, known: known, now: now)
        return VStack(alignment: .leading, spacing: DSLayout.space4) {
            DSTitleRow("Found", qualifier: "(\(hosts.count))")
            VStack(spacing: 0) {
                ForEach(Array(hosts.enumerated()), id: \.element.id) { index, host in
                    foundRow(host, snapshot: known[host.host], now: now)
                        .padding(.vertical, DSLayout.space8)
                        .overlay(alignment: .top) {
                            if index > 0 {
                                Rectangle()
                                    .fill(DSColor.hairline)
                                    .frame(height: 1 / displayScale)
                                    .padding(.leading, DSLayout.thumbnailRow + DSLayout.space12)
                            }
                        }
                        .transition(DSMotion.rowTransition(reduceMotion: motion.reduceMotion))
                }
            }
            .animation(DSMotion.animation(DSMotion.springFast, reduceMotion: motion.reduceMotion), value: environment.scanFound.count)
        }
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scan.found")
    }

    private func foundRow(_ host: DiscoveredHost, snapshot: DeviceSnapshot?, now: Date) -> some View {
        let title = snapshot?.displayName ?? host.hostname ?? host.host
        let isNew = ScanSummary.isNew(snapshot, now: now)
        let vendor = snapshot?.vendor.flatMap { $0.isEmpty ? nil : $0 }
        let latency = host.probe?.outcome.latencyMilliseconds.map { Formatters.latency($0) }
        return DSListRow(
            thumbnail: DeviceThumbnail(kind: snapshot?.kind ?? .unknown, state: snapshot?.state ?? .online, showsStateBadge: false),
            title: title,
            badges: isNew ? [.new] : [],
            subtitle: [host.host] + (vendor.map { [$0] } ?? []),
            primary: latency,
            accessibilityLabel: isNew ? "\(title), New device" : title,
            accessibilityValue: ([host.host, vendor, latency.map { "latency \($0)" }].compactMap { $0 }).joined(separator: ", ")
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scanRow.\(host.host)")
    }

    private func start() {
        hasStarted = true
        wasStopped = false
        environment.startScan()
    }
}

#Preview("Scan") {
    ScanView()
        .environment(AppEnvironment.demo())
}
