import Foundation
import Observation

/// Filtering, search, sorting and sectioning over the directory for the Devices tab.
@Observable
@MainActor
final class DashboardModel {
    nonisolated enum Filter: String, Sendable, Hashable, CaseIterable {
        case all, online, offline, new, strangers, favorites

        var title: String {
            switch self {
            case .all: return "All"
            case .online: return "Online"
            case .offline: return "Offline"
            case .new: return "New"
            case .strangers: return "Strangers"
            case .favorites: return "Favorites"
            }
        }
    }

    /// A titled group of rows in the device list.
    nonisolated struct DeviceGroup: Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let devices: [DeviceSnapshot]

        init(id: String, title: String, devices: [DeviceSnapshot]) {
            self.id = id
            self.title = title
            self.devices = devices
        }
    }

    /// The "New on your network" section, whose rows trust in place instead of opening a link.
    static let newcomersGroupID = "newcomers"
    /// The "Needs attention" section: offline, then unstable devices.
    static let attentionGroupID = "attention"

    var filter: Filter = .all
    var sort: DashboardSortOption = .status
    var searchText: String = ""

    let directory: DeviceDirectory

    init(directory: DeviceDirectory, sort: DashboardSortOption = .status) {
        self.directory = directory
        self.sort = sort
    }

    func matches(_ device: DeviceSnapshot, filter: Filter, now: Date) -> Bool {
        switch filter {
        case .all: return true
        case .online: return device.state.isUp
        case .offline: return device.state == .offline
        case .new: return device.isRecentArrival(now: now)
        case .strangers: return device.isStranger
        case .favorites: return device.isFavorite
        }
    }

    func count(for filter: Filter, now: Date) -> Int {
        directory.devices.filter { matches($0, filter: filter, now: now) }.count
    }

    func visibleDevices(now: Date) -> [DeviceSnapshot] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var devices = directory.devices.filter { matches($0, filter: filter, now: now) }
        if !query.isEmpty {
            devices = devices.filter { Self.matchesQuery($0, query: query) }
        }
        return sorted(devices)
    }

    /// With the status sort on "All": untrusted newcomers first, then problems (offline before unstable),
    /// then the healthy devices, then the ones still being checked; each device appears once. Every other
    /// combination is one section named after the filter.
    func groups(now: Date) -> [DeviceGroup] {
        let devices = visibleDevices(now: now)
        guard !devices.isEmpty else { return [] }
        guard filter == .all, sort == .status else {
            return [DeviceGroup(id: filter.rawValue, title: filter == .all ? "All devices" : filter.title, devices: devices)]
        }
        let newcomers = devices.filter { $0.isNewcomer(now: now) }
        let others = devices.filter { !$0.isNewcomer(now: now) }
        let groups: [(id: String, title: String, devices: [DeviceSnapshot])] = [
            (Self.newcomersGroupID, "New on your network", newcomers),
            (Self.attentionGroupID, "Needs attention", others.filter { $0.state == .offline } + others.filter { $0.state == .degraded }),
            ("online", "Online", others.filter { $0.state == .online }),
            ("checking", "Checking", others.filter { $0.state == .unknown }),
        ]
        return groups.filter { !$0.devices.isEmpty }.map { DeviceGroup(id: $0.id, title: $0.title, devices: $0.devices) }
    }

    func sorted(_ devices: [DeviceSnapshot]) -> [DeviceSnapshot] {
        switch sort {
        case .status:
            return devices.sorted(by: DeviceStore.defaultOrder)
        case .name:
            return devices.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .lastSeen:
            return devices.sorted { ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast) }
        case .latency:
            return devices.sorted { lhs, rhs in
                let lhsBucket = Self.latencyBucket(lhs)
                let rhsBucket = Self.latencyBucket(rhs)
                if lhsBucket != rhsBucket { return lhsBucket < rhsBucket }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
    }

    nonisolated static func matchesQuery(_ device: DeviceSnapshot, query: String) -> Bool {
        let haystacks = [device.displayName, device.name, device.host, device.hostname ?? "", device.vendor ?? "", device.kind.title, device.macAddress ?? ""] + device.tags
        return haystacks.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// Under 5, 20 and 100 ms, then slower, then devices not answering: jitter inside a bucket never
    /// reorders rows.
    private static func latencyBucket(_ device: DeviceSnapshot) -> Int {
        guard device.state.isUp, let latency = device.latencyMilliseconds, latency.isFinite else { return 4 }
        switch latency {
        case ..<5: return 0
        case ..<20: return 1
        case ..<100: return 2
        default: return 3
        }
    }
}
