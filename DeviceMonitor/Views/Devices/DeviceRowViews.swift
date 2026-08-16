import SwiftUI

struct DeviceCardListRow: View {
    let device: Device
    let onSelect: () -> Void
    let onDelete: () -> Void

    private var tappableRow: some View {
        Button(action: onSelect) {
            DeviceCardView(device: device)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    var body: some View {
        tappableRow
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive, action: onDelete) {
                    Label("Remove", systemImage: "trash")
                }
            }
            .dashboardListRow(bottom: 10)
    }
}

private struct DeviceCardView: View {
    let device: Device

    var body: some View {
        DeviceRowContent(device: device, style: .primary)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens device details")
    }
}

private struct DeviceSearchResultRow: View {
    let device: Device

    var body: some View {
        DeviceRowContent(device: device, style: .search)
    }
}

struct DeviceCardSkeletonView: View {
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 150, height: 17)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 120, height: 12)

                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                    .frame(width: 180, height: 24)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(minHeight: 84)
        .background(DeviceRowBackground(cornerRadius: 22, elevated: true))
        .redacted(reason: .placeholder)
    }
}

struct DeviceSearchResultListRow: View {
    let device: Device
    let onSelect: () -> Void
    let onDelete: () -> Void

    private var tappableRow: some View {
        Button(action: onSelect) {
            DeviceSearchResultRow(device: device)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    var body: some View {
        tappableRow
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive, action: onDelete) {
                    Label("Remove", systemImage: "trash")
                }
            }
            .dashboardListRow(bottom: 8)
    }
}

private struct DeviceSourceBadge: View {
    var body: some View {
        Text("Manual")
            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.accent.opacity(0.9))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.accentFill.opacity(0.78))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(AppTheme.accent.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}

private struct DeviceRowContent: View {
    let device: Device
    let style: DeviceRowStyle

    private var statusSummary: some View {
        DeviceStatusSummary(
            statusColor: device.displayStatusColor,
            statusText: device.displayStatusLabel,
            detailIconName: device.displayStatusSecondaryIconName,
            detailText: device.displayStatusDetailText,
            accessibilityDetailText: device.displayStatusAccessibilityDetailText,
            style: style.summaryStyle
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: style.rowSpacing) {
            DeviceStatusIconBadge(
                device: device,
                size: style.iconSize,
                cornerRadius: style.iconCornerRadius
            )

            VStack(alignment: .leading, spacing: style.contentSpacing) {
                HStack(alignment: .center, spacing: 8) {
                    Text(device.name)
                        .font(style.titleFont)
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(style.nameMinimumScale)
                        .layoutPriority(1)

                    Spacer(minLength: 0)

                    if device.isUserAdded {
                        DeviceSourceBadge()
                            .fixedSize()
                    }
                }

                DeviceAddressLine(
                    ipAddress: device.ipAddress,
                    compact: style == .search
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusSummary
                .frame(minWidth: style.statusMinWidth, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)

            if style.showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.tertiaryText.opacity(0.72))
            }
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .frame(minHeight: style.minHeight)
        .background(
            DeviceRowBackground(
                cornerRadius: style.cornerRadius,
                elevated: style.isElevated
            )
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: style.cornerRadius,
                style: .continuous
            )
        )
    }
}

private struct DeviceStatusSummary: View {
    let statusColor: Color
    let statusText: String
    let detailIconName: String
    let detailText: String
    let accessibilityDetailText: String
    let style: DeviceStatusSummaryStyle

    var body: some View {
        VStack(alignment: .trailing, spacing: style.stackSpacing) {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: style.dotSize, height: style.dotSize)

                Text(statusText)
                    .font(style.statusFont)
                    .lineLimit(1)
            }
            .foregroundStyle(statusColor.opacity(0.98))
            .padding(.horizontal, style.statusHorizontalPadding)
            .padding(.vertical, style.statusVerticalPadding)
            .background(
                Capsule(style: .continuous)
                    .fill(statusColor.opacity(0.11))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(statusColor.opacity(0.15), lineWidth: 1)
            )

            HStack(spacing: 4) {
                Image(systemName: detailIconName)
                    .font(style.detailIconFont)
                    .frame(width: style.detailIconWidth)

                Text(detailText)
                    .font(style.detailFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
                    .monospacedDigit()
            }
            .foregroundStyle(AppTheme.secondaryText.opacity(0.92))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(statusText), \(accessibilityDetailText)")
    }
}

private struct DeviceStatusIconBadge: View {
    let device: Device
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.controlFill)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(device.displayStatusColor.opacity(0.10))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(device.displayStatusColor.opacity(0.24), lineWidth: 1)

            Image(systemName: device.displayStatusIconName)
                .font(.system(size: size * 0.38, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(device.displayStatusColor)
        }
        .frame(width: size, height: size)
        .shadow(color: device.displayStatusColor.opacity(0.10), radius: 5, y: 2)
    }
}

private struct DeviceAddressLine: View {
    let ipAddress: String
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "network")
                .font(.system(size: compact ? 9 : 9.5, weight: .bold))
                .foregroundStyle(AppTheme.tertiaryText)

            Text(ipAddress)
                .font(.system(size: compact ? 10.5 : 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DeviceRowBackground: View {
    let cornerRadius: CGFloat
    let elevated: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let baseFill = elevated ? AppTheme.elevatedCardFill : AppTheme.cardFill

        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            baseFill,
                            AppTheme.cardFill
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            LinearGradient(
                colors: [
                    Color.white.opacity(elevated ? 0.05 : 0.03),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(shape)
        }
        .overlay(
            shape.stroke(AppTheme.cardStroke.opacity(elevated ? 1 : 0.92), lineWidth: 1)
        )
        .shadow(
            color: AppTheme.shadow.opacity(elevated ? 0.44 : 0.20),
            radius: elevated ? 5 : 0,
            y: elevated ? 3 : 0
        )
    }
}

private enum DeviceRowStyle {
    case primary
    case search

    var rowSpacing: CGFloat {
        switch self {
            case .primary: 14
            case .search: 10
        }
    }

    var contentSpacing: CGFloat {
        switch self {
            case .primary: 6
            case .search: 4
        }
    }

    var iconSize: CGFloat {
        switch self {
            case .primary: 46
            case .search: 38
        }
    }

    var iconCornerRadius: CGFloat {
        switch self {
            case .primary: 15
            case .search: 13
        }
    }

    var titleFont: Font {
        switch self {
            case .primary:
                .system(size: 14.5, weight: .semibold, design: .rounded)
            case .search:
                .system(size: 13.5, weight: .semibold, design: .rounded)
        }
    }

    var nameMinimumScale: CGFloat {
        switch self {
            case .primary: 0.84
            case .search: 0.82
        }
    }

    var statusMinWidth: CGFloat {
        switch self {
            case .primary: 88
            case .search: 84
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
            case .primary: 16
            case .search: 14
        }
    }

    var verticalPadding: CGFloat {
        switch self {
            case .primary: 13
            case .search: 12
        }
    }

    var minHeight: CGFloat {
        switch self {
            case .primary: 84
            case .search: 70
        }
    }

    var cornerRadius: CGFloat {
        switch self {
            case .primary: 22
            case .search: 18
        }
    }

    var isElevated: Bool {
        switch self {
            case .primary: true
            case .search: false
        }
    }

    var showsChevron: Bool {
        switch self {
            case .primary: true
            case .search: false
        }
    }

    var summaryStyle: DeviceStatusSummaryStyle {
        switch self {
            case .primary: .regular
            case .search: .compact
        }
    }
}

private enum DeviceStatusSummaryStyle {
    case regular
    case compact

    var stackSpacing: CGFloat {
        switch self {
            case .regular: 6
            case .compact: 5
        }
    }

    var dotSize: CGFloat {
        switch self {
            case .regular: 6
            case .compact: 5
        }
    }

    var statusFont: Font {
        switch self {
            case .regular:
                .system(size: 9.5, weight: .semibold, design: .rounded)
            case .compact:
                .system(size: 9, weight: .semibold, design: .rounded)
        }
    }

    var statusHorizontalPadding: CGFloat {
        switch self {
            case .regular: 8
            case .compact: 7
        }
    }

    var statusVerticalPadding: CGFloat {
        switch self {
            case .regular: 4
            case .compact: 3.5
        }
    }

    var detailIconFont: Font {
        switch self {
            case .regular:
                .system(size: 8.5, weight: .bold)
            case .compact:
                .system(size: 8, weight: .bold)
        }
    }

    var detailIconWidth: CGFloat {
        switch self {
            case .regular: 10
            case .compact: 9
        }
    }

    var detailFont: Font {
        switch self {
            case .regular:
                .system(size: 9.5, weight: .medium, design: .rounded)
            case .compact:
                .system(size: 9, weight: .medium, design: .rounded)
        }
    }
}

@MainActor
private extension Device {
    var displayStatusColor: Color {
        guard hasCompletedInitialCheck else { return AppTheme.warning }
        return isOnline ? AppTheme.online : AppTheme.offline
    }

    var displayStatusLabel: String {
        guard hasCompletedInitialCheck else { return "Checking" }
        return isOnline ? "Online" : "Offline"
    }

    var displayStatusDetailText: String {
        guard hasCompletedInitialCheck else { return "Pending" }

        if isOnline {
            return "Now"
        }

        if let lastSeen {
            return lastSeen.formatted(date: .omitted, time: .shortened)
        }

        if let lastStatusCheck {
            return lastStatusCheck.formatted(date: .omitted, time: .shortened)
        }

        return "No data"
    }

    var displayStatusAccessibilityDetailText: String {
        guard hasCompletedInitialCheck else { return "Awaiting first check" }

        if isOnline {
            return "Live now"
        }

        if let lastSeen {
            return "Last seen at \(lastSeen.formatted(date: .omitted, time: .shortened))"
        }

        if let lastStatusCheck {
            return "Checked at \(lastStatusCheck.formatted(date: .omitted, time: .shortened))"
        }

        return "No recent check"
    }

    var displayStatusSecondaryIconName: String {
        guard hasCompletedInitialCheck else { return "clock.fill" }
        return isOnline ? "dot.radiowaves.left.and.right" : "clock.fill"
    }

    var displayStatusIconName: String {
        guard hasCompletedInitialCheck else { return "clock.badge.exclamationmark" }
        return isOnline ? "wave.3.right.circle.fill" : "slash.circle.fill"
    }
}
