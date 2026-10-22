import SwiftUI

/// A device's latency over 1, 6 or 24 hours: the quality word, the window pills, a summary line that is the
/// chart's legend (or the scrubbed point's readout), the chart, where the median sits on the latency range,
/// and three stats. Its words are `LatencyQuality`'s, relative to the device's own usual latency; the absolute
/// grades live only in the ⓘ popover.
struct LatencyCard: View {
    /// The last day of samples, oldest first.
    private let samples: [LatencySampleSnapshot]
    /// The word for the latest reading; nil while the device does not answer.
    private let quality: LatencyQuality?
    private let kind: DeviceKind
    /// Samples further apart than this break the lines.
    private let gapSeconds: TimeInterval
    private let now: Date

    @State private var window: LatencyWindow = .hour
    @State private var selectedDate: Date?
    @State private var showsInfo = false
    @State private var width: CGFloat = 0

    init(samples: [LatencySampleSnapshot], quality: LatencyQuality?, kind: DeviceKind, gapSeconds: TimeInterval, now: Date) {
        self.samples = samples
        self.quality = quality
        self.kind = kind
        self.gapSeconds = gapSeconds
        self.now = now
    }

    var body: some View {
        let series = LatencySeries.make(samples: samples, window: window, now: now, gapSeconds: gapSeconds)
        let hasChart = (series.summary?.count ?? 0) >= 2

        VStack(alignment: .leading, spacing: 0) {
            DSTitleRow("Latency", status: quality.map { DSStatusWord($0.title, tone: $0.tone) })
            DSSegmentedControl(
                LatencyWindow.allCases,
                selection: $window,
                style: .outlined,
                identifierPrefix: "detail.window",
                accessibilityLabel: "Time range",
                title: { $0.title }
            )
            .padding(.top, DSLayout.space12)
            if hasChart {
                summaryLine(series)
                    .padding(.top, DSLayout.space12)
                DSAreaChart(
                    series: [series.latency, series.jitter],
                    domain: series.domain,
                    upperBound: series.upperBound,
                    unit: "ms",
                    xLabels: ChartAxis.labels(domain: series.domain, style: window.axisStyle),
                    height: chartHeight,
                    selection: $selectedDate,
                    accessibilityLabel: "Latency, \(window.spokenTitle)",
                    accessibilityValue: spokenSummary(series)
                )
                .padding(.top, DSLayout.space12)
            } else {
                Text("No measurements in the \(window.spokenTitle). DeviceMonitor measures while it is open.")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                    .padding(.top, DSLayout.space12)
            }
            DSTitleRow("Latency range") {
                infoButton
            }
            .padding(.top, DSLayout.space16)
            DSGradientScale(
                scale: .latency,
                value: series.summary?.median,
                markerSymbol: DeviceThumbnail.symbol(for: kind),
                accessibilityLabel: "Latency range",
                accessibilityValue: series.summary.map { "Median \(Formatters.spokenLatency($0.median))" } ?? "No measurements"
            )
            .padding(.top, DSLayout.space12)
            if hasChart {
                stats(series)
                    .padding(.top, DSLayout.space12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .onChange(of: window) { _, _ in
            selectedDate = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.latencyCard")
    }

    /// 220 pt on cards of 600 pt and more, else 180.
    private var chartHeight: CGFloat {
        width >= 600 ? DSLayout.chartHeightRegular : DSLayout.chartHeightDetail
    }

    /// The one place the card states median, jitter and p95; while scrubbing, the selected point instead.
    @ViewBuilder
    private func summaryLine(_ series: LatencySeries) -> some View {
        if let selectedDate, let items = readout(at: selectedDate, in: series) {
            DSSummaryLine(items)
        } else if let summary = series.summary {
            DSSummaryLine(
                [
                    DSSummaryItem(id: "latency", label: "Latency", value: Formatters.latency(summary.median), tone: .latency, spokenValue: Formatters.spokenLatency(summary.median)),
                    DSSummaryItem(id: "jitter", label: "Jitter", value: Formatters.latency(summary.jitter), tone: .jitter, spokenValue: Formatters.spokenLatency(summary.jitter)),
                ],
                trailing: DSSummaryItem(id: "p95", label: "p95", value: Formatters.latency(summary.p95), spokenValue: Formatters.spokenLatency(summary.p95))
            )
        }
    }

    /// "8:14 PM  Latency 2.6 ms  Jitter 0.2 ms" for the plotted point nearest to `date`.
    private func readout(at date: Date, in series: LatencySeries) -> [DSSummaryItem]? {
        let answered = series.latency.points.filter { $0.value != nil }
        guard let nearest = answered.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
              let latency = nearest.value else { return nil }
        var items = [
            DSSummaryItem(id: "time", label: nearest.date.formatted(date: .omitted, time: .shortened), value: ""),
            DSSummaryItem(id: "latency", label: "Latency", value: Formatters.latency(latency), tone: .latency, spokenValue: Formatters.spokenLatency(latency)),
        ]
        if let jitter = series.jitter.points.first(where: { $0.date == nearest.date })?.value {
            items.append(DSSummaryItem(id: "jitter", label: "Jitter", value: Formatters.latency(jitter), tone: .jitter, spokenValue: Formatters.spokenLatency(jitter)))
        }
        return items
    }

    /// Worst, spikes and how much of the window was measured. Median, p95 and jitter are in the summary.
    private func stats(_ series: LatencySeries) -> some View {
        VStack(spacing: 0) {
            DSStatRow("Worst", value: series.worst.map { "\(Formatters.latency($0.milliseconds)) at \($0.date.formatted(date: .omitted, time: .shortened))" } ?? "—")
            DSStatRow("Spikes", value: spikesText(series), tone: series.spikeCount > 0 ? .warn : nil)
            DSStatRow("Measured", value: "\(Self.span(series.coveredSeconds)) of \(Self.span(window.seconds))", isLast: true)
        }
    }

    /// "2 above 3.5 ms", "None", or a dash before there is a usual range to compare with.
    private func spikesText(_ series: LatencySeries) -> String {
        guard let threshold = series.spikeThreshold else { return "—" }
        return series.spikeCount > 0 ? "\(series.spikeCount) above \(Formatters.latency(threshold))" : "None"
    }

    /// "Median 1.8 milliseconds, jitter 0.3 milliseconds, worst 6.1 milliseconds at 7:52 PM".
    private func spokenSummary(_ series: LatencySeries) -> String {
        guard let summary = series.summary else { return "No measurements" }
        var parts = [
            "Median \(Formatters.spokenLatency(summary.median))",
            "jitter \(Formatters.spokenLatency(summary.jitter))",
        ]
        if let worst = series.worst {
            parts.append("worst \(Formatters.spokenLatency(worst.milliseconds)) at \(worst.date.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: ", ")
    }

    /// Opens what the quality words and the latency range mean. The 44 pt hit area does not grow the title row.
    private var infoButton: some View {
        Button {
            showsInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(DSTypography.body)
                .foregroundStyle(.tint)
                .frame(minWidth: DSLayout.minTapTarget, minHeight: DSLayout.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -12)
        .accessibilityLabel("About latency range")
        .accessibilityIdentifier("detail.qualityInfo")
        .popover(isPresented: $showsInfo) {
            VStack(alignment: .leading, spacing: DSLayout.space12) {
                ForEach(LatencyQuality.allCases, id: \.self) { quality in
                    explanation(title: quality.title, tone: quality.tone, text: quality.explanation)
                }
                Text("Latency range")
                    .font(DSTypography.cardTitle)
                    .foregroundStyle(DSColor.textPrimary)
                    .padding(.top, DSLayout.space4)
                ForEach(LatencyGrade.allCases, id: \.self) { grade in
                    explanation(title: grade.title, tone: grade.tone, text: grade.explanation)
                }
            }
            .padding(DSLayout.space16)
            .frame(width: 300, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func explanation(title: String, tone: DSTone, text: String) -> some View {
        VStack(alignment: .leading, spacing: DSLayout.space2) {
            Text(title)
                .font(DSTypography.segmentSelected)
                .foregroundStyle(DSColor.ink(tone))
            Text(text)
                .font(DSTypography.rowSubtitle)
                .foregroundStyle(DSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// "58 min", "1 h", "5.6 h".
    private static func span(_ seconds: TimeInterval) -> String {
        if seconds < 3600 {
            return "\(Int((seconds / 60).rounded())) min"
        }
        let hours = seconds / 3600
        return hours.rounded() == hours ? "\(Int(hours)) h" : String(format: "%.1f h", hours)
    }
}

extension Formatters {
    /// `latency(_:)` for VoiceOver: "1.8 milliseconds", "1.2 seconds".
    nonisolated static func spokenLatency(_ milliseconds: Double?) -> String {
        let text = latency(milliseconds)
        guard let space = text.lastIndex(of: " ") else { return text }
        let unit = text[text.index(after: space)...] == "s" ? "seconds" : "milliseconds"
        return "\(text[..<space]) \(unit)"
    }
}

#Preview("Latency card") {
    let now = Date()
    let deviceID = UUID()
    let samples = (0..<120).map { index in
        LatencySampleSnapshot(
            id: UUID(),
            deviceID: deviceID,
            timestamp: now.addingTimeInterval(-30 * Double(119 - index)),
            milliseconds: 1.8 + Double(index % 7) * 0.1,
            probeKind: .tcp
        )
    }
    ScrollView {
        LatencyCard(samples: samples, quality: .fast, kind: .nas, gapSeconds: 120, now: now)
            .padding(DSLayout.space16)
    }
    .background {
        DSColor.background.ignoresSafeArea()
    }
}
