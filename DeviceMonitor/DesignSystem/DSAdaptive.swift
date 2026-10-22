import SwiftUI

/// How many card columns a screen shows, derived from its measured width, never from the size class:
/// a split-view detail column reports a regular size class at 474 pt.
nonisolated enum LayoutColumns: Int, Sendable, Equatable {
    case one = 1, two, three

    /// The largest n in {3, 2} with n·cardMinimum + (n−1)·gap + 2·margin ≤ width, where margin and gap
    /// are 16 below 600 pt and 20 from there; otherwise `.one`.
    static func fitting(width: CGFloat, cardMinimum: CGFloat) -> LayoutColumns {
        let regular = width >= 600
        let margin: CGFloat = regular ? 20 : 16
        let gap: CGFloat = regular ? 20 : 16
        for count in [3, 2] where CGFloat(count) * cardMinimum + CGFloat(count - 1) * gap + 2 * margin <= width {
            return LayoutColumns(rawValue: count) ?? .one
        }
        return .one
    }
}

extension View {
    /// Columns(W) = largest n in {3, 2} with n·cardMin + (n−1)·gap + 2·margin ≤ W (cardMin = `cardMinimum`
    /// scaled relativeTo .body; margin and gap 16 below W 600, else 20); `.one` at accessibility text sizes.
    /// Read it once on a screen's root scroll view, never per row.
    func readLayoutColumns(_ columns: Binding<LayoutColumns>, cardMinimum: CGFloat = 300) -> some View {
        modifier(AdaptiveColumnsReader(columns: columns, cardMinimum: cardMinimum))
    }

    /// Horizontal padding equal to the screen margin: 16 pt below 600 pt wide, 20 pt from there.
    /// Apply it to the stack inside a `ScrollView`, never to the scroll view, so it scrolls from the edges.
    func dsContainerMargins() -> some View {
        modifier(ContainerMargins())
    }

    /// Rows are at most `maxRowWidth` wide and centred on wide containers, the spare width split equally on both
    /// sides; narrower containers keep the screen margin on both edges.
    func dsFormColumn(maxRowWidth: CGFloat = 740) -> some View {
        modifier(FormColumn(maxRowWidth: maxRowWidth))
    }
}

private struct AdaptiveColumnsReader: ViewModifier {
    @Binding var columns: LayoutColumns
    let cardMinimum: CGFloat
    /// The text size's scale for `cardMinimum`, in percent.
    @ScaledMetric(relativeTo: .body) private var scalePercent: CGFloat = 100
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var width: CGFloat = 0

    init(columns: Binding<LayoutColumns>, cardMinimum: CGFloat) {
        _columns = columns
        self.cardMinimum = cardMinimum
    }

    private var resolved: LayoutColumns {
        dynamicTypeSize.isAccessibilitySize
            ? .one
            : LayoutColumns.fitting(width: width, cardMinimum: cardMinimum * scalePercent / 100)
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width - proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing
            } action: { newWidth in
                width = newWidth
            }
            .onChange(of: resolved, initial: true) { _, newColumns in
                columns = newColumns
            }
    }
}

/// The width is measured outside the padding, so it is the container's.
private struct ContainerMargins: ViewModifier {
    @State private var width: CGFloat = 0

    init() {}

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DSLayout.margin(forWidth: width))
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
    }
}

/// Equal leading and trailing scroll-content margins. The width is measured inside the safe area, which the
/// margins are added to.
private struct FormColumn: ViewModifier {
    let maxRowWidth: CGFloat
    @State private var width: CGFloat = 0

    init(maxRowWidth: CGFloat) {
        self.maxRowWidth = maxRowWidth
    }

    func body(content: Content) -> some View {
        let side = max(DSLayout.margin(forWidth: width), (width - maxRowWidth) / 2)
        content
            .contentMargins(.horizontal, side, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width - proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing
            } action: { newWidth in
                width = newWidth
            }
    }
}

/// Cards in columns that keep their own heights: item i goes to column i mod n, so no card stretches to a
/// partner's height. Conditional cards that are absent take no slot. A card that spans the full width goes
/// above the masonry, outside it.
struct DSMasonry<Content: View>: View {
    private let columns: Int
    private let spacing: CGFloat
    private let content: Content

    init(columns: Int, spacing: CGFloat = DSLayout.space16, @ViewBuilder content: () -> Content) {
        self.columns = columns
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        Group(subviews: content) { subviews in
            let items = Array(subviews)
            if columns <= 1 {
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(items) { item in
                        item
                    }
                }
            } else {
                let lanes = (0..<columns).map { lane in
                    stride(from: lane, to: items.count, by: columns).map { items[$0] }
                }
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(lanes.indices, id: \.self) { lane in
                        VStack(alignment: .leading, spacing: spacing) {
                            ForEach(lanes[lane]) { item in
                                item
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
        }
    }
}

/// Wrapping layout for pills, tags and summary items; each row is aligned leading or centred.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var alignment: HorizontalAlignment = .leading

    init(spacing: CGFloat = 8, alignment: HorizontalAlignment = .leading) {
        self.spacing = spacing
        self.alignment = alignment
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = alignment == .center ? bounds.minX + (bounds.width - row.width) / 2 : bounds.minX
            for index in row.indices {
                let size = measure(subviews[index], width: bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = measure(subviews[index], width: width)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }

    /// Ideal size, capped at the row width so an oversize pill truncates inside the row.
    private func measure(_ subview: LayoutSubview, width: CGFloat) -> CGSize {
        subview.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
    }
}
