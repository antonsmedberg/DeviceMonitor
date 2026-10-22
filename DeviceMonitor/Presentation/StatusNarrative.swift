import Foundation

/// The one statement at the top of Devices: what is wrong, by name, and where a tap on it leads.
nonisolated struct HeaderStatus: Sendable, Hashable {
    /// Where the status card leads: a device, the Offline filter, or nowhere.
    nonisolated enum Target: Sendable, Hashable {
        case none
        case device(UUID)
        case offlineDevices
    }

    let title: String
    let subtitle: String?
    let target: Target

    init(title: String, subtitle: String?, target: Target) {
        self.title = title
        self.subtitle = subtitle
        self.target = target
    }

    /// The router comes first. Then the problems among the other devices, offline before unstable, the most
    /// recently seen first, then by name: one is named with its story, two or three are named in a list,
    /// more are counted.
    static func make(devices: [DeviceSnapshot], isPaused: Bool, pauseReason: String?, now: Date, calendar: Calendar = .current) -> HeaderStatus {
        guard !devices.isEmpty else {
            return HeaderStatus(title: "No devices yet", subtitle: "Scan to find what's on your Wi‑Fi", target: .none)
        }
        if isPaused {
            return HeaderStatus(title: "Monitoring paused", subtitle: pauseReason, target: .none)
        }
        if let gateway = devices.first(where: { $0.isGateway }) {
            switch gateway.state {
            case .offline:
                return HeaderStatus(title: "Your router isn't answering", subtitle: "Other results may be out of date", target: .device(gateway.id))
            case .degraded:
                return HeaderStatus(title: "Your router is unstable", subtitle: "Some checks are failing", target: .device(gateway.id))
            case .online, .unknown:
                break
            }
        }

        let problems = devices
            .filter { !$0.isGateway && ($0.state == .offline || $0.state == .degraded) }
            .sorted(by: precedes)
        guard let first = problems.first else {
            let isChecking = devices.contains { $0.state == .unknown } && !devices.contains { $0.state == .online }
            return HeaderStatus(title: isChecking ? "Checking devices" : "All devices answering", subtitle: nil, target: .none)
        }
        if problems.count == 1 {
            if first.state == .offline {
                let since = first.lastSeen.map { sincePhrase($0, now: now, calendar: calendar) }
                return HeaderStatus(title: "\(first.displayName) is offline", subtitle: since, target: .device(first.id))
            }
            return HeaderStatus(title: "\(first.displayName) is unstable", subtitle: "Missing some checks", target: .device(first.id))
        }

        let allOffline = problems.allSatisfy { $0.state == .offline }
        let target: Target = allOffline ? .offlineDevices : .none
        guard problems.count <= 3 else {
            return HeaderStatus(title: "\(problems.count) devices need attention", subtitle: nil, target: target)
        }
        let names = ListFormatter.localizedString(byJoining: problems.map(\.displayName))
        let predicate: String
        if allOffline {
            predicate = "are offline"
        } else if problems.allSatisfy({ $0.state == .degraded }) {
            predicate = "are unstable"
        } else {
            predicate = "need attention"
        }
        return HeaderStatus(title: "\(names) \(predicate)", subtitle: nil, target: target)
    }

    /// "Since 3:47 PM" the same day, "Since yesterday, 6:05 PM", "Since Tuesday" within the week, else
    /// "Since Oct 14, 2026".
    static func sincePhrase(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = Int((calendar.startOfDay(for: now).timeIntervalSince(calendar.startOfDay(for: date)) / 86_400).rounded())
        switch days {
        case ...0:
            return "Since \(date.formatted(date: .omitted, time: .shortened))"
        case 1:
            return "Since yesterday, \(date.formatted(date: .omitted, time: .shortened))"
        case 2...6:
            return "Since \(date.formatted(.dateTime.weekday(.wide)))"
        default:
            return "Since \(date.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    private static func precedes(_ lhs: DeviceSnapshot, _ rhs: DeviceSnapshot) -> Bool {
        if lhs.state != rhs.state {
            return lhs.state == .offline
        }
        let lhsSeen = lhs.lastSeen ?? .distantPast
        let rhsSeen = rhs.lastSeen ?? .distantPast
        if lhsSeen != rhsSeen {
            return lhsSeen > rhsSeen
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}

/// What monitoring is doing right now, said once: in the navigation subtitle, and in the tab accessory only
/// when there is news.
nonisolated struct MonitorStatus: Sendable, Hashable {
    nonisolated enum Kind: Sendable, Hashable {
        case empty
        case live
        case scanning(fraction: Double, found: Int)
        /// `reason` is nil when the user paused.
        case paused(reason: String?)
        case offWiFi
        case stale(lastRound: Date)
    }

    let kind: Kind

    init(kind: Kind) {
        self.kind = kind
    }

    /// Scanning, paused, off Wi‑Fi and stale are news; live and empty are not.
    var showsAccessory: Bool {
        switch kind {
        case .scanning, .paused, .offWiFi, .stale: return true
        case .empty, .live: return false
        }
    }

    var isLive: Bool { kind == .live }

    var symbol: String {
        switch kind {
        case .empty: return "circle.dashed"
        case .live: return "circle.fill"
        case .scanning: return "dot.radiowaves.left.and.right"
        case .paused: return "pause.circle.fill"
        case .offWiFi: return "wifi.slash"
        case .stale: return "clock.badge.exclamationmark"
        }
    }

    func headline(now: Date) -> String {
        switch kind {
        case .empty: return "No devices yet"
        case .live: return "Live"
        case .scanning(let fraction, let found): return "Scanning · \(Formatters.percent(fraction)) · \(found) found"
        case .paused(let reason): return reason ?? "Monitoring paused"
        case .offWiFi: return "Not on Wi‑Fi"
        case .stale(let lastRound): return "Last checked \(Self.lowercasingFirst(Formatters.relative(lastRound, now: now)))"
        }
    }

    func shortHeadline(now: Date) -> String {
        switch kind {
        case .empty: return "No devices"
        case .live: return "Live"
        case .scanning(let fraction, _): return "Scanning \(Formatters.percent(fraction))"
        case .paused: return "Paused"
        case .offWiFi: return "Off Wi‑Fi"
        case .stale(let lastRound): return Formatters.relative(lastRound, now: now)
        }
    }

    /// Scanning beats paused, paused beats off Wi‑Fi (never in the demo), then no devices, then a last round
    /// older than two intervals plus 10 s, then live.
    static func make(
        isScanning: Bool,
        scanProgress: ScanProgress?,
        isPausedByUser: Bool,
        pauseReason: String?,
        isOnWiFi: Bool,
        isDemo: Bool,
        hasDevices: Bool,
        lastRoundAt: Date?,
        intervalSeconds: Double,
        now: Date
    ) -> MonitorStatus {
        if isScanning {
            return MonitorStatus(kind: .scanning(fraction: scanProgress?.fraction ?? 0, found: scanProgress?.found ?? 0))
        }
        if isPausedByUser {
            return MonitorStatus(kind: .paused(reason: nil))
        }
        if let pauseReason {
            return MonitorStatus(kind: .paused(reason: pauseReason))
        }
        if !isOnWiFi && !isDemo {
            return MonitorStatus(kind: .offWiFi)
        }
        if !hasDevices {
            return MonitorStatus(kind: .empty)
        }
        if let lastRoundAt, now.timeIntervalSince(lastRoundAt) > 2 * intervalSeconds + 10 {
            return MonitorStatus(kind: .stale(lastRound: lastRoundAt))
        }
        return MonitorStatus(kind: .live)
    }

    /// "5 min ago" stays, "Yesterday, 3:47 PM" becomes "yesterday, 3:47 PM".
    private static func lowercasingFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }
}

/// A latency reading in one word, judged against the device's own history.
nonisolated enum LatencyQuality: String, Sendable, Hashable, CaseIterable {
    case fast, normal, slower, slow

    var title: String {
        switch self {
        case .fast: return "Fast"
        case .normal: return "Normal"
        case .slower: return "Slower than usual"
        case .slow: return "Slow"
        }
    }

    /// For the explanation popover.
    var explanation: String {
        switch self {
        case .fast: return "Under 10 ms and within this device's usual range."
        case .normal: return "Within twice this device's usual time."
        case .slower: return "More than twice this device's usual time."
        case .slow: return "Over 100 ms. Video calls and games will notice."
        }
    }

    /// Slow from 100 ms. With a typical band (4 samples or more), slower than usual above twice the median
    /// (and at least 1 ms above it). Fast under 10 ms and inside the band, if there is one. Otherwise normal.
    static func assess(latest: Double?, samples: [Double]) -> LatencyQuality? {
        guard let latest, latest.isFinite, latest >= 0 else { return nil }
        if latest >= 100 { return .slow }
        let band = LatencyNarrative.typicalBand(samples)
        if band != nil, let typical = median(of: samples), latest > max(2 * typical, typical + 1) {
            return .slower
        }
        if latest < 10 && (band.map { latest <= $0.upperBound } ?? true) {
            return .fast
        }
        return .normal
    }

    /// Slower than usual or slow: the row's latency gets emphasis.
    static func isOutOfBand(latest: Double?, samples: [Double]) -> Bool {
        let quality = assess(latest: latest, samples: samples)
        return quality == .slower || quality == .slow
    }

    /// Whether the detail hero says "Usually …": only with a typical band, when the reading is out of band or
    /// at least 15 % away from the median.
    static func showsTypical(latest: Double?, samples: [Double]) -> Bool {
        guard let latest, LatencyNarrative.typicalBand(samples) != nil, let typical = median(of: samples), typical > 0 else {
            return false
        }
        return isOutOfBand(latest: latest, samples: samples) || abs(latest - typical) / typical >= 0.15
    }

    /// The typical value: the median (nearest rank) of the finite, non-negative samples.
    private static func median(of samples: [Double]) -> Double? {
        let sorted = samples.filter { $0.isFinite && $0 >= 0 }.sorted()
        guard !sorted.isEmpty else { return nil }
        return LatencySummary.nearestRank(sorted, percentile: 0.5)
    }
}
