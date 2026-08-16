import SwiftUI

struct DevicesOverviewButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.monochrome)
        }
        .accessibilityLabel("Monitoring overview")
        .accessibilityHint("Opens the full-screen overview modal")
    }
}

struct DevicesToolbarTitle: View {
    let isSyncing: Bool
    let statusText: String

    var body: some View {
        VStack(spacing: 1) {
            Text("Device Monitor")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .tracking(0.18)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.88)

            Text(isSyncing ? "Checking live status" : statusText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.10)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

struct DevicesToolbarMenu: View {
    let isSyncing: Bool
    let onRefresh: () -> Void
    let onSearchRequested: () -> Void
    let onAddDevice: () -> Void

    var body: some View {
        Menu {
            Button(action: onAddDevice) {
                Label("Add Device", systemImage: "plus")
            }

            Button(action: onSearchRequested) {
                Label("Search Devices", systemImage: "magnifyingglass")
            }

            Button(action: onRefresh) {
                Label("Refresh Status", systemImage: "arrow.clockwise")
            }
            .disabled(isSyncing)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.monochrome)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("More actions")
    }
}

struct DevicesSummaryCard: View {
    let total: Int
    let online: Int
    let offline: Int
    let lastUpdatedText: String
    let isSyncing: Bool
    let onRefresh: () -> Void

    private var onlineRatio: Int {
        guard total > 0 else { return 0 }
        return Int((Double(online) / Double(total)) * 100)
    }

    private var totalSummaryText: String {
        total == 1 ? "1 device" : "\(total) devices"
    }

    private var headerMetadataText: String {
        isSyncing ? "Checking live status" : "\(totalSummaryText) • \(lastUpdatedText)"
    }

    private var healthStatusTint: Color {
        isSyncing ? AppTheme.warning : AppTheme.online
    }

    private var healthStatusText: String {
        isSyncing ? "Updating" : "Healthy"
    }

    private var healthDetailText: String {
        guard total > 0 else { return "Awaiting first check" }
        return "\(onlineRatio)% reachable"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                summaryHeaderLeading
                Spacer(minLength: 6)
                refreshAction
            }

            HStack(spacing: 8) {
                metricTile(title: "Online", value: "\(online)", tint: AppTheme.online, symbol: "checkmark.circle.fill")
                metricTile(title: "Offline", value: "\(offline)", tint: AppTheme.offline, symbol: "xmark.circle.fill")
            }

            healthRow
        }
        .padding(12)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        return ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.elevatedCardFill,
                            AppTheme.cardFill
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.03),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(shape)
        .overlay(
            shape.stroke(AppTheme.strongStroke, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadow.opacity(0.72), radius: 10, y: 6)
    }

    private var summaryHeaderLeading: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.accentFill)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Network Overview")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                ViewThatFits(in: .horizontal) {
                    Text(headerMetadataText)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .monospacedDigit()

                    Text(lastUpdatedText)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .monospacedDigit()
                }
            }
        }
        .layoutPriority(1)
    }

    private var refreshAction: some View {
        Button(action: onRefresh) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .bold))
                .frame(
                    width: AppTheme.Layout.microIconButtonSize,
                    height: AppTheme.Layout.microIconButtonSize
                )
        }
        .appCompactCircularGlassButton()
        .disabled(isSyncing)
        .accessibilityLabel("Refresh status")
    }

    private var healthRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(healthStatusTint)
                    .frame(width: 5, height: 5)

                Text(healthStatusText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(healthStatusTint.opacity(0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(healthStatusTint.opacity(0.16), lineWidth: 1)
                    )
            )

            Label(healthDetailText, systemImage: "chart.line.uptrend.xyaxis")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .monospacedDigit()

            Spacer(minLength: 0)
        }
    }

    private func metricTile(title: String, value: String, tint: Color, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(tint.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)

                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}
