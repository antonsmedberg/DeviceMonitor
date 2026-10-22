import SwiftUI
import UIKit

// MARK: - Surfaces

/// Opaque content card, flat and without a shadow: a 1 px edge in light mode, none in dark, 1 pt with Increase
/// Contrast (`DSColor.cardEdge` is clear in standard dark). Cards never use glass; glass is for controls.
struct DSCardModifier: ViewModifier {
    let padding: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    init(padding: CGFloat) {
        self.padding = padding
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                DSLayout.cardShape.fill(DSColor.card)
            }
            .overlay {
                DSLayout.cardShape
                    .strokeBorder(DSColor.cardEdge, lineWidth: contrast == .increased ? 1 : 1 / displayScale)
                    .allowsHitTesting(false)
            }
            .containerShape(DSLayout.cardShape)
    }
}

extension View {
    func dsCard(padding: CGFloat = DSLayout.space16) -> some View {
        modifier(DSCardModifier(padding: padding))
    }

    /// List or Form: hides the system background, fills the page colour behind it, 20-pt section spacing.
    func dsGroupedList() -> some View {
        scrollContentBackground(.hidden)
            .background {
                DSColor.background.ignoresSafeArea()
            }
            .listSectionSpacing(DSLayout.cardGap)
    }

    /// One List or Form row (or a Section, which passes it to its rows): card background, hairline separator.
    func dsListRow() -> some View {
        listRowBackground(DSColor.card)
            .listRowSeparatorTint(DSColor.hairline)
    }
}

// MARK: - Titles, links and headers

/// A word after a title that says how something is doing, in its tone's ink ("Normal", "1 outage seen").
nonisolated struct DSStatusWord: Sendable, Hashable {
    let text: String
    let tone: DSTone

    init(_ text: String, tone: DSTone) {
        self.text = text
        self.tone = tone
    }
}

/// A card or section title on one line: bold title, grey qualifier, optional status word, then a trailing
/// item (a link, pills or an ⓘ button). The qualifier truncates first, then the title; the trailing item never
/// truncates and moves under the title at accessibility sizes. Title, qualifier and status read as one header.
struct DSTitleRow<Trailing: View>: View {
    private let title: String
    private let qualifier: String?
    private let status: DSStatusWord?
    private let spokenValue: String?
    private let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        _ title: String,
        qualifier: String? = nil,
        status: DSStatusWord? = nil,
        accessibilityValue: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.qualifier = qualifier
        self.status = status
        spokenValue = accessibilityValue
        self.trailing = trailing()
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DSLayout.space4) {
                heading
                trailing
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: DSLayout.space8) {
                heading
                Spacer(minLength: DSLayout.space8)
                trailing
                    .fixedSize()
            }
        }
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title)
                .font(DSTypography.cardTitle)
                .foregroundStyle(DSColor.textPrimary)
                .layoutPriority(1)
            if let qualifier {
                Text(qualifier)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
            }
            if let status {
                Text(status.text)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.ink(status.tone))
                    .layoutPriority(2)
            }
        }
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(spokenValue ?? "")
    }
}

extension DSTitleRow where Trailing == EmptyView {
    init(_ title: String, qualifier: String? = nil, status: DSStatusWord? = nil, accessibilityValue: String? = nil) {
        self.init(title, qualifier: qualifier, status: status, accessibilityValue: accessibilityValue, trailing: { EmptyView() })
    }
}

/// A text link in the tint ("See All"), with a 44 pt hit area that does not grow its row.
struct DSLink: View {
    private let title: String
    private let spokenLabel: String?
    private let action: () -> Void

    init(_ title: String, accessibilityLabel: String? = nil, action: @escaping () -> Void) {
        self.title = title
        spokenLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DSTypography.body)
                .foregroundStyle(.tint)
                .lineLimit(1)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .padding(.vertical, -12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel ?? title)
    }
}

/// A list section header in sentence case: "Online (11)".
struct DSListHeader: View {
    private let title: String
    private let count: Int?

    init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    var body: some View {
        Text(count.map { "\(title) (\($0))" } ?? title)
            .font(DSTypography.listHeader)
            .foregroundStyle(DSColor.textSecondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Summary line

/// One label and value of a summary line. The label takes its tone's ink, so the line is the chart's legend.
nonisolated struct DSSummaryItem: Sendable, Hashable, Identifiable {
    let id: String
    let label: String
    let value: String
    let tone: DSTone?
    /// What VoiceOver reads for the value ("1.8 milliseconds"); defaults to `value`.
    let spokenValue: String

    init(id: String, label: String, value: String, tone: DSTone? = nil, spokenValue: String? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.tone = tone
        self.spokenValue = spokenValue ?? value
    }
}

/// "Latency 1.8 ms   Jitter 0.3 ms ………… p95 2.5 ms": coloured labels with grey values, 12 pt apart, and an
/// optional trailing item on the right. Items that do not fit one line wrap, the trailing item last. Read as
/// one element.
struct DSSummaryLine: View {
    private let items: [DSSummaryItem]
    private let trailing: DSSummaryItem?

    init(_ items: [DSSummaryItem], trailing: DSSummaryItem? = nil) {
        self.items = items
        self.trailing = trailing
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DSLayout.space12) {
                ForEach(items) { item in
                    cell(item)
                }
                Spacer(minLength: DSLayout.space12)
                if let trailing {
                    cell(trailing)
                }
            }
            FlowLayout(spacing: DSLayout.space12) {
                ForEach(items) { item in
                    cell(item)
                }
                if let trailing {
                    cell(trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    private var spokenText: String {
        (items + (trailing.map { [$0] } ?? []))
            .map { "\($0.label) \($0.spokenValue)" }
            .joined(separator: ", ")
    }

    /// Fixed size, so the one-line form cannot squeeze and `ViewThatFits` falls back to the wrapping form.
    private func cell(_ item: DSSummaryItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(item.label)
                .font(DSTypography.body)
                .foregroundStyle(item.tone.map { DSColor.ink($0) } ?? DSColor.textSecondary)
            Text(item.value)
                .font(DSTypography.bodyValue)
                .foregroundStyle(DSColor.textSecondary)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - Info grid

/// One self-describing value of the info grid ("192.168.178.2", "MAC unknown").
nonisolated struct DSInfoItem: Sendable, Hashable, Identifiable {
    nonisolated enum Emphasis: Sendable, Hashable {
        case primary, secondary, tertiary, tone(DSTone)
    }

    let id: String
    let text: String
    let systemImage: String?
    let emphasis: Emphasis
    let accessibilityLabel: String
    /// Long-press offers Copy.
    let isCopyable: Bool

    init(id: String, text: String, systemImage: String? = nil, emphasis: Emphasis = .primary, accessibilityLabel: String, isCopyable: Bool = false) {
        self.id = id
        self.text = text
        self.systemImage = systemImage
        self.emphasis = emphasis
        self.accessibilityLabel = accessibilityLabel
        self.isCopyable = isCopyable
    }
}

nonisolated struct DSInfoRow: Sendable, Hashable, Identifiable {
    let id: String
    let leading: DSInfoItem
    let trailing: DSInfoItem?

    init(id: String, leading: DSInfoItem, trailing: DSInfoItem? = nil) {
        self.id = id
        self.leading = leading
        self.trailing = trailing
    }
}

/// An unlabelled two-column grid of self-describing values on a 28 pt pitch: column 1 leading, column 2
/// trailing. One column at accessibility sizes. Each item is its own element.
struct DSInfoGrid: View {
    private let rows: [DSInfoRow]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(rows: [DSInfoRow]) {
        self.rows = rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                ForEach(items) { item in
                    cell(item)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                }
            } else {
                ForEach(rows) { row in
                    HStack(spacing: DSLayout.space12) {
                        cell(row.leading)
                            .layoutPriority(1)
                        Spacer(minLength: DSLayout.space12)
                        if let trailing = row.trailing {
                            cell(trailing)
                        }
                    }
                    .frame(minHeight: 28)
                }
            }
        }
    }

    private var items: [DSInfoItem] {
        rows.flatMap { row in
            [row.leading] + (row.trailing.map { [$0] } ?? [])
        }
    }

    @ViewBuilder
    private func cell(_ item: DSInfoItem) -> some View {
        let content = HStack(spacing: 5) {
            if let systemImage = item.systemImage {
                Image(systemName: systemImage)
                    .font(DSTypography.body)
                    .environment(\.symbolVariants, SymbolVariants.none)
                    .foregroundStyle(DSColor.textSecondary)
                    .accessibilityHidden(true)
            }
            Text(item.text)
                .font(DSTypography.bodyValue)
                .foregroundStyle(color(for: item.emphasis))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)

        if item.isCopyable {
            content
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = item.text
                    } label: {
                        Label("Copy", systemImage: "document.on.document")
                    }
                }
        } else {
            content
        }
    }

    private func color(for emphasis: DSInfoItem.Emphasis) -> Color {
        switch emphasis {
        case .primary: return DSColor.textPrimary
        case .secondary: return DSColor.textSecondary
        case .tertiary: return DSColor.textTertiary
        case .tone(let tone): return DSColor.ink(tone)
        }
    }
}

// MARK: - Rows

/// The 56 pt row of every device list (insets 8 / 16 / 8 / 16 around 40 pt): a thumbnail, the title with
/// inline badges over a subtitle of segments split by hairline dividers, and a right-aligned column of a
/// primary metric over a secondary one, or an accessory such as a Trust pill. A subtitle too wide for its line
/// falls back to the shorter ones given, whole segments at a time; the last one truncates. The text block and
/// the column are one accessibility element; the accessory stays separate. At accessibility sizes the column
/// moves under the subtitle.
struct DSListRow<Accessory: View>: View {
    private let thumbnail: DeviceThumbnail
    private let title: String
    private let badges: [DSBadge.Kind]
    private let subtitle: [String]
    private let subtitleFallbacks: [[String]]
    private let primary: String?
    private let primaryTone: DSTone?
    private let secondary: String?
    private let rowLabel: String
    private let rowValue: String
    private let accessory: Accessory

    /// Fits "12.5 ms jitter" at 13 pt, so values line up from row to row.
    @ScaledMetric(relativeTo: .footnote) private var trailingWidth: CGFloat = 92
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    init(
        thumbnail: DeviceThumbnail,
        title: String,
        badges: [DSBadge.Kind] = [],
        subtitle: [String],
        subtitleFallbacks: [[String]] = [],
        primary: String? = nil,
        primaryTone: DSTone? = nil,
        secondary: String? = nil,
        accessibilityLabel: String,
        accessibilityValue: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.thumbnail = thumbnail
        self.title = title
        self.badges = badges
        self.subtitle = subtitle
        self.subtitleFallbacks = subtitleFallbacks
        self.primary = primary
        self.primaryTone = primaryTone
        self.secondary = secondary
        rowLabel = accessibilityLabel
        rowValue = accessibilityValue
        self.accessory = accessory()
    }

    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }
    private var hasMetrics: Bool { primary != nil || secondary != nil }

    var body: some View {
        HStack(spacing: DSLayout.space12) {
            HStack(alignment: isLarge ? .top : .center, spacing: DSLayout.space12) {
                thumbnail
                VStack(alignment: .leading, spacing: DSLayout.space2) {
                    titleLine
                    subtitleLine
                    if isLarge && hasMetrics {
                        metrics(alignment: .leading)
                            .padding(.top, DSLayout.space2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                if !isLarge && hasMetrics {
                    metrics(alignment: .trailing)
                        .frame(minWidth: trailingWidth, alignment: .trailing)
                        .fixedSize()
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rowLabel)
            .accessibilityValue(rowValue)
            accessory
        }
        .frame(minHeight: DSLayout.rowHeight - 2 * DSLayout.space8)
    }

    /// Fixed colours, not the hierarchical styles, which a button around the row would resolve to its tint.
    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(DSTypography.rowTitle)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(isLarge ? 3 : 1)
            ForEach(badges, id: \.self) { badge in
                DSBadge(badge)
            }
        }
    }

    @ViewBuilder
    private var subtitleLine: some View {
        if isLarge {
            Text(subtitle.joined(separator: " · "))
                .font(DSTypography.rowSubtitle)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(3)
        } else {
            let candidates = [subtitle] + subtitleFallbacks
            // Fixed size, so a candidate cannot squeeze and `ViewThatFits` moves on to the next one.
            ViewThatFits(in: .horizontal) {
                ForEach(Array(candidates.enumerated()), id: \.offset) { index, segments in
                    segmentLine(segments)
                        .fixedSize(horizontal: index < candidates.count - 1, vertical: false)
                }
            }
            .font(DSTypography.rowSubtitle)
            .foregroundStyle(DSColor.textSecondary)
            .lineLimit(1)
        }
    }

    /// Segments split by 1 × 12 pt hairlines; the first one truncates last.
    private func segmentLine(_ segments: [String]) -> some View {
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
    }

    private func metrics(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: DSLayout.space2) {
            if let primary {
                HStack(spacing: DSLayout.space4) {
                    if let primaryGlyph {
                        Image(systemName: primaryGlyph)
                            .font(.caption2)
                    }
                    Text(primary)
                        .font(DSTypography.rowValue)
                }
                .foregroundStyle(primaryTone.map { DSColor.ink($0) } ?? DSColor.textPrimary)
            }
            if let secondary {
                Text(secondary)
                    .font(DSTypography.rowSecondaryValue)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .lineLimit(1)
    }

    /// Under Differentiate Without Color, a warn or bad metric leads with its shape.
    private var primaryGlyph: String? {
        guard differentiateWithoutColor else { return nil }
        switch primaryTone {
        case .warn?: return "exclamationmark.triangle.fill"
        case .bad?: return "xmark.circle.fill"
        default: return nil
        }
    }
}

extension DSListRow where Accessory == EmptyView {
    init(
        thumbnail: DeviceThumbnail,
        title: String,
        badges: [DSBadge.Kind] = [],
        subtitle: [String],
        subtitleFallbacks: [[String]] = [],
        primary: String? = nil,
        primaryTone: DSTone? = nil,
        secondary: String? = nil,
        accessibilityLabel: String,
        accessibilityValue: String
    ) {
        self.init(
            thumbnail: thumbnail,
            title: title,
            badges: badges,
            subtitle: subtitle,
            subtitleFallbacks: subtitleFallbacks,
            primary: primary,
            primaryTone: primaryTone,
            secondary: secondary,
            accessibilityLabel: accessibilityLabel,
            accessibilityValue: accessibilityValue,
            accessory: { EmptyView() }
        )
    }
}

/// A 40 pt row of a stats list: grey label, value on the right, a hairline under every row but the last.
struct DSStatRow: View {
    private let label: String
    private let value: String
    private let tone: DSTone?
    private let isLast: Bool

    @Environment(\.displayScale) private var displayScale

    init(_ label: String, value: String, tone: DSTone? = nil, isLast: Bool = false) {
        self.label = label
        self.value = value
        self.tone = tone
        self.isLast = isLast
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSLayout.space12) {
            Text(label)
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
            Spacer(minLength: DSLayout.space12)
            Text(value)
                .font(DSTypography.bodyValue)
                .foregroundStyle(tone.map { DSColor.ink($0) } ?? DSColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: DSLayout.statRowHeight)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(DSColor.hairline)
                    .frame(height: 1 / displayScale)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Badges and states

/// An inline badge after a row title: a neutral "New" capsule or the favourite star.
struct DSBadge: View {
    nonisolated enum Kind: Sendable, Hashable {
        case new, favorite
    }

    private let kind: DSBadge.Kind

    init(_ kind: DSBadge.Kind) {
        self.kind = kind
    }

    var body: some View {
        switch kind {
        case .new:
            Text("New")
                .font(DSTypography.badge)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(minHeight: 18)
                .background {
                    Capsule(style: .continuous).fill(DSColor.cardElevated)
                }
                .fixedSize()
                .accessibilityLabel("New device")
        case .favorite:
            Image(systemName: "star.fill")
                .font(DSTypography.badge)
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityLabel("Favorite")
        }
    }
}

/// A device's state as an 8 pt dot in its fill and the word in its ink. While monitoring is live, an online
/// device's dot breathes.
struct DSStateLabel: View {
    private let state: ReachabilityState
    private let isLive: Bool

    init(state: ReachabilityState, isLive: Bool = false) {
        self.state = state
        self.isLive = isLive
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(DSColor.fill(DSTone.forState(state)))
                .frame(width: 8, height: 8)
                .dsBreathing(isActive: isLive && state == .online, mode: .opacity)
            Text(state.title)
                .font(DSTypography.rowSubtitle.weight(.semibold))
                .foregroundStyle(DSColor.ink(DSTone.forState(state)))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.title)
        .accessibilityValue(isLive && state == .online ? "live" : "")
    }
}

/// A state's symbol in its ink (checkmark, triangle, cross or question mark), so state never rests on colour
/// alone. Callers say the state in words.
struct StateSymbol: View {
    let state: ReachabilityState
    let size: CGFloat

    init(state: ReachabilityState, size: CGFloat = 16) {
        self.state = state
        self.size = size
    }

    var body: some View {
        Image(systemName: state.systemImage)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(DSColor.tint(for: state))
            .accessibilityHidden(true)
    }
}

// MARK: - Motion

/// The one "live" breath: a dot scales (12 pt and more) or fades (smaller) over `PingMotion` timings while
/// `isActive`. It holds still under Reduce Motion, "Reduce visual effects" and screenshot runs.
struct DSBreathing: ViewModifier {
    enum Mode {
        case scale(anchor: UnitPoint)
        case opacity
    }

    let isActive: Bool
    let mode: Mode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dsReduceEffects) private var reduceEffects

    init(isActive: Bool, mode: DSBreathing.Mode) {
        self.isActive = isActive
        self.mode = mode
    }

    func body(content: Content) -> some View {
        let breathes = isActive && !reduceMotion && !reduceEffects && !LaunchArguments.current.isScreenshots
        if breathes {
            switch mode {
            case .scale(let anchor):
                content.phaseAnimator([1.0, PingMotion.breathScale]) { view, scale in
                    view.scaleEffect(scale, anchor: anchor)
                } animation: { _ in
                    .easeInOut(duration: PingMotion.breathHalfPeriod)
                }
            case .opacity:
                content.phaseAnimator([1.0, PingMotion.breathOpacity]) { view, opacity in
                    view.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: PingMotion.breathHalfPeriod)
                }
            }
        } else {
            content
        }
    }
}

extension View {
    func dsBreathing(isActive: Bool, mode: DSBreathing.Mode) -> some View {
        modifier(DSBreathing(isActive: isActive, mode: mode))
    }
}

// MARK: - Legend

/// A legend entry under strips, the heatmap and the maps: a 10 pt swatch (4 pt tall for no data, hatched
/// for offline under Differentiate Without Color) and its word, read as one element.
struct DSLegendSwatch: View {
    let color: Color
    let title: String
    let isHatched: Bool
    let isShort: Bool

    init(color: Color, title: String, isHatched: Bool = false, isShort: Bool = false) {
        self.color = color
        self.title = title
        self.isHatched = isHatched
        self.isShort = isShort
    }

    var body: some View {
        HStack(spacing: DSLayout.space4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .overlay {
                    if isHatched {
                        hatching
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .frame(width: 10, height: isShort ? 4 : 10)
                .frame(height: 10, alignment: .bottom)
                .accessibilityHidden(true)
            Text(title)
                .font(DSTypography.axis)
                .foregroundStyle(DSColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// 45° lines, as on offline cells.
    private var hatching: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 4
            }
            context.stroke(path, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1))
        }
    }
}

// MARK: - States and messages

/// Empty state built on the system component so it adapts to every size class. Its action is a quiet text
/// button; the screen's one prominent action stays in the toolbar.
struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(title: String, message: String, systemImage: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .symbolRenderingMode(.hierarchical)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                DSTextButton(actionTitle, surface: .page, action: action)
                    .frame(maxWidth: 280)
            }
        }
    }
}

/// Non-blocking error with recovery text, on a card.
struct ErrorBanner: View {
    let error: DeviceMonitorError
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?

    init(error: DeviceMonitorError, onDismiss: @escaping () -> Void, onRetry: (() -> Void)? = nil) {
        self.error = error
        self.onDismiss = onDismiss
        self.onRetry = onRetry
    }

    var body: some View {
        HStack(alignment: .top, spacing: DSLayout.space12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .environment(\.symbolVariants, SymbolVariants.none)
                .foregroundStyle(DSColor.degraded)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DSLayout.space4) {
                Text(error.errorDescription ?? "Something went wrong.")
                    .font(DSTypography.body.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(DSTypography.rowSubtitle)
                        .foregroundStyle(DSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let onRetry {
                    DSPillButton("Try Again", action: onRetry)
                        .padding(.top, DSLayout.space4)
                }
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: DSLayout.minTapTarget, height: DSLayout.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, -12)
            .padding(.trailing, -12)
            .accessibilityLabel("Dismiss")
        }
        .dsCard()
        .accessibilityElement(children: .contain)
    }
}

/// Informational banner (no Wi‑Fi, router down, permission), on a card.
struct InfoBanner: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    let actionTitle: String?
    let action: (() -> Void)?

    init(title: String, message: String, systemImage: String, tint: Color = .accentColor, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: DSLayout.space12) {
            Image(systemName: systemImage)
                .font(.title3)
                .environment(\.symbolVariants, SymbolVariants.none)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DSLayout.space4) {
                Text(title)
                    .font(DSTypography.body.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Text(message)
                    .font(DSTypography.rowSubtitle)
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    DSPillButton(actionTitle, action: action)
                        .padding(.top, DSLayout.space4)
                }
            }
            Spacer(minLength: 0)
        }
        .dsCard()
        .accessibilityElement(children: .combine)
    }
}

#Preview("Components") {
    ScrollView {
        VStack(alignment: .leading, spacing: DSLayout.cardGap) {
            DSChipBar(
                DeviceKind.allCases,
                selection: .constant(DeviceKind.router),
                identifierPrefix: "preview.chip",
                accessibilityLabel: "Filter",
                title: { $0.title }
            )
            DSSegmentedControl(
                ReachabilityState.allCases,
                selection: .constant(ReachabilityState.online),
                identifierPrefix: "preview.segment",
                accessibilityLabel: "Show",
                title: { $0.title }
            )
            HStack(spacing: DSLayout.space8) {
                ForEach(Array(DeviceKind.allCases.prefix(5).enumerated()), id: \.offset) { index, kind in
                    DeviceThumbnail(kind: kind, state: ReachabilityState.allCases[index % ReachabilityState.allCases.count])
                }
                DeviceThumbnail(kind: .nas, size: DSLayout.thumbnailService)
                DeviceThumbnail(kind: .router, state: .offline, size: DSLayout.thumbnailHeader)
                DSThumbnail(systemImage: "externaldrive", size: DSLayout.thumbnailService, badge: .risk(.high))
            }
            VStack(alignment: .leading, spacing: DSLayout.space12) {
                DSTitleRow("Latency", qualifier: "Router · 1H", status: DSStatusWord("Normal", tone: .good)) {
                    DSLink("See All", accessibilityLabel: "See all latency") {}
                }
                DSSegmentedControl(
                    ReachabilityState.allCases,
                    selection: .constant(ReachabilityState.offline),
                    style: .outlined,
                    identifierPrefix: "preview.window",
                    accessibilityLabel: "Time range",
                    title: { $0.title }
                )
                DSSummaryLine(
                    [
                        DSSummaryItem(id: "latency", label: "Latency", value: "1.8 ms", tone: .latency),
                        DSSummaryItem(id: "jitter", label: "Jitter", value: "0.3 ms", tone: .jitter),
                    ],
                    trailing: DSSummaryItem(id: "p95", label: "p95", value: "2.5 ms")
                )
                DSStatRow("Worst", value: "6.1 ms at 7:52 PM")
                DSStatRow("Spikes", value: "2 above 3.5 ms", tone: .warn, isLast: true)
            }
            .dsCard()
            VStack(alignment: .leading, spacing: DSLayout.space12) {
                DSInfoGrid(rows: [
                    DSInfoRow(
                        id: "address",
                        leading: DSInfoItem(id: "ip", text: "192.168.178.2", systemImage: "network", accessibilityLabel: "IP address, 192.168.178.2", isCopyable: true),
                        trailing: DSInfoItem(id: "mac", text: "MAC unknown", emphasis: .tertiary, accessibilityLabel: "MAC address unknown")
                    ),
                    DSInfoRow(
                        id: "outages",
                        leading: DSInfoItem(id: "seen", text: "Seen since Oct 16", systemImage: "calendar", emphasis: .secondary, accessibilityLabel: "Seen since October 16"),
                        trailing: DSInfoItem(id: "count", text: "1 outage seen · 30D", emphasis: .tone(.warn), accessibilityLabel: "1 outage seen in 30 days")
                    ),
                ])
                DSTileGrid(columns: 3) {
                    Button {} label: { DSTileLabel("Check Now", systemImage: "arrow.clockwise") }
                        .buttonStyle(DSTileButtonStyle())
                    Button {} label: { DSTileLabel("Ping", systemImage: "arrow.left.arrow.right", isBusy: true) }
                        .buttonStyle(DSTileButtonStyle())
                    Button {} label: { DSTileLabel("Trust", systemImage: "checkmark.shield") }
                        .buttonStyle(DSTileButtonStyle())
                }
            }
            .dsCard()
            VStack(spacing: 0) {
                DSListRow(
                    thumbnail: DeviceThumbnail(kind: .nas),
                    title: "DiskStation",
                    badges: [.favorite],
                    subtitle: ["192.168.178.2", "Synology"],
                    primary: "1.8 ms",
                    primaryTone: .good,
                    secondary: "0.3 ms jitter",
                    accessibilityLabel: "DiskStation, Storage, Online",
                    accessibilityValue: "192.168.178.2, latency 1.8 ms"
                )
                DSListRow(
                    thumbnail: DeviceThumbnail(kind: .iot),
                    title: "esp_3a7f21",
                    badges: [.new],
                    subtitle: ["192.168.178.117", "Joined 1 hour ago"],
                    accessibilityLabel: "esp_3a7f21, Smart Device, Online, New device",
                    accessibilityValue: "192.168.178.117"
                ) {
                    DSPillButton("Trust") {}
                }
            }
            .dsCard()
            HStack {
                DSStateLabel(state: .online, isLive: true)
                DSStateLabel(state: .offline)
                DSCounterRow(
                    [
                        DSCounter(id: "online", systemImage: "checkmark.circle", count: 12, accessibilityLabel: "12 online"),
                        DSCounter(id: "offline", systemImage: "xmark.circle", count: 2, tone: .bad, accessibilityLabel: "2 offline"),
                    ],
                    identifierPrefix: "preview.counter",
                    onSelect: { _ in }
                )
            }
            HStack(spacing: DSLayout.space12) {
                ForEach(UptimeState.allCases, id: \.self) { state in
                    DSLegendSwatch(color: DSColor.fill(forUptime: state), title: state.title, isHatched: state == .offline, isShort: state == .noData)
                }
            }
            DSTextButton("Check All Now", systemImage: "arrow.clockwise", surface: .page) {}
            InfoBanner(
                title: "Not on Wi‑Fi",
                message: "Join the Wi‑Fi network your devices are on.",
                systemImage: "wifi.slash",
                tint: DSColor.degraded,
                actionTitle: "Open Settings",
                action: {}
            )
        }
        .padding(DSLayout.space16)
    }
    .background {
        DSColor.background.ignoresSafeArea()
    }
}
