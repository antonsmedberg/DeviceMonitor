import SwiftUI

enum DevicesContentState {
    case loading
    case empty(filter: DevicesViewModel.FilterType, hasDevices: Bool)
    case loaded([Device])
}

struct DevicesContent: View {
    let state: DevicesContentState
    let onSelectDevice: (Device) -> Void
    let onDeleteID: (UUID) -> Void
    let onAddDevice: () -> Void

    var body: some View {
        switch state {
            case .loading:
                ForEach(0..<6, id: \.self) { _ in
                    DeviceCardSkeletonView()
                        .dashboardListRow(bottom: 10)
                }

            case .empty(let filter, let hasDevices):
                DevicesEmptyStateView(
                    filter: filter,
                    hasDevices: hasDevices,
                    onAddDevice: onAddDevice
                )
                .dashboardListRow(top: 2, bottom: 10)

            case .loaded(let devices):
                ForEach(devices) { device in
                    DeviceCardListRow(
                        device: device,
                        onSelect: {
                            onSelectDevice(device)
                        },
                        onDelete: {
                            onDeleteID(device.id)
                        }
                    )
                }
        }
    }
}

struct DevicesEmptyStateView: View {
    let filter: DevicesViewModel.FilterType
    let hasDevices: Bool
    let onAddDevice: () -> Void

    private var titleText: String {
        if !hasDevices {
            return "No Devices Yet"
        }

        switch filter {
            case .all:
                return "No Devices Yet"
            case .online:
                return "No Online Devices"
            case .offline:
                return "No Offline Devices"
        }
    }

    private var messageText: String {
        if !hasDevices {
            return "Start monitoring your devices by adding the first one."
        }

        switch filter {
            case .all:
                return "Start monitoring your devices by adding the first one."
            case .online:
                return "None of your tracked devices are online right now. Try refreshing or check the full list."
            case .offline:
                return "None of your tracked devices are offline right now. Try refreshing or check the full list."
        }
    }

    private var symbolName: String {
        if !hasDevices {
            return "desktopcomputer"
        }

        switch filter {
            case .all:
                return "desktopcomputer"
            case .online:
                return "checkmark.circle"
            case .offline:
                return "moon.zzz"
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 14) {
                Image(systemName: symbolName)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(width: 78, height: 78)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(AppTheme.emptyStateIconFill)
                    )

                Text(titleText)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)

                Text(messageText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            if !hasDevices {
                DeviceModalActionButton(
                    title: "Add First Device",
                    systemImage: "plus",
                    isProminent: true,
                    action: onAddDevice
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(22)
        .appCardStyle(cornerRadius: AppTheme.Layout.cardCornerRadius)
    }
}

struct DeviceSearchResultsList: View {
    let devices: [Device]
    let onSelectDevice: (Device) -> Void
    let onDeleteID: (UUID) -> Void

    var body: some View {
        List {
            ForEach(devices) { device in
                DeviceSearchResultListRow(
                    device: device,
                    onSelect: {
                        onSelectDevice(device)
                    },
                    onDelete: {
                        onDeleteID(device.id)
                    }
                )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(Color.clear)
    }
}

struct DevicesFeedbackBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.online)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .appCardStyle(
            cornerRadius: 18,
            fill: AppTheme.elevatedCardFill,
            stroke: AppTheme.strongStroke,
            shadowRadius: 8,
            shadowY: 5
        )
    }
}

struct DevicesErrorBanner: View {
    let error: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))

            Text(error)
                .font(.footnote.weight(.medium))
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.red.opacity(0.95))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .appCardStyle(
            cornerRadius: 16,
            fill: Color.red.opacity(0.11),
            stroke: Color.red.opacity(0.24),
            shadowRadius: 0,
            shadowY: 0
        )
    }
}

extension View {
    func dashboardListRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        listRowInsets(
            EdgeInsets(
                top: top,
                leading: AppTheme.Layout.screenInset,
                bottom: bottom,
                trailing: AppTheme.Layout.screenInset
            )
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
