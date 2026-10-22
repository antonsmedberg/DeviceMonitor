import Foundation

/// The Overview counters. Each uses the predicate of the Devices filter it opens, so a counter always
/// equals the list behind it.
nonisolated struct NetworkCounters: Sendable, Hashable {
    /// Online and unstable: the Devices "Online" filter.
    let online: Int
    let offline: Int
    /// The "New" filter.
    let recentArrivals: Int
    /// The "Strangers" filter.
    let strangers: Int

    init(online: Int, offline: Int, recentArrivals: Int, strangers: Int) {
        self.online = online
        self.offline = offline
        self.recentArrivals = recentArrivals
        self.strangers = strangers
    }

    static let zero = NetworkCounters(online: 0, offline: 0, recentArrivals: 0, strangers: 0)

    static func make(devices: [DeviceSnapshot], now: Date) -> NetworkCounters {
        NetworkCounters(
            online: devices.filter { $0.state.isUp }.count,
            offline: devices.filter { $0.state == .offline }.count,
            recentArrivals: devices.filter { $0.isRecentArrival(now: now) }.count,
            strangers: devices.filter { $0.isStranger }.count
        )
    }
}

nonisolated enum OverviewAttention {
    /// The Devices "Needs attention" membership: offline devices (most recently seen first), then unstable
    /// ones (by name). Newcomers are not included (the New counter covers them), so the count matches Devices.
    static func devices(_ devices: [DeviceSnapshot], now: Date) -> [DeviceSnapshot] {
        let candidates = devices.filter { !$0.isNewcomer(now: now) }
        let offline = candidates
            .filter { $0.state == .offline }
            .sorted { lhs, rhs in
                let lhsSeen = lhs.lastSeen ?? .distantPast
                let rhsSeen = rhs.lastSeen ?? .distantPast
                if lhsSeen != rhsSeen { return lhsSeen > rhsSeen }
                return byName(lhs, rhs)
            }
        let unstable = candidates
            .filter { $0.state == .degraded }
            .sorted(by: byName)
        return offline + unstable
    }

    private static func byName(_ lhs: DeviceSnapshot, _ rhs: DeviceSnapshot) -> Bool {
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}

/// Latency across the network: one value per answering device.
nonisolated enum ResponseTime {
    /// The latest latency of every answering device, ascending.
    static func latencies(_ devices: [DeviceSnapshot]) -> [Double] {
        devices
            .filter { $0.state.isUp }
            .compactMap(\.latencyMilliseconds)
            .filter { $0.isFinite && $0 >= 0 }
            .sorted()
    }

    /// Nearest rank; nil when no device answers.
    static func median(_ devices: [DeviceSnapshot]) -> Double? {
        let sorted = latencies(devices)
        guard !sorted.isEmpty else { return nil }
        return LatencySummary.nearestRank(sorted, percentile: 0.5)
    }
}

/// Availability in words. The app only sees state changes while it is open, so history is told as
/// outages seen and time down, never as a percentage over a span.
nonisolated enum AvailabilityNarrative {
    /// The caption under every status-history view.
    static let seenWhileOpenCaption = "Changes seen while DeviceMonitor was open"

    /// "Router down" (.bad) when the gateway is offline now; "No outages seen" (.good); "1 outage seen" /
    /// "n outages seen" (.warn); "No data yet" (.neutral) before any cell has data. Never a percentage.
    static func statusWord(cells: [UptimeCell], isGatewayDown: Bool) -> DSStatusWord {
        if isGatewayDown {
            return DSStatusWord("Router down", tone: .bad)
        }
        guard hasData(cells) else {
            return DSStatusWord("No data yet", tone: .neutral)
        }
        let count = outagesSeen(cells)
        return DSStatusWord(outagesPhrase(count), tone: count == 0 ? .good : .warn)
    }

    /// Outages (a count, no tone), then the trailing Down duration (tone .bad when above zero). No "Up %".
    static func summary(cells: [UptimeCell]) -> (items: [DSSummaryItem], trailing: DSSummaryItem?) {
        guard hasData(cells) else {
            return (
                [DSSummaryItem(id: "outages", label: "Outages", value: "—", spokenValue: "no data yet")],
                DSSummaryItem(id: "down", label: "Down", value: "—", spokenValue: "no data yet")
            )
        }
        let count = outagesSeen(cells)
        let down = downSeconds(cells)
        let outages = DSSummaryItem(id: "outages", label: "Outages", value: "\(count)")
        let trailing = DSSummaryItem(
            id: "down",
            label: "Down",
            value: down > 0 ? Formatters.duration(down) : "0 min",
            tone: down > 0 ? .bad : nil,
            spokenValue: down > 0 ? spokenDuration(down) : "0 minutes"
        )
        return ([outages], trailing)
    }

    /// What a strip reads to VoiceOver without a selection: "No outages seen" or
    /// "1 outage seen, 12 minutes down".
    static func spokenSummary(cells: [UptimeCell]) -> String {
        guard hasData(cells) else { return "No data yet" }
        let phrase = outagesPhrase(outagesSeen(cells))
        let down = downSeconds(cells)
        return down > 0 ? "\(phrase), \(spokenDuration(down)) down" : phrase
    }

    /// "45 seconds", "12 minutes", "1.5 hours", "3 days": `Formatters.duration` in words.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return Formatters.count(Int(seconds.rounded()), singular: "second", plural: "seconds")
        }
        if seconds < 3600 {
            return Formatters.count(Int((seconds / 60).rounded()), singular: "minute", plural: "minutes")
        }
        let hours = seconds / 3600
        if hours < 48 {
            return String(format: "%.1f hours", hours)
        }
        return Formatters.count(Int((hours / 24).rounded()), singular: "day", plural: "days")
    }

    /// Outages that started in the cells; a stretch of down time that started earlier counts as one seen.
    static func outagesSeen(_ cells: [UptimeCell]) -> Int {
        let started = cells.reduce(0) { $0 + $1.outages }
        return max(started, downSeconds(cells) > 0 ? 1 : 0)
    }

    private static func downSeconds(_ cells: [UptimeCell]) -> TimeInterval {
        cells.reduce(0) { $0 + $1.offlineSeconds }
    }

    private static func hasData(_ cells: [UptimeCell]) -> Bool {
        cells.contains { $0.state != .noData }
    }

    private static func outagesPhrase(_ count: Int) -> String {
        count == 0 ? "No outages seen" : "\(Formatters.count(count, singular: "outage", plural: "outages")) seen"
    }
}
