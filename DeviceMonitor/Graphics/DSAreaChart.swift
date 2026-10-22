import SwiftUI
import Charts
import Accessibility

nonisolated enum DSChartInterpolation: Sendable, Hashable {
    case smooth, step
}

/// The app's one chart: thin series lines over a quiet gradient, three dashed hairline gridlines with
/// their values inside the plot, the unit above it and the time labels under it, "Now" last. Gaps in a
/// series are drawn as gaps. Swift Charts draws the marks; plain SwiftUI draws the labels, so they sit
/// exactly on their gridlines. The whole chart is one VoiceOver element with an Audio Graph.
struct DSAreaChart: View {
    let series: [DSChartSeries]
    let domain: ClosedRange<Date>
    let upperBound: Double
    let unit: String
    let xLabels: [DSChartLabel]
    let height: CGFloat
    let interpolation: DSChartInterpolation
    let selection: Binding<Date?>?
    let accessibilityLabel: String
    let accessibilityValue: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    /// Used only when the caller passes no selection binding.
    @State private var ownSelection: Date?
    @State private var width: CGFloat = 0

    /// Room above the top gridline for its value label.
    private static let topLabelSpace: CGFloat = 16
    /// Width of the fade-in on the oldest data.
    private static let fadeWidth: CGFloat = 40

    init(
        series: [DSChartSeries],
        domain: ClosedRange<Date>,
        upperBound: Double,
        unit: String,
        xLabels: [DSChartLabel],
        height: CGFloat,
        interpolation: DSChartInterpolation = .smooth,
        selection: Binding<Date?>? = nil,
        accessibilityLabel: String,
        accessibilityValue: String
    ) {
        self.series = series
        self.domain = domain
        self.upperBound = upperBound
        self.unit = unit
        self.xLabels = xLabels
        self.height = height
        self.interpolation = interpolation
        self.selection = selection
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
    }

    private var selectionBinding: Binding<Date?> {
        selection ?? $ownSelection
    }

    /// The y domain's top: the top gridline then sits `topLabelSpace` under the plot's top edge.
    private var plotTop: Double {
        let upper = upperBound > 0 ? upperBound : 1
        return upper * Double(height) / Double(max(height - Self.topLabelSpace, 1))
    }

    var body: some View {
        let marks = PlotMarks(series: series)
        let selected = marks.nearestDate(to: selectionBinding.wrappedValue)

        VStack(alignment: .leading, spacing: 0) {
            Text(unit)
                .font(DSTypography.axis)
                .foregroundStyle(DSColor.textSecondary)
                .padding(.bottom, DSLayout.space4)
            plot(marks: marks, selected: selected)
                .frame(height: height)
                .mask {
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0), .init(color: .black, location: fadeEnd)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .overlay(alignment: .topLeading) {
                    yLabels
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newWidth in
                    width = newWidth
                }
                .contentShape(Rectangle())
                .gesture(HorizontalScrub(onChanged: { x in
                    selectionBinding.wrappedValue = date(atX: x)
                }, onEnded: {
                    selectionBinding.wrappedValue = nil
                }))
                // A tap is a scrub that ends where it starts: a caller that keeps its pick on release (Activity)
                // picks the tapped time.
                .onTapGesture { location in
                    selectionBinding.wrappedValue = date(atX: location.x)
                    selectionBinding.wrappedValue = nil
                }
            AxisLabelsLayout(positions: xLabels.map { position(of: $0.date) }, pinsEnds: true) {
                ForEach(xLabels) { label in
                    Text(label.text)
                        .font(DSTypography.axis)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 3)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityChartDescriptor(DSChartDescriptor(
            title: accessibilityLabel,
            summary: accessibilityValue,
            unit: unit,
            domain: domain,
            upperBound: upperBound,
            series: series
        ))
    }

    private func plot(marks: PlotMarks, selected: Date?) -> some View {
        let method: InterpolationMethod = interpolation == .step ? .stepCenter : .monotone
        let inks = series.map { DSColor.fill($0.tone) }
        let opacity = areaOpacity
        let areaStyles = inks.map { ink in
            LinearGradient(colors: [ink.opacity(opacity.top), ink.opacity(opacity.bottom)], startPoint: .top, endPoint: .bottom)
        }
        let hairline = 1 / max(displayScale, 1)
        let gridTicks = ChartAxis.ticks(upperBound: upperBound)
        let interiorLabels = Array(xLabels.dropFirst().dropLast())
        let selectedPoints = selected.map { marks.points(at: $0) } ?? []

        return Chart {
            ForEach(gridTicks, id: \.self) { tick in
                RuleMark(y: .value("Grid", tick))
                    .lineStyle(StrokeStyle(lineWidth: hairline, dash: [2.7, 1.3]))
                    .foregroundStyle(DSColor.grid)
            }
            ForEach(interiorLabels) { label in
                RuleMark(x: .value("Tick", label.date))
                    .lineStyle(StrokeStyle(lineWidth: hairline, dash: [2, 1.3]))
                    .foregroundStyle(DSColor.grid)
            }
            if let selected {
                RuleMark(x: .value("Selected", selected))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(DSColor.textTertiary)
            }
            ForEach(marks.areas) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    yStart: .value("Base", 0.0),
                    yEnd: .value("Value", point.value),
                    series: .value("Run", point.run)
                )
                .interpolationMethod(method)
                .foregroundStyle(areaStyles[point.seriesIndex])
                .alignsMarkStylesWithPlotArea()
            }
            ForEach(marks.lines) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value),
                    series: .value("Run", point.run)
                )
                .interpolationMethod(method)
                .foregroundStyle(inks[point.seriesIndex])
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(marks.dots) { point in
                PointMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(inks[point.seriesIndex])
                .symbolSize(9)
            }
            ForEach(selectedPoints) { point in
                PointMark(
                    x: .value("Selected", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(DSColor.card)
                .symbolSize(64)
                PointMark(
                    x: .value("Selected", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(inks[point.seriesIndex])
                .symbolSize(25)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...plotTop)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }

    /// The gridline values at x 0, each 2 pt above its line. They let touches through, so scrubbing works
    /// at the leading edge too.
    private var yLabels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(ChartAxis.ticks(upperBound: upperBound), id: \.self) { tick in
                Text(yLabel(tick))
                    .font(DSTypography.axis)
                    .foregroundStyle(DSColor.textTertiary)
                    .frame(height: max(0, height * CGFloat(1 - tick / plotTop) - 2), alignment: .bottomLeading)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// No decimals, except a fractional middle tick on a small scale ("2.5").
    private func yLabel(_ tick: Double) -> String {
        let decimals = upperBound <= 10 && tick.rounded() != tick ? 1 : 0
        return tick.formatted(.number.precision(.fractionLength(decimals)))
    }

    /// 0...1 across the domain.
    private func position(of date: Date) -> Double {
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard span > 0 else { return 0 }
        return date.timeIntervalSince(domain.lowerBound) / span
    }

    /// The date under `x` in the plot, the inverse of `position(of:)`: the hidden axes leave the plot the full width.
    private func date(atX x: CGFloat) -> Date {
        let fraction = width > 0 ? min(max(Double(x / width), 0), 1) : 0
        return domain.lowerBound.addingTimeInterval(domain.upperBound.timeIntervalSince(domain.lowerBound) * fraction)
    }

    private var fadeEnd: CGFloat {
        width > 0 ? min(0.3, Self.fadeWidth / width) : 0.3
    }

    /// Series alpha at the plot top and at the baseline.
    private var areaOpacity: (top: Double, bottom: Double) {
        switch (colorScheme == .dark, contrast == .increased) {
        case (true, false): return (0.40, 0.06)
        case (false, false): return (0.22, 0.03)
        case (true, true): return (0.50, 0.10)
        case (false, true): return (0.30, 0.06)
        }
    }
}

/// One plotted value with the run it belongs to: a run is a stretch of a series without gaps.
nonisolated private struct PlotPoint: Sendable, Hashable, Identifiable {
    let id: Int
    let seriesIndex: Int
    let run: String
    let date: Date
    let value: Double
}

/// The marks of a chart: each series split at its nil points into runs, so lines and areas break at gaps.
/// Runs of one point are drawn as dots; areas only for series that fill.
nonisolated private struct PlotMarks: Sendable {
    private(set) var areas: [PlotPoint] = []
    private(set) var lines: [PlotPoint] = []
    private(set) var dots: [PlotPoint] = []

    init(series: [DSChartSeries]) {
        var nextID = 0
        for (seriesIndex, item) in series.enumerated() {
            for (runIndex, run) in Self.runs(of: item.points).enumerated() {
                var points: [PlotPoint] = []
                for (date, value) in run {
                    points.append(PlotPoint(id: nextID, seriesIndex: seriesIndex, run: "\(item.id)#\(runIndex)", date: date, value: value))
                    nextID += 1
                }
                if points.count == 1 {
                    dots += points
                } else {
                    lines += points
                    if item.fillsArea {
                        areas += points
                    }
                }
            }
        }
    }

    /// Consecutive finite values, split at every nil.
    private static func runs(of points: [DSChartPoint]) -> [[(date: Date, value: Double)]] {
        var runs: [[(date: Date, value: Double)]] = []
        var current: [(date: Date, value: Double)] = []
        for point in points {
            if let value = point.value, value.isFinite {
                current.append((date: point.date, value: value))
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            runs.append(current)
        }
        return runs
    }

    /// The plotted date nearest to `date`, across every series.
    func nearestDate(to date: Date?) -> Date? {
        guard let date else { return nil }
        return (lines + dots)
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?
            .date
    }

    /// Every series' point at exactly `date`.
    func points(at date: Date) -> [PlotPoint] {
        (lines + dots).filter { $0.date == date }
    }
}

/// Labels along an axis, each centred on its position (0...1) and kept inside the bounds. With `pinsEnds`
/// the first label starts at the leading edge and the last ends at the trailing edge, so neither hangs.
struct AxisLabelsLayout: Layout {
    let positions: [Double]
    let pinsEnds: Bool

    init(positions: [Double], pinsEnds: Bool) {
        self.positions = positions
        self.pinsEnds = pinsEnds
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let height = sizes.map(\.height).max() ?? 0
        return CGSize(width: proposal.width ?? sizes.map(\.width).reduce(0, +), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // A lone label ("Now") keeps its own position instead of being pinned to the leading edge.
        let pins = pinsEnds && subviews.count > 1
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let x: CGFloat
            if pins && index == subviews.startIndex {
                x = bounds.minX
            } else if pins && index == subviews.endIndex - 1 {
                x = bounds.maxX - size.width
            } else {
                let fraction = positions.indices.contains(index) ? min(max(positions[index], 0), 1) : 0
                let centred = bounds.minX + bounds.width * CGFloat(fraction) - size.width / 2
                x = min(max(centred, bounds.minX), bounds.maxX - size.width)
            }
            subviews[index].place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(size))
        }
    }
}

/// The chart for VoiceOver's Audio Graph: time in seconds from the domain's start, values in the unit.
nonisolated struct DSChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let summary: String
    let unit: String
    let domain: ClosedRange<Date>
    let upperBound: Double
    let series: [DSChartSeries]

    func makeChartDescriptor() -> AXChartDescriptor {
        let start = domain.lowerBound
        let span = max(domain.upperBound.timeIntervalSince(start), 0)
        let xAxis = AXNumericDataAxisDescriptor(title: "Time", range: 0...span, gridlinePositions: []) { seconds in
            start.addingTimeInterval(seconds).formatted(date: .omitted, time: .shortened)
        }
        let yAxis = AXNumericDataAxisDescriptor(title: unit, range: 0...max(upperBound, 0), gridlinePositions: ChartAxis.ticks(upperBound: upperBound)) { [unit] value in
            "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
        }
        let data = series.map { item in
            AXDataSeriesDescriptor(name: item.title, isContinuous: true, dataPoints: item.points.compactMap { point in
                point.value.map { AXDataPoint(x: point.date.timeIntervalSince(start), y: $0) }
            })
        }
        return AXChartDescriptor(title: title, summary: summary, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: data)
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {}
}
