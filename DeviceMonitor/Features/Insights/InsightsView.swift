import SwiftUI
import Observation

@Observable
@MainActor
final class InsightsModel {
    private(set) var score: SecurityScore?
    private(set) var summary: DeviceInsight?
    private(set) var isLoadingSummary = false
    /// The last 24 clock hours, oldest first, and who was present in each.
    private(set) var hourStarts: [Date] = []
    private(set) var presence: [PresenceRow] = []

    init() {}

    /// Recomputes the score and presence; a summary written for an older score is dropped so it never
    /// contradicts the numbers next to it.
    func reload(environment: AppEnvironment, now: Date) {
        let devices = environment.directory.devices
        let newScore = SecurityAssessor.score(devices: devices, now: now)
        if newScore != score {
            summary = nil
        }
        score = newScore
        // A month of events, so each row starts in the state the device was in before the first hour.
        let events = environment.recentEvents(since: now.addingTimeInterval(-30 * 24 * 3600))
        hourStarts = PresenceGrid.hourStarts(hours: 24, now: now)
        presence = PresenceGrid.rows(devices: devices, events: events, hourStarts: hourStarts, now: now)
    }

    func explain(environment: AppEnvironment) async {
        guard let explained = score, !isLoadingSummary else { return }
        isLoadingSummary = true
        let result = await environment.insightProvider.networkSummary(
            score: explained,
            deviceCount: environment.directory.devices.count,
            onlineCount: environment.directory.onlineCount,
            locale: Locale.current
        )
        // The score can change while the summary is written; one for the old score would contradict it.
        if score == explained {
            summary = result
        }
        isLoadingSummary = false
    }
}

/// The network's three analyses behind one segmented control: Security (the score on its range with the
/// checks behind it, strangers, findings and what kinds of devices are on the network), the network Map and
/// Presence. The router owns the section, so Overview's shortcuts can open one. Explain in the toolbar adds a
/// plain-language summary to the score.
struct InsightsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dsMotion) private var motion
    @State private var model = InsightsModel()
    @State private var now = Date()
    @State private var columns: LayoutColumns = .one
    /// The screen's width: the map is taller and shows names from 600 pt.
    @State private var width: CGFloat = 0
    @State private var showsAllFindings = false

    /// Scroll targets for the checklist's Review links.
    private static let strangersAnchor = "strangers"
    private static let findingsAnchor = "findings"
    /// Strangers on the card; See All opens the rest in Devices.
    private static let strangerLimit = 8
    /// Findings before Show All.
    private static let findingLimit = 3

    init() {}

    /// Everything the model reads, so a round, a history change or a device edit reloads once.
    private var reloadKey: InsightsReloadKey {
        InsightsReloadKey(
            lastRoundAt: environment.directory.lastRoundAt,
            historyRevision: environment.directory.historyRevision,
            devices: environment.directory.devices
        )
    }

    private var isRegular: Bool { width >= 600 }

    var body: some View {
        @Bindable var router = environment.router
        let section = $router.insightsSection

        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DSLayout.cardGap) {
                        if environment.directory.devices.isEmpty {
                            EmptyStateView(title: "Nothing to assess yet", message: "Scan your network to get a security score and a map of your devices.", systemImage: "dot.radiowaves.left.and.right", actionTitle: "Scan Network") {
                                environment.router.present(.scan)
                            }
                            .padding(.top, DSLayout.space32)
                        } else {
                            DSSegmentedControl(
                                InsightsSection.allCases,
                                selection: section,
                                style: .container,
                                identifierPrefix: "insights.section",
                                accessibilityLabel: "Section",
                                title: { $0.title }
                            )
                            .frame(maxWidth: 520, alignment: .leading)
                            switch section.wrappedValue {
                            case .security:
                                security(proxy: proxy)
                            case .map:
                                mapCard
                            case .presence:
                                presenceCard
                            }
                        }
                    }
                    .dsContainerMargins()
                    .padding(.top, DSLayout.space8)
                    .padding(.bottom, DSLayout.space32)
                }
                .accessibilityIdentifier("screen.insights")
                .readLayoutColumns($columns)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.width
                } action: { newWidth in
                    width = newWidth
                }
                .background {
                    DSColor.background
                        .ignoresSafeArea()
                }
                .navigationTitle("Insights")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        explainButton
                    }
                }
                .task(id: reloadKey) {
                    now = Date()
                    model.reload(environment: environment, now: now)
                }
                .refreshable {
                    now = Date()
                    model.reload(environment: environment, now: now)
                }
            }
        }
    }

    @ViewBuilder
    private var explainButton: some View {
        if model.isLoadingSummary {
            ProgressView()
        } else {
            Button("Explain") {
                // The summary lands on the score card.
                environment.router.insightsSection = .security
                Task { await model.explain(environment: environment) }
            }
            .tint(DSColor.textPrimary)
            .disabled(environment.directory.devices.isEmpty)
            .accessibilityHint(FoundationModelsInsightProvider.isAvailable ? "Summarises your network with Apple Intelligence on this device" : "Summarises your network in plain language")
            .accessibilityIdentifier("insights.explain")
        }
    }

    // MARK: - Security

    /// One column in reading order; two from one leading edge: the score on the left, the lists on the right.
    @ViewBuilder
    private func security(proxy: ScrollViewProxy) -> some View {
        let scoreCard = ScoreCard(score: model.score ?? SecurityScore(value: 100, findings: []), summary: model.summary, newcomers: newcomerCount) { kind in
            review(kind, proxy: proxy)
        }
        if columns == .one {
            scoreCard
            strangersCard
            findingsCard
            kindMixCard
        } else {
            DSMasonry(columns: 2, spacing: DSLayout.cardGap) {
                scoreCard
                VStack(alignment: .leading, spacing: DSLayout.cardGap) {
                    strangersCard
                    findingsCard
                    kindMixCard
                }
            }
        }
    }

    /// Review on a failing check: risky services lead to Findings, newcomers to Strangers, the router to its
    /// own page.
    private func review(_ kind: SecurityFactor.Kind, proxy: ScrollViewProxy) {
        let animation = DSMotion.animation(DSMotion.springSoft, reduceMotion: motion.reduceMotion)
        switch kind {
        case .services:
            withAnimation(animation) {
                proxy.scrollTo(Self.findingsAnchor, anchor: .top)
            }
        case .newcomers:
            withAnimation(animation) {
                proxy.scrollTo(Self.strangersAnchor, anchor: .top)
            }
        case .router:
            if let gatewayID = environment.directory.gatewayID {
                environment.router.showDevice(gatewayID)
            }
        }
    }

    /// Untrusted devices that joined in the last day, as the score's newcomer check counts them.
    private var newcomerCount: Int {
        environment.directory.devices.filter { !$0.isTrusted && !$0.isUserAdded && $0.isNew(now: now) }.count
    }

    private var strangers: [DeviceSnapshot] {
        environment.directory.devices
            .filter(\.isStranger)
            .sorted { $0.firstSeen > $1.firstSeen }
    }

    /// Untrusted devices, newest first, each with Trust. More than fit on the card are one link away in Devices.
    private var strangersCard: some View {
        let all = strangers
        let shown = Array(all.prefix(Self.strangerLimit))
        return VStack(alignment: .leading, spacing: 0) {
            DSTitleRow("Strangers", qualifier: all.isEmpty ? nil : "(\(all.count))") {
                if all.count > shown.count {
                    DSLink("See All", accessibilityLabel: "See all strangers") {
                        environment.router.showDevices(filter: .strangers)
                    }
                }
            }
            if shown.isEmpty {
                Text("Every device is trusted")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.top, DSLayout.space12)
                    .accessibilityIdentifier("insights.strangers.empty")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, device in
                        StrangerRow(device: device, now: now, isLast: index == shown.count - 1) {
                            environment.router.showDevice(device.id)
                        } onTrust: {
                            environment.toggleTrusted(device.id)
                        }
                    }
                }
                .padding(.top, DSLayout.space4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.strangers")
        .id(Self.strangersAnchor)
    }

    /// The most severe findings first, three until Show All.
    private var findingsCard: some View {
        let findings = model.score?.findings ?? []
        let shown = showsAllFindings ? findings : Array(findings.prefix(Self.findingLimit))
        return VStack(alignment: .leading, spacing: 0) {
            DSTitleRow("Findings", qualifier: findings.isEmpty ? nil : "(\(findings.count))")
            if findings.isEmpty {
                Text("No risky services, unknown newcomers or router problems.")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DSLayout.space12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, finding in
                        FindingRow(
                            finding: finding,
                            device: finding.deviceID.flatMap { environment.directory.device(id: $0) },
                            isLast: index == shown.count - 1
                        ) { id in
                            environment.router.showDevice(id)
                        }
                    }
                }
                .padding(.top, DSLayout.space4)
                if findings.count > Self.findingLimit {
                    DSLink(showsAllFindings ? "Show Less" : "Show All (\(findings.count))") {
                        withAnimation(DSMotion.animation(DSMotion.springSoft, reduceMotion: motion.reduceMotion)) {
                            showsAllFindings.toggle()
                        }
                    }
                    .padding(.top, DSLayout.space8)
                    .accessibilityIdentifier("insights.findings.showAll")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.findings")
        .id(Self.findingsAnchor)
    }

    /// One row per kind family, largest first, with a grey bar as long as its share of the network.
    private var kindMixCard: some View {
        let devices = environment.directory.devices
        let shares = KindShare.shares(of: devices)
        return VStack(alignment: .leading, spacing: 0) {
            DSTitleRow("What's on your network", qualifier: "(\(devices.count))")
            VStack(spacing: 0) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                    KindMixRow(share: share, total: devices.count, isLast: index == shares.count - 1)
                }
            }
            .padding(.top, DSLayout.space4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.kindMix")
    }

    // MARK: - Map and presence

    /// Kind sectors around the router at latency distance, then what the marks mean.
    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSTitleRow("Network map", qualifier: "(\(environment.directory.devices.count))")
            TopologyView(
                devices: environment.directory.devices,
                gatewayID: environment.directory.gatewayID,
                showsNames: isRegular
            ) { id in
                environment.router.showDevice(id)
            }
            .frame(height: isRegular ? 520 : 360)
            .padding(.top, DSLayout.space12)
            Text("Closer = faster. Rings at 2, 10 and 50 ms. Dashed = not answering. DeviceMonitor can't see cables or Wi‑Fi access points.")
                .font(DSTypography.rowSubtitle)
                .foregroundStyle(DSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DSLayout.space12)
            HStack(spacing: DSLayout.space12) {
                DSLegendSwatch(color: DSColor.degradedFill, title: "Unstable")
                DSLegendSwatch(color: DSColor.offlineFill, title: "Offline")
            }
            .padding(.top, DSLayout.space8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.map")
    }

    /// Who is around when over the last 24 clock hours, built from the changes seen while the app was open.
    private var presenceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSTitleRow("Presence", qualifier: "24H")
            VStack(alignment: .leading, spacing: DSLayout.space4) {
                if let headline = PresenceGrid.headline(rows: model.presence, hourStarts: model.hourStarts) {
                    Text(headline)
                        .font(DSTypography.body)
                        .foregroundStyle(DSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(AvailabilityNarrative.seenWhileOpenCaption)
                    .font(DSTypography.axis)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(.top, DSLayout.space12)
            PresenceHeatmapView(rows: model.presence, hourStarts: model.hourStarts)
                .padding(.top, DSLayout.space12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.presence")
    }
}

/// What Insights' data depends on; one change of any part reloads the model once.
private nonisolated struct InsightsReloadKey: Hashable {
    let lastRoundAt: Date?
    let historyRevision: Int
    let devices: [DeviceSnapshot]
}

/// The lead card: the score and its grade, the score on its range, one row per check with what it costs, and
/// the summary from Explain.
private struct ScoreCard: View {
    let score: SecurityScore
    let summary: DeviceInsight?
    /// Untrusted devices that joined in the last day.
    let newcomers: Int
    let onReview: (SecurityFactor.Kind) -> Void

    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .subheadline) private var glyphColumn: CGFloat = 20

    init(score: SecurityScore, summary: DeviceInsight?, newcomers: Int, onReview: @escaping (SecurityFactor.Kind) -> Void) {
        self.score = score
        self.summary = summary
        self.newcomers = newcomers
        self.onReview = onReview
    }

    /// Open services found by the port check.
    private var riskyServices: Int {
        score.findings.filter { $0.id.hasPrefix("port-") }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSTitleRow("Security score", qualifier: "\(score.value) of 100", status: DSStatusWord(score.grade, tone: DSTone.forScore(score.value)))
            DSGradientScale(
                scale: .securityScore,
                value: Double(score.value),
                markerSymbol: "shield.lefthalf.filled",
                accessibilityLabel: "Security score",
                accessibilityValue: "\(score.value) of 100"
            )
            .padding(.top, DSLayout.space16)
            checklist
                .padding(.top, DSLayout.space12)
            if let summary {
                summaryView(summary)
                    .padding(.top, DSLayout.space12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.score")
    }

    /// The points stay in one column: while any check fails, passing rows keep Review's width free.
    private var checklist: some View {
        let factors = score.factors
        let anyFails = factors.contains { $0.pointsLost > 0 }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(factors.enumerated()), id: \.element.id) { index, factor in
                checkRow(factor, reservesReview: anyFails, isLast: index == factors.count - 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.checklist")
    }

    /// A 44 pt row: the check's severity mark, what it found and its cost; a failing check adds Review.
    private func checkRow(_ factor: SecurityFactor, reservesReview: Bool, isLast: Bool) -> some View {
        let passes = factor.pointsLost == 0
        let checkTitle = title(for: factor)
        let risk = severity(of: factor.kind)
        return HStack(spacing: DSLayout.space12) {
            HStack(spacing: DSLayout.space12) {
                Image(systemName: passes ? "checkmark.circle.fill" : risk.systemImage)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.ink(passes ? .good : DSTone.forRisk(risk)))
                    .frame(width: glyphColumn)
                    .accessibilityHidden(true)
                Text(checkTitle)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(passes ? "OK" : "−\(factor.pointsLost)")
                    .font(DSTypography.bodyValue)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(checkTitle)
            .accessibilityValue(passes ? "Passed" : "\(risk.title), \(factor.pointsLost) points")
            if !passes {
                DSLink("Review", accessibilityLabel: "Review \(checkTitle)") {
                    onReview(factor.kind)
                }
            } else if reservesReview {
                Text("Review")
                    .font(DSTypography.body)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: DSLayout.minTapTarget)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(DSColor.hairline)
                    .frame(height: 1 / displayScale)
                    .padding(.leading, glyphColumn + DSLayout.space12)
            }
        }
    }

    /// The plain-language summary under a hairline, with where it came from.
    private func summaryView(_ summary: DeviceInsight) -> some View {
        VStack(alignment: .leading, spacing: DSLayout.space12) {
            Rectangle()
                .fill(DSColor.hairline)
                .frame(height: 1 / displayScale)
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.body)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Group {
                    if summary.source == .onDeviceModel {
                        Label("Written on this iPhone with Apple Intelligence", systemImage: "apple.intelligence")
                    } else {
                        Text("Rule-based summary")
                    }
                }
                .font(DSTypography.rowSubtitle)
                .foregroundStyle(DSColor.textSecondary)
            }
        }
    }

    private func title(for factor: SecurityFactor) -> String {
        let passes = factor.pointsLost == 0
        switch factor.kind {
        case .services:
            return passes ? "No risky services" : "\(Formatters.count(riskyServices, singular: "risky service", plural: "risky services")) open"
        case .newcomers:
            return passes ? "All devices known" : "\(Formatters.count(max(newcomers, 1), singular: "device", plural: "devices")) you haven't trusted"
        case .router:
            return passes ? "Router answering normally" : "Router not answering reliably"
        }
    }

    /// The worst finding behind a failing check, so the same fact has the same mark here and in Findings.
    /// Newcomers and the router are medium.
    private func severity(of kind: SecurityFactor.Kind) -> PortRisk {
        guard kind == .services else { return .medium }
        return score.findings.contains { $0.id.hasPrefix("port-") && $0.severity == .high } ? .high : .medium
    }
}

/// An untrusted device: the row opens it and the pill trusts it, so the row never asks two things at once.
private struct StrangerRow: View {
    let device: DeviceSnapshot
    let now: Date
    let isLast: Bool
    let onOpen: () -> Void
    let onTrust: () -> Void

    @Environment(\.displayScale) private var displayScale

    init(device: DeviceSnapshot, now: Date, isLast: Bool, onOpen: @escaping () -> Void, onTrust: @escaping () -> Void) {
        self.device = device
        self.now = now
        self.isLast = isLast
        self.onOpen = onOpen
        self.onTrust = onTrust
    }

    /// "joined 1 hour ago", "joined today, 14:05", "joined Oct 16, 2026".
    private var joined: String {
        let relative = Formatters.relative(device.firstSeen, now: now)
        guard ["Just", "Today", "Yesterday"].contains(where: { relative.hasPrefix($0) }) else {
            return "joined \(relative)"
        }
        return "joined \(relative.prefix(1).lowercased())\(relative.dropFirst())"
    }

    private var isNew: Bool {
        device.isNewcomer(now: now)
    }

    /// "esp_3a7f21, Smart Device, Online, New device".
    private var spokenLabel: String {
        let parts = [device.displayName, device.kind.title, device.state.title] + (isNew ? ["New device"] : [])
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: DSLayout.space12) {
            Button(action: onOpen) {
                DSListRow(
                    thumbnail: DeviceThumbnail(kind: device.kind, state: device.state),
                    title: device.displayName,
                    badges: isNew ? [.new] : [],
                    subtitle: [device.host, joined],
                    accessibilityLabel: spokenLabel,
                    accessibilityValue: "\(device.host), \(joined)"
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the device")
            DSPillButton("Trust", action: onTrust)
                .accessibilityLabel("Trust \(device.displayName)")
                .accessibilityIdentifier("insights.trust.\(device.host)")
        }
        .padding(.vertical, DSLayout.space8)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(DSColor.hairline)
                    .frame(height: 1 / displayScale)
                    .padding(.leading, DSLayout.thumbnailRow + DSLayout.space12)
            }
        }
    }
}

/// A finding as a port row: the device's render with the risk badge (the network glyph for a finding about
/// the whole network), the title over two lines of detail, and a chevron when it opens a device.
private struct FindingRow: View {
    let finding: SecurityFinding
    let device: DeviceSnapshot?
    let isLast: Bool
    let onOpen: (UUID) -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(finding: SecurityFinding, device: DeviceSnapshot?, isLast: Bool, onOpen: @escaping (UUID) -> Void) {
        self.finding = finding
        self.device = device
        self.isLast = isLast
        self.onOpen = onOpen
    }

    var body: some View {
        if let deviceID = finding.deviceID {
            Button {
                onOpen(deviceID)
            } label: {
                content(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the device")
        } else {
            content(showsChevron: false)
        }
    }

    /// Fixed colours, not the hierarchical styles, which the button around the row would resolve to its tint.
    private func content(showsChevron: Bool) -> some View {
        let isLarge = dynamicTypeSize.isAccessibilitySize
        return HStack(spacing: DSLayout.space12) {
            DSThumbnail(
                systemImage: device.map { DeviceThumbnail.symbol(for: $0.kind) } ?? "network",
                size: DSLayout.thumbnailService,
                badge: .risk(finding.severity)
            )
            VStack(alignment: .leading, spacing: DSLayout.space2) {
                Text(finding.title)
                    .font(DSTypography.rowTitle)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(isLarge ? 3 : 1)
                Text(finding.detail)
                    .font(DSTypography.rowSubtitle)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(isLarge ? 4 : 2)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(DSTypography.rowSubtitle.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, DSLayout.space12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(DSColor.hairline)
                    .frame(height: 1 / displayScale)
                    .padding(.leading, DSLayout.thumbnailService + DSLayout.space12)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(finding.severity.title)
    }
}

/// A kind family and how many devices belong to it.
private nonisolated struct KindShare: Sendable, Hashable, Identifiable {
    let family: KindFamily
    let count: Int

    var id: KindFamily { family }

    /// Every family with devices, largest first, then in the map's sector order.
    static func shares(of devices: [DeviceSnapshot]) -> [KindShare] {
        Dictionary(grouping: devices) { KindFamily($0.kind) }
            .map { KindShare(family: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.family.rawValue < rhs.family.rawValue
            }
    }
}

/// A 40 pt row of the kind mix: the family's thumbnail and name, a 4 pt grey bar as long as its share of the
/// network, and the count. At accessibility sizes the bar moves under the name.
private struct KindMixRow: View {
    let share: KindShare
    let total: Int
    let isLast: Bool

    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Fits "Phones & watches", so every bar starts at the same x.
    @ScaledMetric(relativeTo: .subheadline) private var nameWidth: CGFloat = 132
    @ScaledMetric(relativeTo: .subheadline) private var countWidth: CGFloat = 28

    private static let thumbnailSize: CGFloat = 24

    init(share: KindShare, total: Int, isLast: Bool) {
        self.share = share
        self.total = total
        self.isLast = isLast
    }

    private var fraction: Double {
        total > 0 ? Double(share.count) / Double(total) : 0
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DSLayout.space4) {
                    HStack(spacing: DSLayout.space12) {
                        thumbnail
                        name
                        Spacer(minLength: DSLayout.space8)
                        count
                    }
                    bar
                }
                .padding(.vertical, DSLayout.space8)
            } else {
                HStack(spacing: DSLayout.space12) {
                    thumbnail
                    name
                        .frame(width: nameWidth, alignment: .leading)
                    bar
                    count
                        .frame(width: countWidth, alignment: .trailing)
                }
            }
        }
        .frame(minHeight: DSLayout.statRowHeight)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(DSColor.hairline)
                    .frame(height: 1 / displayScale)
                    .padding(.leading, Self.thumbnailSize + DSLayout.space12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(share.family.title)
        .accessibilityValue("\(Formatters.count(share.count, singular: "device", plural: "devices")) of \(total)")
    }

    private var thumbnail: some View {
        DeviceThumbnail(kind: share.family.representative, size: Self.thumbnailSize, showsStateBadge: false)
    }

    private var name: some View {
        Text(share.family.title)
            .font(DSTypography.body)
            .foregroundStyle(DSColor.textPrimary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }

    private var count: some View {
        Text("\(share.count)")
            .font(DSTypography.bodyValue)
            .foregroundStyle(DSColor.textSecondary)
    }

    private var bar: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(DSColor.neutralMark)
                        .frame(width: max(4, geometry.size.width * CGFloat(fraction)))
                }
            }
    }
}

#Preview("Insights") {
    InsightsView()
        .environment(AppEnvironment.demo())
}
