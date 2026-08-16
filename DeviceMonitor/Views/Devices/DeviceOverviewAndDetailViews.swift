import SwiftUI

struct DeviceOverviewView: View {
    let total: Int
    let online: Int
    let offline: Int
    let lastUpdatedText: String
    let onRefresh: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let statColumns = [
        GridItem(.flexible(), spacing: 12, alignment: .top),
        GridItem(.flexible(), spacing: 12, alignment: .top)
    ]

    private var onlineRate: Int {
        guard total > 0 else { return 0 }
        return Int((Double(online) / Double(total)) * 100)
    }

    var body: some View {
        DeviceModalScaffold(
            title: "Monitor Overview",
            subtitle: lastUpdatedText,
            systemImage: "waveform.path.ecg"
        ) {
            DeviceModalCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("At a glance")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("Use this view to quickly understand how healthy the monitored network looks before returning to the main list.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            overviewBadge(title: "Online Rate", value: "\(onlineRate)%", tint: AppTheme.accent)
                            overviewBadge(title: "Live", value: "\(online)", tint: AppTheme.online)
                            overviewBadge(title: "Offline", value: "\(offline)", tint: AppTheme.offline)
                        }

                        VStack(spacing: 10) {
                            overviewBadge(title: "Online Rate", value: "\(onlineRate)%", tint: AppTheme.accent)
                            overviewBadge(title: "Live", value: "\(online)", tint: AppTheme.online)
                            overviewBadge(title: "Offline", value: "\(offline)", tint: AppTheme.offline)
                        }
                    }
                }
            }

            LazyVGrid(columns: statColumns, spacing: 12) {
                overviewStatCard(title: "Devices", value: total, tint: AppTheme.accent, symbol: "square.grid.2x2")
                overviewStatCard(title: "Online", value: online, tint: AppTheme.online, symbol: "bolt.fill")
                overviewStatCard(title: "Offline", value: offline, tint: AppTheme.offline, symbol: "moon.zzz.fill")
                overviewStatCard(title: "Health", value: onlineRate, tint: AppTheme.warning, symbol: "heart.text.square.fill")
            }

            DeviceModalCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Next Action")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("Refresh if you want the latest connectivity state before returning to the dashboard.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    DeviceModalActionButton(
                        title: "Refresh Status",
                        systemImage: "arrow.clockwise",
                        action: {
                            onRefresh()
                            dismiss()
                        }
                    )
                }
            }
        }
    }

    private func overviewBadge(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .appCardStyle(
            cornerRadius: 16,
            fill: tint.opacity(0.10),
            stroke: tint.opacity(0.18),
            shadowRadius: 0,
            shadowY: 0
        )
    }

    private func overviewStatCard(title: String, value: Int, tint: Color, symbol: String) -> some View {
        DeviceModalCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)

                Text("\(value)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .monospacedDigit()

                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

struct DeviceDetailView: View {
    let device: Device

    private var sortedHistory: [StatusEvent] {
        device.statusHistory.sorted { $0.timestamp > $1.timestamp }
    }

    private var hasCompletedInitialCheck: Bool {
        device.hasCompletedInitialCheck
    }

    private var detailIconName: String {
        guard hasCompletedInitialCheck else { return "clock.badge.exclamationmark" }
        return device.isOnline ? "wave.3.right.circle.fill" : "slash.circle.fill"
    }

    private var statusColor: Color {
        guard hasCompletedInitialCheck else { return AppTheme.warning }
        return device.isOnline ? AppTheme.online : AppTheme.offline
    }

    private var statusHeadline: String {
        guard hasCompletedInitialCheck else { return "Checking device status" }
        return device.isOnline ? "Device is currently online" : "Device is currently offline"
    }

    private var statusDescription: String {
        guard hasCompletedInitialCheck else {
            return "The first status check is running now and the device state will update automatically."
        }

        if device.isOnline {
            return "The device is reachable and responding normally."
        }

        if let lastSeen = device.lastSeen {
            return "Last seen \(lastSeen.formatted(date: .abbreviated, time: .shortened))."
        }

        return "No successful status check has been recorded yet."
    }

    private var lastSeenSummaryCard: some View {
        summaryCard(
            title: "Last Seen",
            value: summaryTimestampText,
            tint: AppTheme.accent,
            symbol: "clock"
        )
    }

    private var eventsSummaryCard: some View {
        summaryCard(
            title: "Events",
            value: "\(sortedHistory.count)",
            tint: AppTheme.warning,
            symbol: "waveform.path.ecg"
        )
    }

    var body: some View {
        DeviceModalScaffold(
            title: device.name,
            subtitle: device.ipAddress,
            systemImage: detailIconName
        ) {
            statusHeroCard
            summaryStrip
            informationCard
            historyCard
        }
    }

    private var statusHeroCard: some View {
        DeviceModalCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(statusColor.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(statusColor.opacity(0.18), lineWidth: 1)
                            )

                        Image(systemName: detailIconName)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(statusColor)
                    }
                    .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(statusHeadline)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.84)

                        Text(statusDescription)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        statusBadge
                        timelineBadge
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        statusBadge
                        timelineBadge
                    }
                }
            }
        }
    }

    private var summaryStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                lastSeenSummaryCard
                eventsSummaryCard
            }

            VStack(spacing: 12) {
                lastSeenSummaryCard
                eventsSummaryCard
            }
        }
    }

    private var informationCard: some View {
        DeviceModalCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Information")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                DeviceDetailRow(label: "IP Address", value: device.ipAddress, isCopyable: true)
                Divider().opacity(0.16)

                DeviceDetailRow(
                    label: "Last Seen",
                    value: detailTimestampText
                )
                Divider().opacity(0.16)

                DeviceDetailRow(
                    label: "Status",
                    value: hasCompletedInitialCheck ? (device.isOnline ? "Online" : "Offline") : "Checking"
                )
            }
        }
    }

    private var historyCard: some View {
        DeviceModalCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Status History")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                if sortedHistory.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)

                        Text("No history yet")
                            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)

                        Text("Status changes will appear here.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    VStack(spacing: 8) {
                        ForEach(sortedHistory) { status in
                            StatusEventRow(status: status)
                        }
                    }
                }
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(hasCompletedInitialCheck ? (device.isOnline ? "Online" : "Offline") : "Checking")
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(statusColor.opacity(0.14))
        )
    }

    private var timelineBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.caption.weight(.bold))

            Text(hasCompletedInitialCheck ? "History tracked" : "First check running")
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(AppTheme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.controlFill)
        )
    }

    private func summaryCard(title: String, value: String, tint: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .appCardStyle(
            cornerRadius: AppTheme.Layout.secondaryCardCornerRadius,
            fill: AppTheme.sheetCardFill,
            stroke: AppTheme.cardStroke,
            shadowRadius: 8,
            shadowY: 6
        )
    }

    private var summaryTimestampText: String {
        if let lastSeen = device.lastSeen {
            return lastSeen.formatted(date: .omitted, time: .shortened)
        }

        if let lastStatusCheck = device.lastStatusCheck {
            return lastStatusCheck.formatted(date: .omitted, time: .shortened)
        }

        return "Checking"
    }

    private var detailTimestampText: String {
        if let lastSeen = device.lastSeen {
            return lastSeen.formatted(date: .abbreviated, time: .standard)
        }

        if let lastStatusCheck = device.lastStatusCheck {
            return "Checked \(lastStatusCheck.formatted(date: .abbreviated, time: .standard))"
        }

        return "Checking now"
    }
}
