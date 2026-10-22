import Foundation

/// One plotted value; nil is a gap, which breaks the line and the area.
nonisolated struct DSChartPoint: Sendable, Hashable {
    let date: Date
    let value: Double?

    init(date: Date, value: Double?) {
        self.date = date
        self.value = value
    }
}

/// One series of an area chart. The tone names its colour; only the chart turns it into one.
nonisolated struct DSChartSeries: Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let tone: DSTone
    let points: [DSChartPoint]
    /// False draws a line only (jitter), so it never paints over the primary series' area.
    let fillsArea: Bool

    init(id: String, title: String, tone: DSTone, points: [DSChartPoint], fillsArea: Bool = true) {
        self.id = id
        self.title = title
        self.tone = tone
        self.points = points
        self.fillsArea = fillsArea
    }
}

/// An x-axis label at its date.
nonisolated struct DSChartLabel: Sendable, Hashable, Identifiable {
    let id: Int
    let date: Date
    let text: String

    init(id: Int, date: Date, text: String) {
        self.id = id
        self.date = date
        self.text = text
    }
}

/// Axis arithmetic shared by every chart, so the labels and the plot agree.
nonisolated enum ChartAxis {
    nonisolated enum Style: Sendable, Hashable {
        case clock, hour, weekday
    }

    /// `count` labels at equal fractions of the domain; the last reads "Now".
    static func labels(domain: ClosedRange<Date>, count: Int = 5, style: ChartAxis.Style) -> [DSChartLabel] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [DSChartLabel(id: 0, date: domain.upperBound, text: "Now")] }
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        return (0..<count).map { index in
            let date = domain.lowerBound.addingTimeInterval(span * Double(index) / Double(count - 1))
            let text = index == count - 1 ? "Now" : title(of: date, style: style)
            return DSChartLabel(id: index, date: date, text: text)
        }
    }

    /// `max(5, 1.15 × maximum)` rounded up to 1, 2 or 5 × 10ⁿ, so the ticks read 0, 2.5, 5 or 0, 5, 10.
    static func niceUpperBound(_ maximum: Double) -> Double {
        let target = max(5, maximum.isFinite ? maximum * 1.15 : 0)
        var magnitude = 1.0
        while magnitude * 10 < target {
            magnitude *= 10
        }
        for step in [1.0, 2, 5] where step * magnitude >= target {
            return step * magnitude
        }
        return 10 * magnitude
    }

    /// The three gridlines: the baseline, the middle and the top.
    static func ticks(upperBound: Double) -> [Double] {
        [0, upperBound / 2, upperBound]
    }

    private static func title(of date: Date, style: ChartAxis.Style) -> String {
        switch style {
        case .clock: return date.formatted(date: .omitted, time: .shortened)
        case .hour: return date.formatted(.dateTime.hour())
        case .weekday: return date.formatted(.dateTime.weekday(.abbreviated))
        }
    }
}

/// The windows the latency store can fill: at most 720 samples per device, kept for a day at most.
nonisolated enum LatencyWindow: String, Sendable, Hashable, CaseIterable {
    case hour, sixHours, day

    var title: String {
        switch self {
        case .hour: return "1H"
        case .sixHours: return "6H"
        case .day: return "24H"
        }
    }

    var spokenTitle: String {
        switch self {
        case .hour: return "last hour"
        case .sixHours: return "last 6 hours"
        case .day: return "last 24 hours"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .hour: return 3_600
        case .sixHours: return 21_600
        case .day: return 86_400
        }
    }

    /// 0 plots every sample; otherwise one median per bucket.
    var bucketSeconds: TimeInterval {
        switch self {
        case .hour: return 0
        case .sixHours: return 120
        case .day: return 600
        }
    }

    var axisStyle: ChartAxis.Style {
        switch self {
        case .hour, .sixHours: return .clock
        case .day: return .hour
        }
    }
}

/// A device's latency over a window, ready to plot: latency and jitter series broken at gaps, and the
/// statistics the card states once.
nonisolated struct LatencySeries: Sendable, Hashable {
    nonisolated struct Sample: Sendable, Hashable {
        let date: Date
        let milliseconds: Double
    }

    let window: LatencyWindow
    let domain: ClosedRange<Date>
    let latency: DSChartSeries
    /// 1H: the rolling mean of the last five |Δ| inside a run, so one spike draws one bump.
    let jitter: DSChartSeries
    let upperBound: Double
    let summary: LatencySummary?
    let spikeThreshold: Double?
    let spikeCount: Int
    let worst: LatencySeries.Sample?
    /// Window seconds in sixtieths that hold a sample or lie inside a run: "Measured 58 min of 1 h".
    let coveredSeconds: TimeInterval

    /// Differences averaged by the 1H jitter line.
    private static let jitterWindow = 5
    /// Slices the window is cut into for `coveredSeconds`.
    private static let coverageSlices = 60

    /// `gapSeconds`: two consecutive samples further apart than this break both lines (callers pass
    /// `max(3 × interval, 120)`).
    static func make(samples: [LatencySampleSnapshot], window: LatencyWindow, now: Date, gapSeconds: TimeInterval) -> LatencySeries {
        let lower = now.addingTimeInterval(-window.seconds)
        let kept = samples
            .filter { $0.timestamp >= lower && $0.timestamp <= now && $0.milliseconds.isFinite && $0.milliseconds >= 0 }
            .sorted { $0.timestamp < $1.timestamp }
            .map { Sample(date: $0.timestamp, milliseconds: $0.milliseconds) }
        let values = kept.map(\.milliseconds)

        let threshold = LatencyNarrative.typicalBand(values).map { LatencyNarrative.spikeThreshold(for: $0) }
        let points = window.bucketSeconds > 0
            ? bucketPoints(kept, lower: lower, window: window, gapSeconds: gapSeconds)
            : samplePoints(kept, gapSeconds: gapSeconds)
        let plotted = (points.latency + points.jitter).compactMap(\.value)

        return LatencySeries(
            window: window,
            domain: lower...now,
            latency: DSChartSeries(id: "latency", title: "Latency", tone: .latency, points: points.latency),
            jitter: DSChartSeries(id: "jitter", title: "Jitter", tone: .jitter, points: points.jitter, fillsArea: false),
            upperBound: ChartAxis.niceUpperBound(plotted.max() ?? 0),
            summary: LatencySummary(samples: values),
            spikeThreshold: threshold,
            spikeCount: threshold.map { limit in values.filter { $0 > limit }.count } ?? 0,
            worst: kept.max { $0.milliseconds < $1.milliseconds },
            coveredSeconds: coverage(of: kept, lower: lower, window: window, gapSeconds: gapSeconds)
        )
    }

    /// One latency point per sample. Jitter at a sample is the mean of the last up to five |Δ| of its run
    /// (nil for a run's first sample). A nil point between samples more than `gapSeconds` apart breaks
    /// both series and restarts the jitter window.
    private static func samplePoints(_ samples: [Sample], gapSeconds: TimeInterval) -> (latency: [DSChartPoint], jitter: [DSChartPoint]) {
        var latency: [DSChartPoint] = []
        var jitter: [DSChartPoint] = []
        var differences: [Double] = []
        var previous: Sample?
        for sample in samples {
            if let last = previous, sample.date.timeIntervalSince(last.date) <= gapSeconds {
                differences.append(abs(sample.milliseconds - last.milliseconds))
                if differences.count > jitterWindow {
                    differences.removeFirst()
                }
                jitter.append(DSChartPoint(date: sample.date, value: differences.reduce(0, +) / Double(differences.count)))
            } else {
                if let last = previous {
                    let gap = DSChartPoint(date: midpoint(last.date, sample.date), value: nil)
                    latency.append(gap)
                    jitter.append(gap)
                }
                differences.removeAll()
                jitter.append(DSChartPoint(date: sample.date, value: nil))
            }
            latency.append(DSChartPoint(date: sample.date, value: sample.milliseconds))
            previous = sample
        }
        return (latency, jitter)
    }

    /// One point per bucket that holds samples, at its midpoint: the nearest-rank median, and the mean |Δ| of
    /// consecutive samples inside the bucket (no jitter point with one sample). Buckets that a slow check
    /// interval leaves empty are skipped, so the lines stay whole; a nil point breaks both lines only where
    /// consecutive samples lie more than `gapSeconds` apart, and such a pair never counts as jitter.
    private static func bucketPoints(_ samples: [Sample], lower: Date, window: LatencyWindow, gapSeconds: TimeInterval) -> (latency: [DSChartPoint], jitter: [DSChartPoint]) {
        let width = window.bucketSeconds
        let count = Int((window.seconds / width).rounded())
        var buckets = Array(repeating: [Sample](), count: count)
        for sample in samples {
            let index = min(max(Int(sample.date.timeIntervalSince(lower) / width), 0), count - 1)
            buckets[index].append(sample)
        }

        var latency: [DSChartPoint] = []
        var jitter: [DSChartPoint] = []
        var previous: Sample?
        for (index, bucket) in buckets.enumerated() {
            guard let first = bucket.first, let last = bucket.last else { continue }
            let start = lower.addingTimeInterval(Double(index) * width)
            if let previous, first.date.timeIntervalSince(previous.date) > gapSeconds {
                let gap = DSChartPoint(date: start, value: nil)
                latency.append(gap)
                jitter.append(gap)
            }
            let middle = start.addingTimeInterval(width / 2)
            latency.append(DSChartPoint(date: middle, value: LatencySummary.nearestRank(bucket.map(\.milliseconds).sorted(), percentile: 0.5)))
            let differences = zip(bucket, bucket.dropFirst())
                .filter { $1.date.timeIntervalSince($0.date) <= gapSeconds }
                .map { abs($1.milliseconds - $0.milliseconds) }
            if !differences.isEmpty {
                jitter.append(DSChartPoint(date: middle, value: differences.reduce(0, +) / Double(differences.count)))
            }
            previous = last
        }
        return (latency, jitter)
    }

    /// Slices that hold a sample or lie between two consecutive samples no more than `gapSeconds` apart, so a
    /// slow check interval still reads as measured and only real gaps count as missing.
    private static func coverage(of samples: [Sample], lower: Date, window: LatencyWindow, gapSeconds: TimeInterval) -> TimeInterval {
        let slice = window.seconds / Double(coverageSlices)
        let slices = samples.map { min(max(Int($0.date.timeIntervalSince(lower) / slice), 0), coverageSlices - 1) }
        var filled = Set(slices)
        // `samples` is in time order, so the slices never decrease.
        for index in slices.indices.dropFirst() where samples[index].date.timeIntervalSince(samples[index - 1].date) <= gapSeconds {
            filled.formUnion(slices[index - 1]...slices[index])
        }
        return Double(filled.count) / Double(coverageSlices) * window.seconds
    }

    private static func midpoint(_ start: Date, _ end: Date) -> Date {
        start.addingTimeInterval(end.timeIntervalSince(start) / 2)
    }
}

/// The spans an availability strip offers: hourly cells for a day, daily cells for 30 or 90 days.
nonisolated enum AvailabilityRange: String, Sendable, Hashable, CaseIterable {
    case day, month, quarter

    var title: String {
        switch self {
        case .day: return "24H"
        case .month: return "30D"
        case .quarter: return "90D"
        }
    }

    var leadingCaption: String {
        switch self {
        case .day: return "24h ago"
        case .month: return "30 days ago"
        case .quarter: return "90 days ago"
        }
    }

    var trailingCaption: String {
        switch self {
        case .day: return "Now"
        case .month, .quarter: return "Today"
        }
    }
}

/// "Devices online" as a chart series.
nonisolated enum ActivitySeries {
    /// One point per bucket at its midpoint: the devices online at the bucket's start.
    static func online(_ density: ActivityDensity) -> DSChartSeries {
        let points = density.buckets.map { bucket in
            DSChartPoint(date: bucket.start.addingTimeInterval(bucket.end.timeIntervalSince(bucket.start) / 2), value: Double(bucket.online))
        }
        return DSChartSeries(id: "online", title: "Online", tone: .good, points: points)
    }

    static func domain(_ density: ActivityDensity) -> ClosedRange<Date>? {
        guard let first = density.buckets.first, let last = density.buckets.last, first.start <= last.end else { return nil }
        return first.start...last.end
    }
}
