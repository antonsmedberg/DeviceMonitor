import SwiftUI

/// Who is around when: one row per device and one column per clock hour. A cell is mint at an opacity that
/// grows with the share of the hour the device answered (presence is being online), and the no-data grey when
/// it never answered. Drag sideways over the cells to read a column.
struct PresenceHeatmapView: View {
    let rows: [PresenceRow]
    let hourStarts: [Date]
    let visibleRows: Int

    @State private var showsAll = false
    @State private var selection: Int?
    @State private var width: CGFloat = 0

    init(rows: [PresenceRow], hourStarts: [Date], visibleRows: Int = 8) {
        self.rows = rows
        self.hourStarts = hourStarts
        self.visibleRows = visibleRows
    }

    private var nameWidth: CGFloat {
        width >= 600 ? 112 : 96
    }

    private var shownRows: [PresenceRow] {
        showsAll ? rows : Array(rows.prefix(visibleRows))
    }

    private var showAllTitle: String {
        showsAll ? "Show Less" : "Show All (\(rows.count))"
    }

    /// "8 AM · 11 of 14 online" for the selected column.
    private var readout: String? {
        guard let selection, hourStarts.indices.contains(selection) else { return nil }
        let hour = hourStarts[selection].formatted(.dateTime.hour())
        return "\(hour) · \(PresenceGrid.online(rows: rows, column: selection)) of \(rows.count) online"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(readout ?? " ")
                .font(DSTypography.rowSecondaryValue.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
                .padding(.bottom, DSLayout.space4)
                .accessibilityHidden(true)
            grid
            axis
                .frame(height: 16)
                .accessibilityHidden(true)
            if rows.count > visibleRows {
                DSLink(showAllTitle) {
                    showsAll.toggle()
                }
                .padding(.top, DSLayout.space8)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .onChange(of: readout) { _, newReadout in
            if let newReadout {
                AccessibilityNotification.Announcement(newReadout).post()
            }
        }
    }

    private var grid: some View {
        VStack(spacing: DSLayout.space4) {
            ForEach(shownRows) { row in
                HStack(spacing: DSLayout.space8) {
                    Text(row.name)
                        .font(DSTypography.body)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: nameWidth, alignment: .leading)
                    cells(row.shares)
                        .frame(height: 18)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.name)
                .accessibilityValue(onlineHours(row))
            }
        }
        .contentShape(Rectangle())
        .gesture(HorizontalScrub(onChanged: { x in
            select(atX: x)
        }, onEnded: {
            selection = nil
        }))
    }

    /// Cells 2 pt apart with 2 pt corners. Before the device existed a cell stays empty.
    private func cells(_ shares: [Double?]) -> some View {
        Canvas { context, size in
            let count = shares.count
            guard count > 0 else { return }
            let gap: CGFloat = 2
            let cellWidth = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            for (index, share) in shares.enumerated() {
                guard let share else { continue }
                let rect = CGRect(x: CGFloat(index) * (cellWidth + gap), y: 0, width: cellWidth, height: size.height)
                let emphasis = selection == nil || selection == index ? 1 : 0.45
                let clamped = min(max(share, 0), 1)
                let color = clamped > 0 ? DSColor.onlineFill.opacity((0.25 + 0.75 * clamped) * emphasis) : DSColor.noData.opacity(emphasis)
                context.fill(Path(roundedRect: rect, cornerRadius: min(2, cellWidth / 2), style: .continuous), with: .color(color))
            }
        }
    }

    /// Hour labels under the columns that start at 12 AM, 6 AM, 12 PM and 6 PM.
    private var axis: some View {
        HStack(spacing: DSLayout.space8) {
            Color.clear
                .frame(width: nameWidth)
            HStack(spacing: 2) {
                ForEach(hourStarts.indices, id: \.self) { column in
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .overlay {
                            if let label = axisLabel(column) {
                                Text(label)
                                    .font(DSTypography.axis)
                                    .foregroundStyle(DSColor.textSecondary)
                                    .fixedSize()
                            }
                        }
                }
            }
        }
    }

    private func axisLabel(_ column: Int) -> String? {
        let start = hourStarts[column]
        guard Calendar.current.component(.hour, from: start) % 6 == 0 else { return nil }
        return start.formatted(.dateTime.hour())
    }

    private func select(atX x: CGFloat) {
        let cellsWidth = width - nameWidth - DSLayout.space8
        guard cellsWidth > 0, !hourStarts.isEmpty else { return }
        let column = Int((x - nameWidth - DSLayout.space8) / cellsWidth * CGFloat(hourStarts.count))
        let clamped = min(max(column, 0), hourStarts.count - 1)
        if clamped != selection {
            selection = clamped
        }
    }

    /// "online 14 of 24 hours": the shares added up.
    private func onlineHours(_ row: PresenceRow) -> String {
        let hours = row.shares.compactMap { $0 }.reduce(0, +)
        return "online \(Int(hours.rounded())) of \(row.shares.count) hours"
    }
}
