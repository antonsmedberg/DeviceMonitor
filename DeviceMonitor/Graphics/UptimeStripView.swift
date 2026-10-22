import SwiftUI

/// Status-page strip: one bar per cell, grey while up, amber when unstable, red when down and short where
/// nothing was measured. With Differentiate Without Color, down bars are hatched and unstable bars broken.
/// Drag sideways across an interactive strip to read one cell in the caption row. The cells carry each
/// state through the hours the app was closed, so the strip ends with the "seen while open" caption and
/// never states a percentage.
struct UptimeStripView: View {
    let title: String
    let cells: [UptimeCell]
    let leadingCaption: String
    let trailingCaption: String
    let barHeight: CGFloat
    /// nil: 2 pt, or 1 pt with more than 60 cells.
    let barGap: CGFloat?
    let isInteractive: Bool

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var selection: Int?
    @State private var width: CGFloat = 0
    @State private var isScrubbing = false
    /// Counts releases, so the selection clears 1.5 s after the last one.
    @State private var releases = 0
    /// Counts cells the finger moves onto, so clearing the selection plays no haptic.
    @State private var scrubSteps = 0

    init(
        title: String,
        cells: [UptimeCell],
        leadingCaption: String,
        trailingCaption: String,
        barHeight: CGFloat = DSLayout.stripHeight,
        barGap: CGFloat? = nil,
        isInteractive: Bool = true
    ) {
        self.title = title
        self.cells = cells
        self.leadingCaption = leadingCaption
        self.trailingCaption = trailingCaption
        self.barHeight = barHeight
        self.barGap = barGap
        self.isInteractive = isInteractive
    }

    private var selectedCell: UptimeCell? {
        guard let selection, cells.indices.contains(selection) else { return nil }
        return cells[selection]
    }

    /// Daily strips read their cells by date, shorter ones by time.
    private var isDaily: Bool {
        guard let first = cells.first, let last = cells.last else { return false }
        return last.interval.end.timeIntervalSince(first.interval.start) / Double(cells.count) >= 12 * 3600
    }

    var body: some View {
        let strip = VStack(alignment: .leading, spacing: 6) {
            bars
                .frame(height: barHeight)
            captionRow
            Text(AvailabilityNarrative.seenWhileOpenCaption)
                .font(DSTypography.axis)
                .foregroundStyle(DSColor.textSecondary)
        }
        .sensoryFeedback(.selection, trigger: scrubSteps)
        .task(id: releases) {
            guard releases > 0 else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, !isScrubbing else { return }
            selection = nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(selectedCell.map { readout(for: $0) } ?? AvailabilityNarrative.spokenSummary(cells: cells))
        if isInteractive {
            strip.accessibilityAdjustableAction { direction in
                let last = cells.count - 1
                guard last >= 0 else { return }
                switch direction {
                case .increment: selection = min((selection ?? -1) + 1, last)
                case .decrement: selection = max((selection ?? last + 1) - 1, 0)
                @unknown default: break
                }
            }
        } else {
            strip
        }
    }

    /// "24h ago" … "Now", replaced by the selected cell's readout while scrubbing. Both layers stay in the
    /// layout, so the row keeps its height.
    private var captionRow: some View {
        ZStack(alignment: .leading) {
            HStack {
                Text(leadingCaption)
                Spacer(minLength: DSLayout.space8)
                Text(trailingCaption)
            }
            .font(DSTypography.axis)
            .foregroundStyle(DSColor.textSecondary)
            .opacity(selectedCell == nil ? 1 : 0)
            Text(selectedCell.map { readout(for: $0) } ?? "")
                .font(DSTypography.axis.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .opacity(selectedCell == nil ? 0 : 1)
        }
    }

    private var bars: some View {
        Canvas { context, size in
            let count = cells.count
            guard count > 0 else { return }
            let gap = barGap ?? (count > 60 ? 1 : 2)
            let barWidth = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            for (index, cell) in cells.enumerated() {
                let height = cell.state == .noData ? size.height * 0.3 : size.height
                let rect = CGRect(x: CGFloat(index) * (barWidth + gap), y: size.height - height, width: barWidth, height: height)
                let bar = Path(roundedRect: rect, cornerRadius: min(1.5, barWidth / 2), style: .continuous)
                var layer = context
                layer.opacity = selection == nil || selection == index ? 1 : 0.4
                layer.fill(bar, with: .color(DSColor.fill(forUptime: cell.state)))
                guard differentiateWithoutColor else { continue }
                switch cell.state {
                case .offline:
                    layer.drawLayer { hatched in
                        hatched.clip(to: bar)
                        hatched.stroke(Self.hatch(in: rect), with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1))
                    }
                case .unstable:
                    let gapRect = CGRect(x: rect.minX, y: rect.midY - 0.75, width: rect.width, height: 1.5)
                    layer.fill(Path(gapRect), with: .color(DSColor.card))
                case .online, .noData:
                    break
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .gesture(HorizontalScrub(onChanged: { x in
            isScrubbing = true
            select(atX: x)
        }, onEnded: {
            isScrubbing = false
            releases += 1
        }))
        .allowsHitTesting(isInteractive)
    }

    private func select(atX x: CGFloat) {
        guard width > 0, !cells.isEmpty else { return }
        let index = min(max(Int(x / width * CGFloat(cells.count)), 0), cells.count - 1)
        guard index != selection else { return }
        selection = index
        scrubSteps += 1
    }

    /// "3 PM – 3:30 PM · Offline · 4 min down" for short cells, "Tue, Oct 14 · Up · 1 outage seen · 12 min down"
    /// for days: the state word, then outages and down time when there are any.
    private func readout(for cell: UptimeCell) -> String {
        var parts = [period(of: cell), cell.state.title]
        if isDaily, cell.outages > 0 {
            parts.append("\(Formatters.count(cell.outages, singular: "outage", plural: "outages")) seen")
        }
        if cell.offlineSeconds > 0 {
            parts.append("\(Formatters.duration(cell.offlineSeconds)) down")
        }
        return parts.joined(separator: " · ")
    }

    private func period(of cell: UptimeCell) -> String {
        if isDaily {
            return cell.interval.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        let calendar = Calendar.current
        let onTheHour = calendar.component(.minute, from: cell.interval.start) == 0 && calendar.component(.minute, from: cell.interval.end) == 0
        let style: Date.FormatStyle = onTheHour ? .dateTime.hour() : .dateTime.hour().minute()
        return "\(cell.interval.start.formatted(style)) – \(cell.interval.end.formatted(style))"
    }

    /// 45° lines across `rect`, so a down bar reads without colour.
    private static func hatch(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 4
        }
        return path
    }
}
