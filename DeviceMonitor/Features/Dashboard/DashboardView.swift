import SwiftUI
import UIKit
import Combine

/// Devices tab: a search drawer, one row of filter chips and the device list in sections. Split view on
/// regular widths (iPad, iPhone Duo inner display), stack on compact.
struct DashboardView: View {
    /// Shared with the root, so the Scan and Add Device sheets zoom out of their toolbar buttons and Edit out
    /// of the detail's More menu.
    let sheetNamespace: Namespace.ID?

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dsMotion) private var motion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Namespace private var ownNamespace
    @State private var model: DashboardModel?
    @State private var now = Date()
    @State private var pendingDeletion: DeviceSnapshot?
    @State private var latencyCache: [UUID: [Double]] = [:]

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// Without a shared namespace, as in previews, the view uses its own.
    init(sheetNamespace: Namespace.ID? = nil) {
        self.sheetNamespace = sheetNamespace
    }

    var body: some View {
        @Bindable var router = environment.router

        NavigationSplitView(columnVisibility: $router.columnVisibility) {
            sidebar
                .navigationTitle("Devices")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                // Leaves 474 pt for the detail column on an 11-inch iPad in portrait.
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
        } detail: {
            if let id = router.selectedDeviceID, environment.directory.device(id: id) != nil {
                DeviceDetailView(deviceID: id, sheetNamespace: sheetNamespace)
            } else {
                EmptyStateView(
                    title: "Select a device",
                    message: "Choose a device to see its latency, history and open services.",
                    systemImage: "cursorarrow.click.2"
                )
                .background {
                    DSColor.background
                        .ignoresSafeArea()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        // A filter chosen on Overview before this tab was ever shown is applied where the model is made.
        .task {
            if model == nil {
                let created = DashboardModel(directory: environment.directory, sort: environment.settings.dashboardSort)
                created.filter = environment.router.pendingDeviceFilter ?? .all
                environment.router.pendingDeviceFilter = nil
                model = created
            }
        }
        // A filter chosen later: the list then shows exactly what the counter counted, and a pushed detail
        // pops on compact widths. While the model is nil the task above applies it.
        .onChange(of: environment.router.pendingDeviceFilter) { _, filter in
            guard let filter, let model else { return }
            model.filter = filter
            model.searchText = ""
            environment.router.pendingDeviceFilter = nil
            if sizeClass == .compact {
                environment.router.selectedDeviceID = nil
            }
        }
        // On regular widths the detail column sits beside the list, so it opens on the gateway instead
        // of an empty placeholder. Compact widths never auto-select: that would push the detail screen.
        .onChange(of: sizeClass == .regular && !environment.directory.devices.isEmpty, initial: true) { _, showsDetailColumn in
            if showsDetailColumn {
                environment.router.selectDefaultDevice(environment.directory.gatewayID ?? environment.directory.devices.first?.id)
            }
        }
        .onReceive(clock) { date in
            now = date
        }
        .confirmationDialog(
            "Remove \(pendingDeletion?.displayName ?? "device")?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let pendingDeletion {
                    environment.remove(deviceIDs: [pendingDeletion.id])
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("Its history will be deleted. It will reappear if a scan finds it again.")
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        @Bindable var router = environment.router

        if let model {
            @Bindable var bindableModel = model
            let groups = model.groups(now: now)
            // Sections and their members, so a device that moves (after Trust, or a state change) animates
            // while latency updates in place do not.
            let membership: [String] = groups.flatMap { [$0.id] + $0.devices.map(\.id.uuidString) }
            let hasDevices = !environment.directory.devices.isEmpty

            List(selection: $router.selectedDeviceID) {
                if hasDevices {
                    Section {
                        DSChipBar(
                            DashboardModel.Filter.allCases,
                            selection: $bindableModel.filter,
                            identifierPrefix: "filter",
                            accessibilityLabel: "Filter",
                            title: { filter in "\(filter.title) (\(model.count(for: filter, now: now)))" }
                        )
                        .listRowInsets(EdgeInsets(top: DSLayout.space4, leading: DSLayout.space16, bottom: DSLayout.space4, trailing: DSLayout.space16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    // Flush: the row insets and the chips' hit area already put the chips 10 pt under the field.
                    .listSectionMargins(.top, 0)
                }

                if showsBanner {
                    Section {
                        banners
                    }
                }

                if groups.isEmpty {
                    Section {
                        emptyState(filter: model.filter, query: model.searchText, hasDevices: hasDevices)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    ForEach(groups) { group in
                        Section {
                            rows(for: group)
                        } header: {
                            DSListHeader(group.title, count: group.devices.count)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("screen.devices")
            .dsGroupedList()
            // 8 pt under the search field: the first section has no header, so the grouped style would leave
            // about 45 pt.
            .contentMargins(.top, DSLayout.space8, for: .scrollContent)
            .searchable(
                text: $bindableModel.searchText,
                isPresented: $router.isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search"
            )
            .refreshable {
                environment.checkAllNow()
                try? await Task.sleep(for: .milliseconds(600))
            }
            .animation(DSMotion.animation(DSMotion.springSoft, reduceMotion: motion.reduceMotion), value: membership)
            .onChange(of: model.sort) { _, sort in
                environment.settings.dashboardSort = sort
            }
            .task(id: environment.directory.lastRoundAt) {
                refreshLatencyCache(for: environment.directory.devices)
            }
        } else {
            ProgressView()
        }
    }

    /// Permission and Wi‑Fi problems the list cannot say by itself.
    private var showsBanner: Bool {
        environment.permissionState == .denied || (!environment.pathStatus.isWiFi && !environment.isDemo)
    }

    @ViewBuilder
    private var banners: some View {
        if environment.permissionState == .denied {
            LocalNetworkDeniedBanner()
                .bannerRow()
        } else if !environment.pathStatus.isWiFi && !environment.isDemo {
            InfoBanner(
                title: environment.pathStatus.isSatisfied ? "Not on Wi‑Fi" : "No network",
                message: "Join the Wi‑Fi network your devices are on. Monitoring resumes automatically.",
                systemImage: "wifi.slash",
                tint: DSColor.degraded
            )
            .bannerRow()
        }
    }

    private func rows(for group: DashboardModel.DeviceGroup) -> some View {
        ForEach(group.devices) { device in
            if group.id == DashboardModel.newcomersGroupID {
                newcomerRow(for: device)
            } else {
                row(for: device)
            }
        }
    }

    private func row(for device: DeviceSnapshot) -> some View {
        withActions(
            NavigationLink(value: device.id) {
                DeviceRowView(device: device, samples: latencyCache[device.id] ?? [], now: now)
            }
            .accessibilityIdentifier("deviceRow.\(device.host)"),
            for: device,
            isNewcomer: false
        )
    }

    /// A device that joined and nobody has trusted yet. No link: one button opens it and one trusts it, so the
    /// row never asks two things at once. Naming lives in the context menu and the leading swipe.
    private func newcomerRow(for device: DeviceSnapshot) -> some View {
        withActions(
            HStack(spacing: DSLayout.space8) {
                Button {
                    environment.router.selectedDeviceID = device.id
                } label: {
                    DeviceRowView(device: device, samples: latencyCache[device.id] ?? [], now: now, isNewcomer: true)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("deviceRow.\(device.host)")
                DSPillButton("Trust") {
                    environment.toggleTrusted(device.id)
                }
                .accessibilityLabel("Trust \(device.displayName)")
                .accessibilityIdentifier("devices.newTrust.\(device.host)")
            },
            for: device,
            isNewcomer: true
        )
    }

    /// The same swipes and context menu on every row; a New row adds Name to the leading swipe. Favorite, Name
    /// and Check Now take the app tint, Remove the system's destructive red.
    private func withActions<Row: View>(_ row: Row, for device: DeviceSnapshot, isNewcomer: Bool) -> some View {
        let appTint = environment.settings.accent.color
        return row
            .listRowInsets(DeviceRowView.listRowInsets)
            .dsListRow()
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    environment.toggleFavorite(device.id)
                } label: {
                    Label(device.isFavorite ? "Unfavorite" : "Favorite", systemImage: device.isFavorite ? "star.slash.fill" : "star.fill")
                }
                .tint(appTint)
                if isNewcomer {
                    Button {
                        environment.router.present(.editDevice(device.id))
                    } label: {
                        Label("Name", systemImage: "pencil")
                    }
                    .tint(appTint)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    pendingDeletion = device
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                Button {
                    Task { await environment.checkNow(deviceID: device.id) }
                } label: {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
                .tint(appTint)
            }
            .contentShape(.contextMenuPreview, DSLayout.cardShape)
            .contextMenu {
                contextMenu(for: device)
            } preview: {
                DevicePreviewCard(device: device, now: now)
            }
    }

    /// Add and Sort share one glass background; a fixed spacer splits them from Scan, which is pinned to the
    /// trailing edge, the last item to move into the overflow menu. Add and Scan are the sources their sheets
    /// zoom out of. Keyboard shortcuts live in the menu-bar commands.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                environment.router.present(.addDevice)
            } label: {
                Label("Add Device", systemImage: "plus")
            }
            .tint(Color.primary)
            .accessibilityIdentifier("toolbar.addDevice")
        }
        .matchedTransitionSource(id: "add", in: sheetNamespace ?? ownNamespace)
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let model {
                    @Bindable var bindableModel = model
                    Picker(selection: $bindableModel.sort) {
                        ForEach(DashboardSortOption.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    } label: {
                        Label("Sort By", systemImage: "arrow.up.arrow.down")
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .tint(Color.primary)
            .accessibilityIdentifier("toolbar.sort")
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarPinnedTrailing) {
            Button {
                environment.router.present(.scan)
            } label: {
                Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                    .symbolEffect(
                        .variableColor.cumulative.dimInactiveLayers.reversing,
                        options: .repeat(.continuous),
                        isActive: environment.isScanning && !LaunchArguments.current.isScreenshots
                    )
            }
            .tint(Color.primary)
            .accessibilityHint("Finds devices on your Wi‑Fi network")
            .accessibilityIdentifier("toolbar.scan")
        }
        .visibilityPriority(.high)
        .matchedTransitionSource(id: "scan", in: sheetNamespace ?? ownNamespace)
    }

    /// Three groups: quick actions, what you can do with the device, and Remove on its own.
    @ViewBuilder
    private func contextMenu(for device: DeviceSnapshot) -> some View {
        ControlGroup {
            Button {
                Task { await environment.checkNow(deviceID: device.id) }
            } label: {
                Label("Check Now", systemImage: "arrow.clockwise")
            }
            Button {
                environment.toggleFavorite(device.id)
            } label: {
                Label(device.isFavorite ? "Unfavorite" : "Favorite", systemImage: device.isFavorite ? "star.slash" : "star")
            }
            Button {
                UIPasteboard.general.string = device.host
            } label: {
                Label("Copy", systemImage: "document.on.document")
            }
        }
        Section {
            Button {
                environment.toggleTrusted(device.id)
            } label: {
                Label(device.isTrusted ? "Mark as Untrusted" : "Mark as Trusted", systemImage: device.isTrusted ? "xmark.shield" : "checkmark.shield")
            }
            if let url = device.webURL {
                Link(destination: url) {
                    Label("Open Web Interface", systemImage: "globe")
                }
            }
            if device.canWake {
                Button {
                    Task { await environment.wake(deviceID: device.id) }
                } label: {
                    Label("Wake", systemImage: "power")
                }
            }
            Button {
                environment.router.present(.editDevice(device.id))
            } label: {
                Label("Edit…", systemImage: "pencil")
            }
        }
        Section {
            Button(role: .destructive) {
                pendingDeletion = device
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    /// No devices at all, no match for the search, or nothing under the selected filter.
    @ViewBuilder
    private func emptyState(filter: DashboardModel.Filter, query: String, hasDevices: Bool) -> some View {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hasDevices {
            ContentUnavailableView {
                VStack(spacing: DSLayout.space12) {
                    PingMark(style: .placeholder)
                        .frame(height: 72)
                    Text("No devices yet")
                }
            } description: {
                Text("Tap Scan to find routers, printers, speakers and everything else on your Wi‑Fi, or add a device by address.")
            } actions: {
                DSTextButton("Scan", systemImage: "dot.radiowaves.left.and.right", surface: .page) {
                    environment.router.present(.scan)
                }
                .frame(maxWidth: 280)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("devices.empty")
        } else if !trimmedQuery.isEmpty {
            ContentUnavailableView.search(text: trimmedQuery)
        } else {
            switch filter {
            case .all:
                filterEmptyState("No devices", systemImage: "circle.dashed")
            case .online:
                filterEmptyState("Nothing online", systemImage: "checkmark.circle")
            case .offline:
                filterEmptyState("Nothing offline", message: "Every device you track is answering.", systemImage: "xmark.circle")
            case .new:
                filterEmptyState("No new devices", systemImage: "sparkle")
            case .strangers:
                filterEmptyState("No strangers", systemImage: "person.crop.circle.badge.questionmark")
            case .favorites:
                filterEmptyState("No favorites", message: "Swipe right on a device to favorite it.", systemImage: "star")
            }
        }
    }

    /// A filter with nothing to show: what is missing, and the one way back.
    private func filterEmptyState(_ title: String, message: String? = nil, systemImage: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message {
                Text(message)
            }
        } actions: {
            DSTextButton("Show All", surface: .page) {
                model?.filter = .all
            }
            .frame(maxWidth: 280)
        }
    }

    private func refreshLatencyCache(for devices: [DeviceSnapshot]) {
        let since = Date().addingTimeInterval(-3600)
        var cache: [UUID: [Double]] = [:]
        for device in devices.prefix(60) where device.state.isUp {
            let samples = environment.latencySamples(deviceID: device.id, since: since)
            cache[device.id] = samples.suffix(24).map(\.milliseconds)
        }
        latencyCache = cache
    }
}

/// Peek preview for the context menu: the device's header and its two key facts.
private struct DevicePreviewCard: View {
    let device: DeviceSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: DSLayout.space12) {
            HStack(spacing: DSLayout.space12) {
                DeviceThumbnail(kind: device.kind, state: device.state, size: DSLayout.thumbnailHeader)
                VStack(alignment: .leading, spacing: DSLayout.space2) {
                    Text(device.displayName)
                        .font(DSTypography.headerName)
                        .foregroundStyle(DSColor.textPrimary)
                    Text(device.modelLine)
                        .font(DSTypography.body)
                        .foregroundStyle(DSColor.textPrimary)
                    DSStateLabel(state: device.state)
                }
            }
            VStack(spacing: 0) {
                DSStatRow("Address", value: device.host)
                if device.state.isUp {
                    DSStatRow("Latency", value: Formatters.latency(device.latencyMilliseconds), isLast: true)
                } else {
                    DSStatRow("Last seen", value: Formatters.relative(device.lastSeen, now: now), isLast: true)
                }
            }
        }
        .padding(DSLayout.space16)
        // The ideal width stands in when the preview is measured without a proposal, so the rows keep a known
        // width instead of running off the card at large text sizes.
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, alignment: .leading)
        .background {
            DSColor.card
        }
    }
}

private extension View {
    func bannerRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)
    }
}

#Preview("Devices") {
    DashboardView()
        .environment(AppEnvironment.demo())
}
