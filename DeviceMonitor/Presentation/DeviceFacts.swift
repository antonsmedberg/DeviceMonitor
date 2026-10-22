import Foundation

extension DeviceSnapshot {
    /// Seen for the first time in the last day and not added by hand (the Devices "New" filter).
    nonisolated func isRecentArrival(now: Date) -> Bool {
        isNew(now: now) && !isUserAdded
    }

    /// A recent arrival nobody has trusted yet.
    nonisolated func isNewcomer(now: Date) -> Bool {
        isRecentArrival(now: now) && isStranger
    }

    /// "Synology · Storage": the vendor when it differs from the display name, then the kind.
    nonisolated var modelLine: String {
        if let vendor, !vendor.isEmpty, vendor != displayName {
            return "\(vendor) · \(kind.title)"
        }
        return kind.title
    }
}

/// What one device row says: the subtitle segments, the trailing metrics and what VoiceOver reads.
nonisolated struct DeviceRowFacts: Sendable, Hashable {
    let subtitle: [String]
    /// Shorter subtitles for a narrow row, longest first, each one whole segment less: the state word drops
    /// out first, then the maker (a newcomer keeps "Joined …" over its maker), down to the address alone.
    let subtitleFallbacks: [[String]]
    let primary: String?
    let primaryTone: DSTone
    let secondary: String?
    let accessibilityLabel: String
    let accessibilityValue: String

    /// `samples`: the last hour's latency values, oldest first. A newcomer row has no trailing metrics,
    /// because its Trust button sits there.
    static func make(device: DeviceSnapshot, samples: [Double], now: Date, isNewcomer: Bool) -> DeviceRowFacts {
        let joinedWhen = relativePhrase(device.firstSeen, now: now)
        let joined = "Joined \(joinedWhen)"
        let address = device.host
        let madeBy = maker(of: device)
        // An offline row says when it was last seen in its trailing column, so the subtitle does not repeat it.
        let subtitle: [String]
        let subtitleFallbacks: [[String]]
        if isNewcomer {
            subtitle = [address, madeBy, joined]
            subtitleFallbacks = [[address, joined], [address]]
        } else if device.state == .degraded {
            subtitle = [address, madeBy, "Unstable"]
            subtitleFallbacks = [[address, madeBy], [address]]
        } else {
            subtitle = [address, madeBy]
            subtitleFallbacks = [[address]]
        }

        let latency = device.state.isUp ? device.latencyMilliseconds : nil
        let jitter: Double?
        if device.state.isUp, let summary = LatencySummary(samples: samples), summary.count >= 2 {
            jitter = summary.jitter
        } else {
            jitter = nil
        }

        let primary: String?
        let tone: DSTone
        let secondary: String?
        if isNewcomer {
            primary = nil
            tone = .neutral
            secondary = nil
        } else {
            switch device.state {
            case .online, .degraded:
                primary = latency.map { Formatters.latency($0) } ?? "—"
                if device.state == .degraded {
                    tone = .warn
                } else {
                    tone = LatencyQuality.assess(latest: latency, samples: samples)?.tone ?? .neutral
                }
                secondary = jitter.map { "\(Formatters.latency($0)) jitter" }
            case .offline:
                primary = "Offline"
                tone = .bad
                secondary = device.lastSeen.map { Formatters.relative($0, now: now) }
            case .unknown:
                primary = "Checking"
                tone = .neutral
                secondary = nil
            }
        }

        var label = [device.displayName, device.kind.title, device.state.title]
        if device.isFavorite { label.append("Favorite") }
        if device.isNewcomer(now: now) { label.append("New device") }

        var value = [device.host]
        if isNewcomer { value.append("joined \(joinedWhen)") }
        if let latency { value.append("latency \(Formatters.latency(latency))") }
        if let jitter { value.append("jitter \(Formatters.latency(jitter))") }
        if device.state == .offline, let lastSeen = device.lastSeen {
            value.append("last seen \(relativePhrase(lastSeen, now: now))")
        }

        return DeviceRowFacts(
            subtitle: subtitle,
            subtitleFallbacks: subtitleFallbacks,
            primary: primary,
            primaryTone: tone,
            secondary: secondary,
            accessibilityLabel: label.joined(separator: ", "),
            accessibilityValue: value.joined(separator: ", ")
        )
    }

    /// The vendor unless it is the name itself, else the kind.
    private static func maker(of device: DeviceSnapshot) -> String {
        if let vendor = device.vendor, !vendor.isEmpty, vendor != device.displayName {
            return vendor
        }
        return device.kind.title
    }

    /// `Formatters.relative` inside a sentence: "Just now", "Today, …" and "Yesterday, …" start in lower case;
    /// "5 min ago" and dates ("Oct 14, 2026") stay as they are.
    private static func relativePhrase(_ date: Date, now: Date) -> String {
        let text = Formatters.relative(date, now: now)
        for word in ["Just", "Today", "Yesterday"] where text.hasPrefix(word) {
            return word.lowercased() + text.dropFirst(word.count)
        }
        return text
    }
}

/// The detail's unlabelled info grid: four rows of values that describe themselves.
nonisolated enum DeviceInfoGrid {
    /// Always four rows. `samples`: the last day's latency values, oldest first (for `LatencyQuality`);
    /// `outagesSeen`: `AvailabilityNarrative.outagesSeen` of `UptimeCells.days(count: 30, …)`, nil when no
    /// cell has data; `openPortCount`: nil when ports were never checked.
    static func rows(device: DeviceSnapshot, samples: [Double], outagesSeen: Int?, openPortCount: Int?, now: Date) -> [DSInfoRow] {
        [
            DSInfoRow(id: "addressing", leading: address(device), trailing: mac(device)),
            DSInfoRow(id: "latency", leading: latency(device, samples: samples), trailing: hostname(device)),
            DSInfoRow(id: "history", leading: seenSince(device, now: now), trailing: outages(outagesSeen)),
            DSInfoRow(id: "ports", leading: ports(openPortCount), trailing: trust(device)),
        ]
    }

    private static func address(_ device: DeviceSnapshot) -> DSInfoItem {
        DSInfoItem(id: "address", text: device.host, systemImage: "network", accessibilityLabel: "IP address, \(device.host)", isCopyable: true)
    }

    private static func mac(_ device: DeviceSnapshot) -> DSInfoItem {
        guard let mac = device.macAddress, !mac.isEmpty else {
            return DSInfoItem(id: "mac", text: "MAC unknown", emphasis: .tertiary, accessibilityLabel: "MAC address unknown")
        }
        return DSInfoItem(id: "mac", text: mac, accessibilityLabel: "MAC address, \(mac)", isCopyable: true)
    }

    /// Primary when the reading is usual; the warn or bad ink only when it is slower than usual or slow,
    /// so a latency beside the cyan chart legend is never mint.
    private static func latency(_ device: DeviceSnapshot, samples: [Double]) -> DSInfoItem {
        switch device.state {
        case .offline:
            return DSInfoItem(id: "latency", text: "Offline", systemImage: "bolt.horizontal", emphasis: .tone(.bad), accessibilityLabel: "Offline, no latency")
        case .unknown:
            return DSInfoItem(id: "latency", text: "Checking", systemImage: "bolt.horizontal", emphasis: .tertiary, accessibilityLabel: "Latency, checking")
        case .online, .degraded:
            guard let milliseconds = device.latencyMilliseconds, milliseconds.isFinite, milliseconds >= 0 else {
                return DSInfoItem(id: "latency", text: "No reading yet", systemImage: "bolt.horizontal", emphasis: .tertiary, accessibilityLabel: "Latency, no reading yet")
            }
            let emphasis: DSInfoItem.Emphasis
            switch LatencyQuality.assess(latest: milliseconds, samples: samples) {
            case .slower: emphasis = .tone(.warn)
            case .slow: emphasis = .tone(.bad)
            case .fast, .normal, nil: emphasis = .primary
            }
            let text = Formatters.latency(milliseconds)
            return DSInfoItem(id: "latency", text: text, systemImage: "bolt.horizontal", emphasis: emphasis, accessibilityLabel: "Latency, \(text)")
        }
    }

    private static func hostname(_ device: DeviceSnapshot) -> DSInfoItem? {
        guard let hostname = device.hostname, !hostname.isEmpty else { return nil }
        return DSInfoItem(id: "hostname", text: hostname, accessibilityLabel: "Hostname, \(hostname)", isCopyable: true)
    }

    private static func seenSince(_ device: DeviceSnapshot, now: Date) -> DSInfoItem {
        let sameYear = Calendar.current.isDate(device.firstSeen, equalTo: now, toGranularity: .year)
        let date = sameYear
            ? device.firstSeen.formatted(.dateTime.month(.abbreviated).day())
            : device.firstSeen.formatted(.dateTime.month(.abbreviated).day().year())
        let text = "Seen since \(date)"
        return DSInfoItem(id: "seen", text: text, systemImage: "calendar", emphasis: .secondary, accessibilityLabel: text)
    }

    /// A count of outages seen, never a percentage: the app only watches while it is open.
    private static func outages(_ count: Int?) -> DSInfoItem {
        guard let count else {
            return DSInfoItem(id: "outages", text: "No history yet", emphasis: .tertiary, accessibilityLabel: "No history yet")
        }
        if count == 0 {
            return DSInfoItem(id: "outages", text: "No outages seen · 30D", emphasis: .secondary, accessibilityLabel: "No outages seen in 30 days")
        }
        let seen = "\(Formatters.count(count, singular: "outage", plural: "outages")) seen"
        return DSInfoItem(id: "outages", text: "\(seen) · 30D", emphasis: .tone(.warn), accessibilityLabel: "\(seen) in 30 days")
    }

    private static func ports(_ count: Int?) -> DSInfoItem {
        guard let count else {
            return DSInfoItem(id: "ports", text: "Ports not checked", systemImage: "network.badge.shield.half.filled", emphasis: .tertiary, accessibilityLabel: "Ports not checked")
        }
        let text = count == 0 ? "No open ports" : Formatters.count(count, singular: "open port", plural: "open ports")
        return DSInfoItem(id: "ports", text: text, systemImage: "network.badge.shield.half.filled", emphasis: .secondary, accessibilityLabel: text)
    }

    private static func trust(_ device: DeviceSnapshot) -> DSInfoItem {
        if device.isStranger {
            return DSInfoItem(id: "trust", text: "Stranger", emphasis: .tone(.warn), accessibilityLabel: "Stranger, not trusted yet")
        }
        if device.isUserAdded && !device.isTrusted {
            return DSInfoItem(id: "trust", text: "Added by you", emphasis: .secondary, accessibilityLabel: "Added by you")
        }
        return DSInfoItem(id: "trust", text: "Trusted", emphasis: .secondary, accessibilityLabel: "Trusted")
    }
}

/// One line of the detail's connection log.
nonisolated struct ConnectionLogEntry: Sendable, Hashable, Identifiable {
    let id: UUID
    let state: ReachabilityState
    /// "Came online", "Went offline", "Became unstable", "Checking".
    let title: String
    /// ["Today at 2:11 PM", "192.168.178.52"].
    let detail: [String]
}

/// A device's state changes as log lines, newest first.
nonisolated enum ConnectionLog {
    static func entries(events: [StatusEventSnapshot], host: String, now: Date, calendar: Calendar = .current) -> [ConnectionLogEntry] {
        events
            .sorted { $0.timestamp > $1.timestamp }
            .map { event in
                ConnectionLogEntry(
                    id: event.id,
                    state: event.state,
                    title: title(for: event.state),
                    detail: [when(event.timestamp, now: now, calendar: calendar), host]
                )
            }
    }

    private static func title(for state: ReachabilityState) -> String {
        switch state {
        case .online: return "Came online"
        case .offline: return "Went offline"
        case .degraded: return "Became unstable"
        case .unknown: return "Checking"
        }
    }

    /// "Today at 2:11 PM", "Yesterday at 6:05 PM", "Tuesday at 9:00 AM" within the week, else "Oct 14 at 3:20 AM".
    private static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return "Today at \(time)"
        case 1: return "Yesterday at \(time)"
        case 2...6: return "\(date.formatted(.dateTime.weekday(.wide))) at \(time)"
        default: return "\(date.formatted(.dateTime.month(.abbreviated).day())) at \(time)"
        }
    }
}
