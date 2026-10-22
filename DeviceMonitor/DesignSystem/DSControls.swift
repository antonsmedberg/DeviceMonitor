import SwiftUI

// MARK: - Segmented control

nonisolated enum DSSegmentStyle: Sendable, Hashable {
    /// A track with a sliding well: Activity's filter, Insights' sections.
    case container
    /// Separate pills, the selected one outlined: time windows inside cards.
    case outlined
}

/// One choice out of a few, always one selected. Each segment is its own plain button, so segments tap
/// independently inside a List row. The selected label is semibold in the tint (weight is the non-colour cue);
/// the container style's well slides between segments and cross-fades under Reduce Motion.
struct DSSegmentedControl<Option>: View where Option: Hashable & RawRepresentable, Option.RawValue == String {
    private let options: [Option]
    @Binding private var selection: Option
    private let style: DSSegmentStyle
    private let fillsWidth: Bool
    private let identifierPrefix: String
    private let controlLabel: String
    private let titleFor: (Option) -> String

    @Environment(\.dsMotion) private var motion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    @Namespace private var namespace

    init(
        _ options: [Option],
        selection: Binding<Option>,
        style: DSSegmentStyle = .container,
        fillsWidth: Bool = true,
        identifierPrefix: String,
        accessibilityLabel: String,
        title: @escaping (Option) -> String
    ) {
        self.options = options
        _selection = selection
        self.style = style
        self.fillsWidth = fillsWidth
        self.identifierPrefix = identifierPrefix
        controlLabel = accessibilityLabel
        titleFor = title
    }

    var body: some View {
        Group {
            switch style {
            case .container: track
            case .outlined: pills
            }
        }
        // Scoped to the control, so a selection change does not animate the content below it.
        .animation(DSMotion.animation(DSMotion.springFast, reduceMotion: motion.reduceMotion), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
        .dynamicTypeSize(style == .outlined ? (...DynamicTypeSize.xxxLarge) : (...DynamicTypeSize.accessibility5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(controlLabel)
    }

    /// A 44 pt track, 4 pt inset, equal-width segments.
    private var track: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                segmentButton(option) { isSelected in
                    label(for: option, isSelected: isSelected)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, DSLayout.space4)
                        .frame(maxWidth: .infinity, minHeight: DSLayout.segmentHeight - 2 * DSLayout.space4)
                        .background {
                            if isSelected {
                                well
                                    .matchedGeometryEffect(id: wellID(for: option), in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(DSLayout.space4)
        .background {
            RoundedRectangle(cornerRadius: DSLayout.segmentRadius, style: .continuous)
                .fill(DSColor.segmentTrack)
        }
    }

    /// The selected segment: the page colour with an edge (`stroke` in light, `hairline` in dark), or a 1 pt
    /// tint outline with Increase Contrast.
    @ViewBuilder
    private var well: some View {
        let shape = DSLayout.controlShape
        if contrast == .increased {
            shape
                .fill(DSColor.segmentWell)
                .overlay {
                    shape.strokeBorder(.tint, lineWidth: 1)
                }
        } else {
            shape
                .fill(DSColor.segmentWell)
                .overlay {
                    shape.strokeBorder(colorScheme == .dark ? DSColor.hairline : DSColor.stroke, lineWidth: 1 / displayScale)
                }
        }
    }

    /// One shared id slides the well; under Reduce Motion each segment has its own, so the wells cross-fade.
    private func wellID(for option: Option) -> String {
        motion.reduceMotion ? "well.\(option.rawValue)" : "well"
    }

    /// Separate 32 pt pills, 4 pt apart, filling the width or 64 pt each.
    private var pills: some View {
        HStack(spacing: DSLayout.space4) {
            ForEach(options, id: \.self) { option in
                segmentButton(option) { isSelected in
                    label(for: option, isSelected: isSelected)
                        .lineLimit(1)
                        .padding(.horizontal, DSLayout.space4)
                        .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil, minHeight: DSLayout.pillHeight)
                        .frame(width: fillsWidth ? nil : 64)
                        .background {
                            if isSelected {
                                DSLayout.controlShape.strokeBorder(.tint, lineWidth: 1)
                            } else {
                                DSLayout.controlShape.fill(DSColor.cardElevated)
                            }
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .padding(.vertical, -12)
                }
            }
        }
    }

    private func segmentButton<Content: View>(_ option: Option, @ViewBuilder content: (Bool) -> Content) -> some View {
        let isSelected = option == selection
        let segment = content(isSelected)
        return Button {
            if !isSelected {
                selection = option
            }
        } label: {
            segment
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(identifierPrefix).\(option.rawValue)")
    }

    @ViewBuilder
    private func label(for option: Option, isSelected: Bool) -> some View {
        if isSelected {
            Text(titleFor(option))
                .font(DSTypography.segmentSelected)
                .foregroundStyle(.tint)
        } else {
            Text(titleFor(option))
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
        }
    }
}

// MARK: - Filter chips

/// One horizontally scrolling row of 32 pt chips from the screen margin, fading out at the trailing edge to
/// show there is more. Exactly one chip is always selected: outlined in the tint with a semibold label; the
/// others are filled. Opaque, never glass. Each chip is its own plain button, so chips tap independently
/// inside a List row.
struct DSChipBar<Option>: View where Option: Hashable & RawRepresentable, Option.RawValue == String {
    private let options: [Option]
    @Binding private var selection: Option
    private let identifierPrefix: String
    private let barLabel: String
    private let titleFor: (Option) -> String

    @Environment(\.dsMotion) private var motion
    /// The chip the user just tapped, so the row does not jump to centre it.
    @State private var tappedOption: Option? = nil

    init(
        _ options: [Option],
        selection: Binding<Option>,
        identifierPrefix: String,
        accessibilityLabel: String,
        title: @escaping (Option) -> String
    ) {
        self.options = options
        _selection = selection
        self.identifierPrefix = identifierPrefix
        barLabel = accessibilityLabel
        titleFor = title
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: DSLayout.space8) {
                    ForEach(options, id: \.self) { option in
                        chip(for: option)
                            .id(option)
                    }
                }
                .padding(.trailing, DSLayout.space24)
            }
            .scrollIndicators(.hidden)
            // Scroll margins reach nested scroll views; a list's top margin must not move the chips down.
            .contentMargins(.vertical, 0, for: .scrollContent)
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: DSLayout.space24)
                }
            }
            // A filter chosen elsewhere (an Overview counter) centres its chip; a tapped chip scrolls only as far
            // as it must to be wholly visible.
            .onChange(of: selection, initial: true) { _, newSelection in
                let anchor: UnitPoint? = newSelection == tappedOption ? nil : .center
                tappedOption = nil
                withAnimation(DSMotion.animation(DSMotion.springSoft, reduceMotion: motion.reduceMotion)) {
                    proxy.scrollTo(newSelection, anchor: anchor)
                }
            }
        }
        // Scoped to the bar, so a filter change does not animate the content below it.
        .animation(DSMotion.animation(DSMotion.springFast, reduceMotion: motion.reduceMotion), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(barLabel)
    }

    /// 32 pt visible, 44 pt tall in layout, so the scroll view does not clip the hit area.
    private func chip(for option: Option) -> some View {
        let isSelected = option == selection
        return Button {
            if !isSelected {
                tappedOption = option
                selection = option
            }
        } label: {
            chipTitle(titleFor(option), isSelected: isSelected)
                .lineLimit(1)
                .padding(.horizontal, DSLayout.space16)
                .frame(minHeight: DSLayout.chipHeight)
                .background {
                    if isSelected {
                        DSLayout.controlShape.strokeBorder(.tint, lineWidth: 1)
                    } else {
                        DSLayout.controlShape.fill(DSColor.chip)
                    }
                }
                .padding(.vertical, (DSLayout.minTapTarget - DSLayout.chipHeight) / 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(identifierPrefix).\(option.rawValue)")
    }

    @ViewBuilder
    private func chipTitle(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Text(title)
                .font(DSTypography.segmentSelected)
                .foregroundStyle(.tint)
        } else {
            Text(title)
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
        }
    }
}

// MARK: - Tiles

nonisolated enum DSTileStyle: Sendable, Hashable {
    /// Transparent with a 1 pt stroke: action tiles inside a card.
    case outlined
    /// The chip fill with a 1 pt stroke: shortcut tiles on the page.
    case filled
}

/// The look of an action or shortcut tile: a 20 pt line icon over a one-line label, at least 50 pt tall.
/// Disabled tiles fade to 45 %; a busy tile shows a spinner in place of the icon and keeps its size. Use it as
/// the label of a `Button` with `DSTileButtonStyle`, a `Menu` or a `ShareLink`.
struct DSTileLabel: View {
    private let title: String
    private let systemImage: String
    private let style: DSTileStyle
    private let isBusy: Bool

    @ScaledMetric(relativeTo: .title3) private var iconHeight: CGFloat = 20
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dsTilePressed) private var isPressed

    init(_ title: String, systemImage: String, style: DSTileStyle = .outlined, isBusy: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.isBusy = isBusy
    }

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .environment(\.symbolVariants, SymbolVariants.none)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .frame(height: iconHeight)
            .accessibilityHidden(true)
            Text(title)
                .font(DSTypography.tileLabel)
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
        .padding(.top, DSLayout.space8)
        .padding(.horizontal, DSLayout.space4)
        .frame(maxWidth: .infinity, minHeight: DSLayout.tileHeight, alignment: .top)
        .background {
            if style == .filled {
                DSLayout.controlShape.fill(isPressed ? DSColor.cardElevated : DSColor.chip)
            }
        }
        .overlay {
            DSLayout.controlShape
                .strokeBorder(DSColor.stroke, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(DSLayout.controlShape)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// The pressed state of a tile: `cardElevated` behind the label.
struct DSTileButtonStyle: ButtonStyle {
    init() {}

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.dsTilePressed, configuration.isPressed)
            .background {
                if configuration.isPressed {
                    DSLayout.controlShape.fill(DSColor.cardElevated)
                }
            }
    }
}

/// Tells a filled tile's label that its button is pressed, so its own fill gives way to the pressed one.
private nonisolated struct DSTilePressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    fileprivate nonisolated var dsTilePressed: Bool {
        get { self[DSTilePressedKey.self] }
        set { self[DSTilePressedKey.self] = newValue }
    }
}

/// Equal-width columns with the given spacing; rows 8 pt apart, each as tall as its tallest tile. Not lazy: a grid
/// holds a handful of tiles, and each one is in the accessibility tree before it is scrolled to.
struct DSTileGrid<Content: View>: View {
    private let columns: Int
    private let spacing: CGFloat
    private let content: Content

    init(columns: Int, spacing: CGFloat = DSLayout.space8, @ViewBuilder content: () -> Content) {
        self.columns = columns
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        TileColumnsLayout(columns: max(columns, 1), spacing: spacing, rowSpacing: DSLayout.space8) {
            content
        }
    }
}

private struct TileColumnsLayout: Layout {
    let columns: Int
    let spacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let column = columnWidth(for: proposal.width, subviews: subviews)
        let rows = rowHeights(columnWidth: column, subviews: subviews)
        let width = proposal.width ?? column * CGFloat(columns) + spacing * CGFloat(columns - 1)
        return CGSize(width: width, height: rows.reduce(0, +) + rowSpacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let column = columnWidth(for: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (row, height) in rowHeights(columnWidth: column, subviews: subviews).enumerated() {
            for index in row * columns ..< min((row + 1) * columns, subviews.count) {
                let x = bounds.minX + CGFloat(index - row * columns) * (column + spacing)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: column, height: height))
            }
            y += height + rowSpacing
        }
    }

    /// The proposed width shared out, or the widest tile's ideal width when no width is proposed.
    private func columnWidth(for width: CGFloat?, subviews: Subviews) -> CGFloat {
        guard let width else {
            return subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        }
        return max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func rowHeights(columnWidth: CGFloat, subviews: Subviews) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns).map { start in
            (start ..< min(start + columns, subviews.count))
                .map { subviews[$0].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
                .max() ?? 0
        }
    }
}

// MARK: - Text and pill buttons

/// The surface a control sits on, so it can stand one step above it.
nonisolated enum DSSurface: Sendable, Hashable {
    case page, card
}

/// A quiet full-width action: 36 pt, one step above its surface, the label in the tint with an optional line
/// icon. Never a filled accent.
struct DSTextButton: View {
    private let title: String
    private let systemImage: String?
    private let surface: DSSurface
    private let action: () -> Void

    init(_ title: String, systemImage: String? = nil, surface: DSSurface = .card, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.surface = surface
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body)
                        .environment(\.symbolVariants, SymbolVariants.none)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(DSTypography.body)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, DSLayout.space12)
            .padding(.vertical, DSLayout.space8)
            .frame(maxWidth: .infinity, minHeight: DSLayout.textButtonHeight)
            .background {
                DSLayout.controlShape.fill(surface == .page ? DSColor.chip : DSColor.cardElevated)
            }
            .padding(.vertical, (DSLayout.minTapTarget - DSLayout.textButtonHeight) / 2)
            .contentShape(Rectangle())
            .padding(.vertical, -(DSLayout.minTapTarget - DSLayout.textButtonHeight) / 2)
        }
        .buttonStyle(.plain)
    }
}

/// An inline action in a row or card header (Trust, Done, Clear): a 30 pt capsule outlined in the tint,
/// with a 44 pt hit area that does not grow its row.
struct DSPillButton: View {
    private let title: String
    private let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DSTypography.segmentSelected)
                .foregroundStyle(.tint)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 30)
                .overlay {
                    Capsule(style: .continuous).strokeBorder(.tint, lineWidth: 1)
                }
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .padding(.vertical, -7)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Counters

/// One count of the gateway line ("12 online"), which filters the Devices list.
nonisolated struct DSCounter: Sendable, Hashable, Identifiable {
    /// "online", "offline", "new" or "strangers".
    let id: String
    let systemImage: String
    let count: Int
    /// Only `.bad` with a count above zero takes a colour; every other count stays grey.
    let tone: DSTone
    let accessibilityLabel: String

    init(id: String, systemImage: String, count: Int, tone: DSTone = .neutral, accessibilityLabel: String) {
        self.id = id
        self.systemImage = systemImage
        self.count = count
        self.tone = tone
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Icon and count pairs, 13 pt apart, all grey except a bad count above zero. Each pair is a button with a
/// 44 pt hit area that keeps the visible gap.
struct DSCounterRow: View {
    private let counters: [DSCounter]
    private let identifierPrefix: String
    private let onSelect: (String) -> Void

    init(_ counters: [DSCounter], identifierPrefix: String, onSelect: @escaping (String) -> Void) {
        self.counters = counters
        self.identifierPrefix = identifierPrefix
        self.onSelect = onSelect
    }

    var body: some View {
        HStack(spacing: 13) {
            ForEach(counters) { counter in
                Button {
                    onSelect(counter.id)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: counter.systemImage)
                            .font(DSTypography.body)
                            .environment(\.symbolVariants, SymbolVariants.none)
                        Text("\(counter.count)")
                            .font(DSTypography.bodyValue)
                            .contentTransition(.numericText(value: Double(counter.count)))
                    }
                    .foregroundStyle(counter.tone == .bad && counter.count > 0 ? DSColor.offline : DSColor.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .padding(.horizontal, -6)
                    .padding(.vertical, -12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(counter.accessibilityLabel)
                .accessibilityHint(Self.hint(for: counter.id))
                .accessibilityIdentifier("\(identifierPrefix).\(counter.id)")
            }
        }
    }

    /// "Shows offline devices", "Shows strangers".
    private static func hint(for id: String) -> String {
        id == "strangers" ? "Shows strangers" : "Shows \(id) devices"
    }
}

// MARK: - Settings rows

/// The label of a settings row: a 20 pt line icon in the tint in a 28 pt column, the title, and an optional
/// grey value. No coloured tile. The row's separator starts at the title.
struct DSSettingsLabel: View {
    private let title: String
    private let systemImage: String
    private let value: String?

    @ScaledMetric(relativeTo: .title3) private var iconColumn: CGFloat = 28

    init(_ title: String, systemImage: String, value: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
    }

    var body: some View {
        HStack(spacing: DSLayout.space12) {
            Image(systemName: systemImage)
                .font(.title3)
                .environment(\.symbolVariants, SymbolVariants.none)
                .foregroundStyle(.tint)
                .frame(width: iconColumn)
                .accessibilityHidden(true)
            Text(title)
                .font(DSTypography.rowTitle)
                .foregroundStyle(DSColor.textPrimary)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            if let value {
                Spacer(minLength: DSLayout.space8)
                Text(value)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
