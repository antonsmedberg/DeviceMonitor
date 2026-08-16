import SwiftUI

struct DevicesView: View {
    @ObservedObject var viewModel: DevicesViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeFullScreenDestination: FullScreenDestination?
    @State private var newDeviceName = ""
    @State private var newDeviceIP = ""
    @State private var hasPerformedInitialRefresh = false
    @State private var successMessage: String?
    @State private var successMessageTask: Task<Void, Never>?

    private enum FullScreenDestination: Identifiable {
        case addDevice
        case search
        case overview
        case detail(Device)

        var id: String {
            switch self {
                case .addDevice:
                    return "add-device"
                case .search:
                    return "search"
                case .overview:
                    return "overview"
                case .detail(let device):
                    return "detail-\(device.id.uuidString)"
            }
        }
    }

    private var contentState: DevicesContentState {
        if viewModel.isLoading && viewModel.devices.isEmpty {
            return .loading
        }

        if viewModel.filteredDevices.isEmpty {
            return .empty(
                filter: viewModel.selectedFilter,
                hasDevices: !viewModel.devices.isEmpty
            )
        }

        return .loaded(viewModel.filteredDevices)
    }

    private var toolbarStatusText: String {
        guard viewModel.allCount > 0 else { return "No devices yet" }
        if viewModel.checkingCount > 0 {
            return "\(viewModel.onlineCount) online | \(viewModel.offlineCount) offline | \(viewModel.checkingCount) checking"
        }

        return "\(viewModel.onlineCount) online | \(viewModel.offlineCount) offline"
    }

    private var lastUpdatedText: String {
        guard let lastRefreshAt = viewModel.lastRefreshAt else {
            return "Awaiting first live status check"
        }

        return "Updated \(lastRefreshAt.formatted(date: .omitted, time: .shortened))"
    }

    private var summaryCardUpdatedText: String {
        guard let lastRefreshAt = viewModel.lastRefreshAt else {
            return "First check pending"
        }

        return "Updated \(lastRefreshAt.formatted(date: .omitted, time: .shortened))"
    }

    private var feedbackTransition: AnyTransition {
        reduceMotion
        ? .opacity
        : .move(edge: .top).combined(with: .opacity)
    }

    private var shouldPerformInitialRefresh: Bool {
        !AppModelFactory.isRunningForPreviews
    }

    var body: some View {
        ZStack {
            AppScreenBackground()

            List {
                Section {
                    if let error = viewModel.lastError {
                        DevicesErrorBanner(error: error)
                            .dashboardListRow(top: 8, bottom: 10)
                    }

                    DevicesSummaryCard(
                        total: viewModel.allCount,
                        online: viewModel.onlineCount,
                        offline: viewModel.offlineCount,
                        lastUpdatedText: summaryCardUpdatedText,
                        isSyncing: viewModel.isLoading,
                        onRefresh: refreshDevices
                    )
                    .dashboardListRow(top: 6, bottom: 10)

                    DevicesContent(
                        state: contentState,
                        onSelectDevice: presentDetail,
                        onDeleteID: deleteDevice,
                        onAddDevice: {
                            activeFullScreenDestination = .addDevice
                        }
                    )

                    Color.clear
                        .frame(height: 18)
                        .dashboardListRow()
                } header: {
                    stickyFilterBar
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .top) {
            if let successMessage {
                DevicesFeedbackBanner(message: successMessage)
                    .padding(.horizontal, AppTheme.Layout.screenInset)
                    .padding(.top, 8)
                    .transition(feedbackTransition)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(id: "devices.overview", placement: .topBarLeading) {
                DevicesOverviewButton(
                    action: {
                        activeFullScreenDestination = .overview
                    }
                )
            }

            ToolbarItem(id: "devices.title", placement: .principal) {
                DevicesToolbarTitle(
                    isSyncing: viewModel.isLoading,
                    statusText: toolbarStatusText
                )
            }

            ToolbarItem(id: "devices.actions", placement: .topBarTrailing) {
                DevicesToolbarMenu(
                    isSyncing: viewModel.isLoading,
                    onRefresh: refreshDevices,
                    onSearchRequested: {
                        activeFullScreenDestination = .search
                    },
                    onAddDevice: {
                        activeFullScreenDestination = .addDevice
                    }
                )
            }
        }
        .task {
            guard shouldPerformInitialRefresh else { return }
            guard !hasPerformedInitialRefresh else { return }
            hasPerformedInitialRefresh = true
            await viewModel.refresh()
        }
        .onDisappear {
            successMessageTask?.cancel()
            successMessageTask = nil
        }
        .fullScreenCover(
            item: $activeFullScreenDestination,
            onDismiss: resetTransientState
        ) { destination in
            fullScreenDestinationView(for: destination)
        }
        .fontDesign(.rounded)
    }

    private var stickyFilterBar: some View {
        DevicesFilterBar(
            selectedFilter: viewModel.selectedFilter,
            onSelect: viewModel.setFilter
        )
        .padding(.horizontal, AppTheme.Layout.screenInset)
        .padding(.top, 0)
        .padding(.bottom, 6)
        .background(Color.clear)
        .textCase(nil)
    }

    @ViewBuilder
    private func fullScreenDestinationView(for destination: FullScreenDestination) -> some View {
        switch destination {
            case .addDevice:
                AddDeviceView(
                    newName: $newDeviceName,
                    newIP: $newDeviceIP,
                    onSave: saveDevice
                )
            case .search:
                DeviceSearchView(
                    devices: viewModel.devices,
                    onDeleteID: deleteDevice,
                    onAddDevice: {
                        activeFullScreenDestination = .addDevice
                    }
                )
            case .overview:
                DeviceOverviewView(
                    total: viewModel.allCount,
                    online: viewModel.onlineCount,
                    offline: viewModel.offlineCount,
                    lastUpdatedText: lastUpdatedText,
                    onRefresh: refreshDevices
                )
            case .detail(let device):
                DeviceDetailView(device: device)
        }
    }

    private func refreshDevices() {
        Task {
            await viewModel.refresh()
        }
    }

    private func presentDetail(_ device: Device) {
        activeFullScreenDestination = .detail(device)
    }

    private func deleteDevice(_ id: UUID) {
        viewModel.delete(deviceIDs: [id])
    }

    private func saveDevice() -> Bool {
        let trimmedName = newDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIP = newDeviceIP.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, IPv4Validator.isValid(trimmedIP) else {
            return false
        }

        viewModel.add(
            deviceDTO: DeviceDTO(
                name: trimmedName,
                ipAddress: trimmedIP,
                isUserAdded: true
            )
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showSuccessMessage("Added \(trimmedName)")
        resetTransientState()
        return true
    }

    private func resetTransientState() {
        newDeviceName = ""
        newDeviceIP = ""
    }

    private func showSuccessMessage(_ message: String) {
        successMessageTask?.cancel()

        let presentAnimation: Animation = reduceMotion
        ? .easeOut(duration: 0.16)
        : .spring(response: 0.34, dampingFraction: 0.9)

        withAnimation(presentAnimation) {
            successMessage = message
        }

        successMessageTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.2)) {
                successMessage = nil
            }
        }
    }
}
