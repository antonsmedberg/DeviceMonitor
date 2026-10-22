import SwiftUI
import Observation

@Observable
@MainActor
final class TimelineModel {
    nonisolated enum Filter: String, Sendable, Hashable, CaseIterable {
        case all, new, left, outages

        var title: String {
            switch self {
            case .all: return "All"
            case .new: return "New"
            case .left: return "Offline"
            case .outages: return "Outages"
            }
        }
    }

    var filter: Filter = .all
    var range: TimelineRange = .day
    /// The moment picked on the Devices online chart; the feed shows the bucket that holds it. Buckets are
    /// anchored to now and move every round, so the pick follows this moment instead of a bucket position.
    var selectedDate: Date?
    private(set) var sections: [(day: Date, entries: [TimelineEntry])] = []
    private(set) var density: ActivityDensity?
    private(set) var totalCount = 0
    /// Network outages that started inside the range.
    private(set) var outageCount = 0
    /// What happened since `lastLookedAt`, most important first.
    private(set) var journal: [JournalLine] = []
    /// When the person last tapped Done on the journal; until they do, 12 hours before now.
    private(set) var lastLookedAt = Date()

    init() {}

    /// The index of the bucket that holds `selectedDate`.
    var selectedBucket: Int? {
        get { selected?.index }
        set {
            let bucket = newValue.flatMap { index in density?.buckets.first { $0.index == index } }
            selectedDate = bucket.map { $0.start.addingTimeInterval($0.end.timeIntervalSince($0.start) / 2) }
        }
    }

    private var selected: ActivityDensity.Bucket? {
        guard let selectedDate else { return nil }
        return density?.buckets.first { $0.start <= selectedDate && selectedDate < $0.end }
    }

    func reload(environment: AppEnvironment, now: Date) {
        let events = environment.recentEvents(since: now.addingTimeInterval(-30 * 24 * 3600))
        let snapshots = environment.directory.devices
        density = ActivityDensity(events: events, devices: snapshots, range: range, now: now)
        if selectedDate != nil, selected == nil {
            selectedDate = nil
        }

        let devices = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        var entries = NetworkTimelineBuilder.entries(
            events: events,
            devices: devices,
            gatewayID: environment.directory.gatewayID,
            outageWindowSeconds: 90,
            outageFraction: 0.6,
            now: now
        )
        totalCount = entries.count
        let rangeStart = now.addingTimeInterval(-range.seconds)
        outageCount = entries.filter { $0.kind == .outageStarted && $0.date >= rangeStart }.count
        lastLookedAt = UserDefaults.standard.object(forKey: Self.lookedKey(isDemo: environment.isDemo)) as? Date
            ?? now.addingTimeInterval(-12 * 3600)
        journal = Journal.lines(entries: entries, devices: devices, since: lastLookedAt)
        switch filter {
        case .all: break
        case .new: entries = entries.filter { $0.kind == .newDevice }
        case .left: entries = entries.filter { $0.kind == .left }
        case .outages: entries = entries.filter { $0.kind == .outageStarted || $0.kind == .outageEnded }
        }
        if let bucket = selected {
            entries = entries.filter { $0.date >= bucket.start && $0.date < bucket.end }
        }
        sections = NetworkTimelineBuilder.sectionedByDay(entries, calendar: .current)
    }

    /// Stores `now` as the moment the person last looked, which empties the journal.
    func markLooked(environment: AppEnvironment, now: Date) {
        UserDefaults.standard.set(now, forKey: Self.lookedKey(isDemo: environment.isDemo))
        reload(environment: environment, now: now)
    }

    /// The stored key keeps its pre-Activity name; the demo has its own, so demo runs never move the real date.
    private static func lookedKey(isDemo: Bool) -> String {
        "\(isDemo ? "demo." : "")timeline.lastLookedAt"
    }
}

/// Activity: what happened since you last looked, devices online over time, the address map, then a feed of
/// arrivals, departures and outages by day. The filter is the first row; the range lives in its card. Every
/// control in a row is its own plain button, so no row acts as one tap target.
struct ActivityTimelineView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var model = TimelineModel()
    @State private var now = Date()
    /// iPhone shows the address map only on request; regular widths always show it.
    @State private var showsAddressMap = false
    /// Wide enough for the "New" badge, so every journal line's text starts at the same x.
    @ScaledMetric(relativeTo: .caption2) private var badgeColumn: CGFloat = 36

    init() {}

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                Section {
                    DSSegmentedControl(
                        TimelineModel.Filter.allCases,
                        selection: $model.filter,
                        style: .container,
                        identifierPrefix: "activity.filter",
                        accessibilityLabel: "Show",
                        title: { $0.title }
                    )
                    .cardRow()
                }
                .listSectionMargins(.top, DSLayout.space8)

                if !environment.directory.devices.isEmpty {
                    if !model.journal.isEmpty {
                        Section {
                            journalCard
                                .cardRow()
                        }
                    }
                    if let density = model.density {
                        Section {
                            onlineCard(density)
                                .cardRow()
                        }
                    }
                    if sizeClass == .regular || showsAddressMap {
                        Section {
                            addressMap
                                .cardRow()
                        }
                    }
                }

                if model.sections.isEmpty {
                    Section {
                        EmptyStateView(
                            title: model.totalCount == 0 ? "No activity yet" : "Nothing here",
                            message: model.totalCount == 0 ? "Devices joining, leaving and outages appear here as monitoring runs." : "Try another filter or clear the selected time.",
                            systemImage: "clock"
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } else {
                    ForEach(model.sections, id: \.day) { section in
                        Section {
                            ForEach(section.entries) { entry in
                                row(for: entry)
                                    .listRowInsets(EdgeInsets(top: 0, leading: DSLayout.space16, bottom: 0, trailing: DSLayout.space16))
                                    .dsListRow()
                            }
                        } header: {
                            DSListHeader(sectionTitle(section.day), count: section.entries.count)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("screen.activity")
            .dsGroupedList()
            .dsFormColumn(maxRowWidth: 880)
            // 8 pt under the title, here and on the first section: it has no header, so the grouped style would leave
            // about 45 pt.
            .contentMargins(.top, DSLayout.space8, for: .scrollContent)
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: environment.directory.lastRoundAt) {
                now = Date()
                model.reload(environment: environment, now: now)
            }
            .onChange(of: model.filter) { _, _ in
                model.reload(environment: environment, now: now)
            }
            .onChange(of: model.range) { _, _ in
                model.selectedBucket = nil
                model.reload(environment: environment, now: now)
            }
            // The bucket, not the date: scrubbing inside one bucket does not refilter the feed.
            .onChange(of: model.selectedBucket) { _, _ in
                model.reload(environment: environment, now: now)
            }
            // Overview's Outages shortcut and Availability "See All", on first appearance and later.
            .onChange(of: environment.router.pendingActivityFilter, initial: true) { _, filter in
                guard let filter else { return }
                model.filter = filter
                model.selectedBucket = nil
                environment.router.pendingActivityFilter = nil
            }
            .refreshable {
                now = Date()
                model.reload(environment: environment, now: now)
            }
        }
    }

    // MARK: - Since you last looked

    private var journalCard: some View {
        VStack(alignment: .leading, spacing: DSLayout.space4) {
            DSTitleRow("Since you last looked", qualifier: Formatters.relative(model.lastLookedAt, now: now)) {
                DSPillButton("Done") {
                    now = Date()
                    model.markLooked(environment: environment, now: now)
                }
                .accessibilityHint("Marks these changes as seen")
                .accessibilityIdentifier("activity.journalDone")
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.journal) { line in
                    journalRow(line)
                }
            }
        }
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity.journal")
    }

    /// A line opens its device when it names one. Plain, so it works apart from its list row; fixed label
    /// colours keep the button's tint off the text.
    @ViewBuilder
    private func journalRow(_ line: JournalLine) -> some View {
        let markWidth = model.journal.contains(where: { $0.kind == .newDevice }) ? badgeColumn : 18
        let content = HStack(spacing: DSLayout.space8) {
            journalMark(line.kind)
                .frame(width: markWidth, alignment: .leading)
            Text(line.text)
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if line.deviceID != nil {
                Image(systemName: "chevron.forward")
                    .font(DSTypography.rowSubtitle.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: DSLayout.minTapTarget)
        .contentShape(Rectangle())

        if let deviceID = line.deviceID {
            Button {
                environment.router.showDevice(deviceID)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the device")
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func journalMark(_ kind: JournalLine.Kind) -> some View {
        switch kind {
        case .newDevice: DSBadge(.new)
        case .outage, .wentOffline: StateSymbol(state: .offline)
        case .repeatedDrops: StateSymbol(state: .degraded)
        case .recovered: StateSymbol(state: .online)
        }
    }

    // MARK: - Devices online

    /// The range pills, the peak and low with the outages seen (or the picked bucket with Clear), the step
    /// chart, and the caption that says the history only holds what the app saw while open.
    private func onlineCard(_ density: ActivityDensity) -> some View {
        @Bindable var model = model
        let spokenRange = density.range == .day ? "last 24 hours" : "last 7 days"

        return VStack(alignment: .leading, spacing: 0) {
            DSTitleRow("Devices online", qualifier: Self.rangeTitle(model.range))
            DSSegmentedControl(
                TimelineRange.allCases,
                selection: $model.range,
                style: .outlined,
                fillsWidth: false,
                identifierPrefix: "activity.range",
                accessibilityLabel: "Time range",
                title: { Self.rangeTitle($0) }
            )
            .padding(.top, DSLayout.space12)
            onlineSummary(density)
                .padding(.top, DSLayout.space12)
            if let domain = ActivitySeries.domain(density) {
                DSAreaChart(
                    series: [ActivitySeries.online(density)],
                    domain: domain,
                    upperBound: ChartAxis.niceUpperBound(Double(density.peakOnline)),
                    unit: "devices",
                    xLabels: ChartAxis.labels(domain: domain, style: density.range == .day ? .hour : .weekday),
                    height: sizeClass == .regular ? 200 : 120,
                    interpolation: .step,
                    selection: pickedDate,
                    accessibilityLabel: "Devices online, \(spokenRange)",
                    accessibilityValue: onlineSpokenValue(density)
                )
                .accessibilityHint("Drag across the chart to filter the changes below.")
                .padding(.top, DSLayout.space12)
            }
            Text(AvailabilityNarrative.seenWhileOpenCaption)
                .font(DSTypography.axis)
                .foregroundStyle(DSColor.textSecondary)
                .padding(.top, 6)
            if sizeClass != .regular {
                DSLink(showsAddressMap ? "Hide address map" : "Show address map") {
                    showsAddressMap.toggle()
                }
                .accessibilityIdentifier("activity.showAddressMap")
                .padding(.top, DSLayout.space12)
            }
        }
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity.online")
    }

    /// The chart's selection. Only Clear removes a pick: a nil from the chart (a lifted finger) is ignored, so
    /// the feed stays on the picked bucket, as the bars did.
    private var pickedDate: Binding<Date?> {
        Binding(
            get: { model.selectedDate },
            set: { date in
                if let date {
                    model.selectedDate = date
                }
            }
        )
    }

    /// "Peak 13  Low 10 ……… 1 outage seen" (outages in the warn ink, as everywhere else), or the picked bucket,
    /// "3:00 PM · 12 online · 2 changes", with Clear. Both are 30 pt tall, so the chart below does not move.
    @ViewBuilder
    private func onlineSummary(_ density: ActivityDensity) -> some View {
        if let bucket = selectedBucket(in: density) {
            HStack(spacing: DSLayout.space12) {
                Text(readout(for: bucket, range: density.range))
                    .font(DSTypography.bodyValue)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: DSLayout.space8)
                DSPillButton("Clear") {
                    model.selectedDate = nil
                }
                .accessibilityLabel("Clear selection")
            }
            .frame(minHeight: 30)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: DSLayout.space12) {
                DSSummaryLine(rangeItems(density))
                Text(outagePhrase)
                    .font(DSTypography.body)
                    .foregroundStyle(model.outageCount == 0 ? DSColor.textSecondary : DSColor.degraded)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minHeight: 30)
            .accessibilityElement(children: .combine)
        }
    }

    private func selectedBucket(in density: ActivityDensity) -> ActivityDensity.Bucket? {
        guard let index = model.selectedBucket else { return nil }
        return density.buckets.first { $0.index == index }
    }

    private func rangeItems(_ density: ActivityDensity) -> [DSSummaryItem] {
        var items = [DSSummaryItem(id: "peak", label: "Peak", value: "\(density.peakOnline)")]
        if let low = lowestOnline(density) {
            items.append(DSSummaryItem(id: "low", label: "Low", value: "\(low)"))
        }
        return items
    }

    /// The fewest online in one bucket. Buckets from before the first device was seen count nobody, so they
    /// are left out.
    private func lowestOnline(_ density: ActivityDensity) -> Int? {
        guard let firstSeen = environment.directory.devices.map(\.firstSeen).min() else { return nil }
        return density.buckets.filter { $0.start >= firstSeen }.map(\.online).min()
    }

    /// A count, never a percentage: the app only sees outages while it is open.
    private var outagePhrase: String {
        model.outageCount == 0 ? "No outages seen" : "\(Formatters.count(model.outageCount, singular: "outage", plural: "outages")) seen"
    }

    /// "3:00 PM · 12 online · 2 changes".
    private func readout(for bucket: ActivityDensity.Bucket, range: TimelineRange) -> String {
        "\(bucketTime(bucket.start, range: range)) · \(bucket.online) online · \(Formatters.count(bucket.events, singular: "change", plural: "changes"))"
    }

    private func onlineSpokenValue(_ density: ActivityDensity) -> String {
        if let bucket = selectedBucket(in: density) {
            return readout(for: bucket, range: density.range)
        }
        let low = lowestOnline(density).map { ", low \($0)" } ?? ""
        return "Peak \(density.peakOnline)\(low), \(outagePhrase)"
    }

    /// "3:00 PM" in a day; "Mon 3:00 PM" in a week.
    private func bucketTime(_ date: Date, range: TimelineRange) -> String {
        range == .day ? date.formatted(date: .omitted, time: .shortened) : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// "24H" and "7D"; Core's `TimelineRange.title` reads "24 hours".
    private static func rangeTitle(_ range: TimelineRange) -> String {
        range == .day ? "24H" : "7D"
    }

    // MARK: - Address map

    private var addressMap: some View {
        SubnetHeatmapView(devices: environment.directory.devices, subnet: environment.currentSubnet) { id in
            environment.router.showDevice(id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity.addressMap")
    }

    // MARK: - Feed

    /// The device's flat kind well (or the event's glyph for the network), its name over the event's state
    /// symbol, word and address, and the time on the right. The well never shows the device's current state:
    /// the row is about the event. Device rows open the device.
    @ViewBuilder
    private func row(for entry: TimelineEntry) -> some View {
        let device = entry.deviceID.flatMap { environment.directory.device(id: $0) }
        let content = HStack(spacing: DSLayout.space12) {
            thumbnail(for: entry, device: device)
            VStack(alignment: .leading, spacing: DSLayout.space2) {
                Text(entry.title)
                    .font(DSTypography.rowTitle)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                subtitle(for: entry, device: device)
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: DSLayout.space8)
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(DSTypography.rowSecondaryValue)
                .foregroundStyle(DSColor.textSecondary)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)

        if let device {
            Button {
                environment.router.showDevice(device.id)
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    @ViewBuilder
    private func thumbnail(for entry: TimelineEntry, device: DeviceSnapshot?) -> some View {
        if let device {
            DeviceThumbnail(kind: device.kind, size: DSLayout.thumbnailRow, showsStateBadge: false)
        } else {
            DSThumbnail(systemImage: Self.symbol(for: entry.kind), size: DSLayout.thumbnailRow)
        }
    }

    /// "Went offline │ 192.168.178.52" after the event's state symbol; the address never truncates. At
    /// accessibility sizes the segments wrap as one line of text.
    @ViewBuilder
    private func subtitle(for entry: TimelineEntry, device: DeviceSnapshot?) -> some View {
        let segments = [Self.word(for: entry)] + (device.map { [$0.host] } ?? [])
        if dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                StateSymbol(state: Self.state(for: entry.kind), size: 11)
                Text(segments.joined(separator: " · "))
                    .lineLimit(3)
            }
            .font(DSTypography.rowSubtitle)
            .foregroundStyle(DSColor.textSecondary)
        } else {
            HStack(spacing: 5) {
                StateSymbol(state: Self.state(for: entry.kind), size: 11)
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Rectangle()
                            .fill(DSColor.hairline)
                            .frame(width: 1, height: 12)
                    }
                    Text(segment)
                        .layoutPriority(index == 1 ? 1 : 0)
                }
            }
            .font(DSTypography.rowSubtitle)
            .foregroundStyle(DSColor.textSecondary)
            .lineLimit(1)
        }
    }

    /// The event in a word for device rows; network rows say what happened, such as "Router stopped answering".
    private static func word(for entry: TimelineEntry) -> String {
        switch entry.kind {
        case .newDevice: return "Joined"
        case .left: return "Went offline"
        case .returned: return "Back online"
        case .outageStarted, .outageEnded: return entry.subtitle ?? entry.kind.title
        }
    }

    /// The state an event leaves behind: joining and coming back are online, leaving and outages offline.
    private static func state(for kind: TimelineEntry.Kind) -> ReachabilityState {
        switch kind {
        case .newDevice, .returned, .outageEnded: return .online
        case .left, .outageStarted: return .offline
        }
    }

    /// A network event's glyph; a device removed since shows the unknown kind.
    private static func symbol(for kind: TimelineEntry.Kind) -> String {
        switch kind {
        case .outageStarted: return "wifi.exclamationmark"
        case .outageEnded: return "wifi"
        case .newDevice, .left, .returned: return DeviceThumbnail.symbol(for: .unknown)
        }
    }

    private func sectionTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

private extension View {
    /// A List row that holds a card or a control on the page: no row background, insets or separator.
    func cardRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
    }
}

#Preview("Activity") {
    ActivityTimelineView()
        .environment(AppEnvironment.demo())
}
