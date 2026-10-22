import SwiftUI
import UIKit

/// Result of a five-probe burst: how many answered and the loss, one bar per probe, then min, average and max.
struct PingCard: View {
    private let samples: [PingSample]

    private static let probeCount = 5

    init(samples: [PingSample]) {
        self.samples = samples
    }

    var body: some View {
        let summary = PingSummary(samples: samples)

        VStack(alignment: .leading, spacing: 0) {
            DSTitleRow("Ping", qualifier: "\(Self.probeCount) probes")
            if summary.sent > 0 {
                DSSummaryLine(
                    [DSSummaryItem(id: "answered", label: "Answered", value: "\(summary.received) of \(summary.sent)")],
                    trailing: DSSummaryItem(id: "loss", label: "Loss", value: Formatters.percent(summary.loss), tone: summary.loss > 0 ? .bad : nil)
                )
                .padding(.top, DSLayout.space12)
            } else {
                Text("Pinging…")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.top, DSLayout.space12)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(1...Self.probeCount, id: \.self) { index in
                    bar(for: samples.first { $0.index == index }, maximum: summary.maximum ?? 1)
                }
            }
            .frame(height: 56)
            .padding(.top, DSLayout.space12)
            .accessibilityHidden(true)
            if summary.sent > 0 {
                VStack(spacing: 0) {
                    DSStatRow("Min", value: Formatters.latency(summary.minimum))
                    DSStatRow("Avg", value: Formatters.latency(summary.average))
                    DSStatRow("Max", value: Formatters.latency(summary.maximum), isLast: true)
                }
                .padding(.top, DSLayout.space12)
            }
            if let kind = samples.first?.kind {
                Text("Sent with \(kind == .icmp ? "ICMP" : kind.title). Results do not change the device's status.")
                    .font(DSTypography.rowSubtitle)
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DSLayout.space12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.pingResult")
    }

    /// The latency colour for an answer, the offline fill for a lost probe, no data while it is pending. Bars
    /// have rounded tops and a square baseline.
    private func bar(for sample: PingSample?, maximum: Double) -> some View {
        let fraction: Double = {
            guard let latency = sample?.outcome.latencyMilliseconds, sample?.outcome.indicatesHostUp == true else { return 0.08 }
            return max(0.12, min(1, latency / max(maximum, 0.1)))
        }()
        let color: Color = {
            guard let sample else { return DSColor.noData }
            return sample.outcome.indicatesHostUp ? DSColor.latency : DSColor.offlineFill
        }()
        return GeometryReader { proxy in
            let height = proxy.size.height * fraction
            Path(
                roundedRect: CGRect(x: 0, y: proxy.size.height - height, width: proxy.size.width, height: height),
                cornerRadii: RectangleCornerRadii(topLeading: 3, bottomLeading: 0, bottomTrailing: 0, topTrailing: 3)
            )
            .fill(color)
        }
    }
}

/// Outages over 24 hours, 30 or 90 days as a status-page strip: counts and down time, never a percentage,
/// because the app only sees changes while it is open.
struct AvailabilityCard: View {
    private let device: DeviceSnapshot
    private let events: [StatusEventSnapshot]
    private let now: Date

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var range: AvailabilityRange = .month

    init(device: DeviceSnapshot, events: [StatusEventSnapshot], now: Date) {
        self.device = device
        self.events = events
        self.now = now
    }

    var body: some View {
        let cells = self.cells
        let summary = AvailabilityNarrative.summary(cells: cells)

        VStack(alignment: .leading, spacing: 0) {
            DSTitleRow("Availability", qualifier: range.title, status: statusWord(cells))
            DSSegmentedControl(
                AvailabilityRange.allCases,
                selection: $range,
                style: .outlined,
                identifierPrefix: "detail.availability",
                accessibilityLabel: "Time range",
                title: { $0.title }
            )
            .padding(.top, DSLayout.space12)
            DSSummaryLine(summary.items, trailing: summary.trailing)
                .padding(.top, DSLayout.space12)
            UptimeStripView(
                title: "Availability, \(spokenRange)",
                cells: cells,
                leadingCaption: range.leadingCaption,
                trailingCaption: range.trailingCaption
            )
            .accessibilityIdentifier("detail.availabilityStrip")
            .padding(.top, DSLayout.space12)
            FlowLayout(spacing: DSLayout.space12) {
                ForEach(UptimeState.allCases, id: \.self) { state in
                    DSLegendSwatch(
                        color: DSColor.fill(forUptime: state),
                        title: state.title,
                        isHatched: state == .offline && differentiateWithoutColor,
                        isShort: state == .noData
                    )
                }
            }
            .padding(.top, DSLayout.space12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.availabilityCard")
    }

    /// Hourly cells for a day, daily cells for 30 or 90 days.
    private var cells: [UptimeCell] {
        switch range {
        case .day:
            return UptimeCells.recent(count: 24, span: 86_400, events: events, currentState: device.state, firstSeen: device.firstSeen, now: now)
        case .month:
            return UptimeCells.days(count: 30, events: events, currentState: device.state, firstSeen: device.firstSeen, now: now)
        case .quarter:
            return UptimeCells.days(count: 90, events: events, currentState: device.state, firstSeen: device.firstSeen, now: now)
        }
    }

    /// "Down now" while the device is offline, otherwise the outages seen in the range.
    private func statusWord(_ cells: [UptimeCell]) -> DSStatusWord {
        device.state == .offline
            ? DSStatusWord("Down now", tone: .bad)
            : AvailabilityNarrative.statusWord(cells: cells, isGatewayDown: false)
    }

    private var spokenRange: String {
        switch range {
        case .day: return "last 24 hours"
        case .month: return "last 30 days"
        case .quarter: return "last 90 days"
        }
    }
}

/// The on-device explanation of what the device is. The Apple Intelligence symbol appears only on the
/// source line of a generated text, unmodified in the secondary colour, because `apple.intelligence` is a
/// restricted symbol.
struct AboutDeviceCard: View {
    /// nil while the explanation is being written.
    private let insight: DeviceInsight?

    init(insight: DeviceInsight?) {
        self.insight = insight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSLayout.space12) {
            if let insight {
                DSTitleRow(insight.headline)
                Text(insight.body)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Group {
                    if insight.source == .onDeviceModel {
                        Label("Written on this iPhone with Apple Intelligence", systemImage: "apple.intelligence")
                    } else {
                        Text("Based on the services and ports this device exposes")
                    }
                }
                .font(DSTypography.rowSubtitle)
                .foregroundStyle(DSColor.textSecondary)
            } else {
                DSTitleRow("About this device")
                HStack(spacing: DSLayout.space8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Thinking it over…")
                        .font(DSTypography.body)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }
}

/// State changes, newest first: five, then all the loaded ones on request.
struct ConnectionLogCard: View {
    private let entries: [ConnectionLogEntry]

    @Environment(\.displayScale) private var displayScale
    @State private var showsAll = false

    private static let collapsedCount = 5
    /// The state symbol's column, so titles line up whatever the glyph's width.
    private static let symbolColumn: CGFloat = 20

    init(entries: [ConnectionLogEntry]) {
        self.entries = entries
    }

    var body: some View {
        let shown = showsAll ? entries : Array(entries.prefix(Self.collapsedCount))

        VStack(alignment: .leading, spacing: 0) {
            DSTitleRow("Connection log", qualifier: "(\(entries.count))")
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                    row(entry, isLast: index == shown.count - 1)
                }
            }
            .padding(.top, DSLayout.space4)
            if entries.count > Self.collapsedCount {
                DSLink(showsAll ? "Show Less" : "Show All (\(entries.count))") {
                    showsAll.toggle()
                }
                .accessibilityIdentifier("detail.log.showAll")
                .padding(.top, DSLayout.space12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.log")
    }

    private func row(_ entry: ConnectionLogEntry, isLast: Bool) -> some View {
        HStack(alignment: .center, spacing: DSLayout.space12) {
            StateSymbol(state: entry.state, size: 16)
                .frame(width: Self.symbolColumn)
            VStack(alignment: .leading, spacing: DSLayout.space2) {
                Text(entry.title)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textPrimary)
                DetailSegments(entry.detail)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DSLayout.space8)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(DSColor.hairline)
                    .frame(height: 1 / displayScale)
                    .padding(.leading, Self.symbolColumn + DSLayout.space12)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Every fact the app holds about the device, label on the left and value on the right; the address,
/// hostname and MAC can be copied.
struct DeviceDetailsCard: View {
    private let device: DeviceSnapshot
    private let now: Date

    @Environment(\.displayScale) private var displayScale
    /// The row whose value was just copied; its copy glyph shows a checkmark for a moment.
    @State private var copiedField: String?

    init(device: DeviceSnapshot, now: Date) {
        self.device = device
        self.now = now
    }

    private struct Fact: Identifiable {
        let label: String
        let value: String
        let isCopyable: Bool

        var id: String { label }
    }

    private var facts: [Fact] {
        var facts = [Fact(label: "Address", value: device.host, isCopyable: true)]
        if let hostname = device.hostname, !hostname.isEmpty {
            facts.append(Fact(label: "Hostname", value: hostname, isCopyable: true))
        }
        if let mac = device.macAddress, !mac.isEmpty {
            facts.append(Fact(label: "MAC", value: mac, isCopyable: true))
        }
        if let vendor = device.vendor, !vendor.isEmpty {
            facts.append(Fact(label: "Vendor", value: vendor, isCopyable: false))
        }
        facts.append(Fact(label: "Kind", value: device.kind.title, isCopyable: false))
        facts.append(Fact(label: "Confidence", value: Formatters.percent(device.confidence), isCopyable: false))
        facts.append(Fact(label: "First seen", value: Formatters.relative(device.firstSeen, now: now), isCopyable: false))
        facts.append(Fact(label: "Last checked", value: Formatters.relative(device.lastChecked, now: now), isCopyable: false))
        if !device.tags.isEmpty {
            facts.append(Fact(label: "Tags", value: device.tags.joined(separator: ", "), isCopyable: false))
        }
        facts.append(Fact(label: "Source", value: device.isUserAdded ? "Added by you" : "Discovered", isCopyable: false))
        return facts
    }

    var body: some View {
        let facts = self.facts

        VStack(alignment: .leading, spacing: 0) {
            DSTitleRow("Details")
            VStack(spacing: 0) {
                ForEach(facts) { fact in
                    row(fact, isLast: fact.id == facts.last?.id)
                }
            }
            .padding(.top, DSLayout.space4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .task(id: copiedField) {
            guard copiedField != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copiedField = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.details")
    }

    /// A 40 pt row; the copy button's 44 pt hit area reaches into the rows around it instead of growing this one.
    private func row(_ fact: Fact, isLast: Bool) -> some View {
        HStack(alignment: .center, spacing: DSLayout.space8) {
            Text(fact.label)
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
            Spacer(minLength: DSLayout.space12)
            Text(fact.value)
                .font(DSTypography.bodyValue)
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
            if fact.isCopyable {
                Button {
                    UIPasteboard.general.string = fact.value
                    copiedField = fact.label
                } label: {
                    Image(systemName: copiedField == fact.label ? "checkmark" : "document.on.document")
                        .contentTransition(.symbolEffect(.replace))
                        .font(DSTypography.rowSubtitle)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(width: DSLayout.minTapTarget, height: DSLayout.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -12)
                .padding(.vertical, -2)
                .accessibilityLabel("Copy \(fact.label)")
                .accessibilityValue(copiedField == fact.label ? "Copied" : "")
            }
        }
        .frame(minHeight: DSLayout.statRowHeight)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(DSColor.hairline)
                    .frame(height: 1 / displayScale)
            }
        }
    }
}

/// The user's notes about the device.
struct NotesCard: View {
    private let notes: String

    init(notes: String) {
        self.notes = notes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSLayout.space12) {
            DSTitleRow("Notes")
            Text(notes)
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }
}

/// A row subtitle in segments split by hairline dividers ("445 │ TCP │ File sharing"), as in device rows. The
/// first segment never truncates; at accessibility sizes the segments wrap as one line of text.
struct DetailSegments: View {
    private let segments: [String]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ segments: [String]) {
        self.segments = segments
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Text(segments.joined(separator: " · "))
                    .lineLimit(3)
            } else {
                HStack(spacing: 5) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        if index > 0 {
                            Rectangle()
                                .fill(DSColor.hairline)
                                .frame(width: 1, height: 12)
                        }
                        Text(segment)
                            .layoutPriority(index == 0 ? 1 : 0)
                    }
                }
                .lineLimit(1)
            }
        }
        .font(DSTypography.rowSubtitle)
        .foregroundStyle(DSColor.textSecondary)
    }
}
