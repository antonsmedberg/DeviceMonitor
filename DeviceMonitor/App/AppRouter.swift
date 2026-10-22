import Foundation
import SwiftUI
import Observation

nonisolated enum AppTab: String, Sendable, Hashable, CaseIterable {
    case overview, devices, activity, insights, settings
}

/// The sections of Insights. The router owns the selection, so Overview's shortcuts can open one.
nonisolated enum InsightsSection: String, Sendable, Hashable, CaseIterable {
    case security, map, presence

    var title: String {
        switch self {
        case .security: return "Security"
        case .map: return "Map"
        case .presence: return "Presence"
        }
    }
}

nonisolated enum AppSheet: Sendable, Hashable, Identifiable {
    case addDevice
    case scan
    case welcome
    case editDevice(UUID)

    var id: String {
        switch self {
        case .addDevice: return "add"
        case .scan: return "scan"
        case .welcome: return "welcome"
        case .editDevice(let id): return "edit-\(id.uuidString)"
        }
    }
}

/// Navigation state. Lives outside the view tree so fold/unfold and size-class changes never lose selection.
/// It records intent only (a tab and a pending filter); the screens apply the filters, because only they know
/// their size class.
@Observable
@MainActor
final class AppRouter {
    var selectedTab: AppTab = .overview
    var selectedDeviceID: UUID?
    var sheet: AppSheet?
    var columnVisibility: NavigationSplitViewVisibility = .all
    var insightsSection: InsightsSection = .security
    /// Set by Overview; DashboardView applies it to its model and sets it back to nil.
    var pendingDeviceFilter: DashboardModel.Filter?
    /// Set by Overview; ActivityTimelineView applies it to its model and sets it back to nil.
    var pendingActivityFilter: TimelineModel.Filter?
    /// Bound to the Devices search field; ⌘F sets it.
    var isSearchPresented = false
    @ObservationIgnored private var hasOfferedDefaultDevice = false

    init() {}

    /// Fills an empty detail column on regular widths with `id`, once per launch, so a later
    /// deselection by the user stays. An existing selection is kept.
    func selectDefaultDevice(_ id: UUID?) {
        guard !hasOfferedDefaultDevice, let id else { return }
        hasOfferedDefaultDevice = true
        if selectedDeviceID == nil {
            selectedDeviceID = id
        }
    }

    func showDevice(_ id: UUID) {
        selectedTab = .devices
        selectedDeviceID = id
    }

    /// Sets selectedTab = .devices and pendingDeviceFilter = filter; nothing else. The router has no size
    /// class: DashboardView owns applying the filter and popping a pushed detail on compact widths.
    func showDevices(filter: DashboardModel.Filter) {
        selectedTab = .devices
        pendingDeviceFilter = filter
    }

    /// Sets selectedTab = .activity and pendingActivityFilter = filter; nothing else.
    func showActivity(filter: TimelineModel.Filter) {
        selectedTab = .activity
        pendingActivityFilter = filter
    }

    func showInsights(_ section: InsightsSection) {
        selectedTab = .insights
        insightsSection = section
    }

    func present(_ sheet: AppSheet) {
        self.sheet = sheet
    }
}
