import Foundation

/// What a stretch of history looked like. Unstable counts as up; red means down and nothing else.
nonisolated enum UptimeState: String, Sendable, Hashable, CaseIterable {
    case online, unstable, offline, noData

    /// The legend word.
    var title: String {
        switch self {
        case .online: return "Up"
        case .unstable: return "Unstable"
        case .offline: return "Offline"
        case .noData: return "No data"
        }
    }
}

/// One cell of a status-page strip.
nonisolated struct UptimeCell: Sendable, Hashable, Identifiable {
    /// The whole cell, even where it starts before the device was first seen or ends after now.
    let interval: DateInterval
    let state: UptimeState
    /// Up seconds ÷ known seconds; nil without data.
    let availability: Double?
    let offlineSeconds: TimeInterval
    /// Offline periods that start in the cell.
    let outages: Int

    var id: Date { interval.start }

    init(interval: DateInterval, state: UptimeState, availability: Double?, offlineSeconds: TimeInterval, outages: Int) {
        self.interval = interval
        self.state = state
        self.availability = availability
        self.offlineSeconds = offlineSeconds
        self.outages = outages
    }
}

/// Status-page cells from a device's state changes. Each cell is judged on the part of it between the
/// device's first sighting and now; the state before a device's first event is inferred as
/// `ActivityDensity.state(at:history:current:)` does.
nonisolated enum UptimeCells {
    /// `count` equal cells covering `span` seconds and ending at `now`.
    static func recent(count: Int, span: TimeInterval, events: [StatusEventSnapshot], currentState: ReachabilityState, firstSeen: Date, now: Date) -> [UptimeCell] {
        let history = events.sorted { $0.timestamp < $1.timestamp }
        return intervals(count: count, span: span, now: now).map { interval in
            cell(for: interval, history: history, currentState: currentState, firstSeen: firstSeen, now: now)
        }
    }

    /// `count` calendar days ending with today, each from the start of its day.
    static func days(count: Int, events: [StatusEventSnapshot], currentState: ReachabilityState, firstSeen: Date, now: Date, calendar: Calendar = .current) -> [UptimeCell] {
        let history = events.sorted { $0.timestamp < $1.timestamp }
        let today = calendar.startOfDay(for: now)
        return (0..<max(count, 0)).compactMap { index -> UptimeCell? in
            guard let start = calendar.date(byAdding: .day, value: index - (count - 1), to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return cell(for: DateInterval(start: start, end: end), history: history, currentState: currentState, firstSeen: firstSeen, now: now)
        }
    }

    /// The network's heartbeat: the router's cells, with every cell that overlaps a network-wide outage forced
    /// offline. Without a router only the outages count, and cells before the first device was seen have no
    /// data.
    static func network(count: Int, span: TimeInterval, events: [StatusEventSnapshot], devices: [DeviceSnapshot], gatewayID: UUID?, now: Date) -> [UptimeCell] {
        let outages = outagePeriods(events: events, devices: devices, gatewayID: gatewayID, now: now)
        let base: [UptimeCell]
        if let gateway = devices.first(where: { $0.id == gatewayID }) {
            base = recent(
                count: count,
                span: span,
                events: events.filter { $0.deviceID == gateway.id },
                currentState: gateway.state,
                firstSeen: gateway.firstSeen,
                now: now
            )
        } else {
            let earliest = devices.map(\.firstSeen).min() ?? now
            base = intervals(count: count, span: span, now: now).map { interval -> UptimeCell in
                let isKnown = max(interval.start, earliest) < min(interval.end, now)
                return UptimeCell(interval: interval, state: isKnown ? .online : .noData, availability: isKnown ? 1 : nil, offlineSeconds: 0, outages: 0)
            }
        }
        return base.map { forcingOffline($0, during: outages, now: now) }
    }

    /// Offline from max(120 s, 2 % of the cell) of offline time; unstable with any offline or unstable time
    /// below that; no data without known time.
    static func state(offlineSeconds: TimeInterval, unstableSeconds: TimeInterval, knownSeconds: TimeInterval, duration: TimeInterval) -> UptimeState {
        guard knownSeconds > 0 else { return .noData }
        if offlineSeconds >= max(120, 0.02 * duration) { return .offline }
        if offlineSeconds > 0 || unstableSeconds > 0 { return .unstable }
        return .online
    }

    /// Mean availability of the cells with data, weighted by cell length.
    static func availability(of cells: [UptimeCell]) -> Double? {
        var weighted = 0.0
        var total = 0.0
        for cell in cells {
            guard let availability = cell.availability else { continue }
            weighted += availability * cell.interval.duration
            total += cell.interval.duration
        }
        return total > 0 ? weighted / total : nil
    }

    /// "Up all day" or "Down 4 min today" for a day of cells; "Up 99.8% · 1 outage in 30 days" for longer.
    static func headline(_ cells: [UptimeCell], days: Int) -> String {
        guard let availability = availability(of: cells) else { return "No data yet" }
        if days <= 1 {
            let downSeconds = cells.map(\.offlineSeconds).reduce(0, +)
            return downSeconds > 0 ? "Down \(Formatters.duration(downSeconds)) today" : "Up all day"
        }
        let outages = cells.map(\.outages).reduce(0, +)
        let outageText = outages == 0 ? "no outages" : Formatters.count(outages, singular: "outage", plural: "outages")
        return "Up \(Formatters.percent(availability)) · \(outageText) in \(days) days"
    }

    private static func intervals(count: Int, span: TimeInterval, now: Date) -> [DateInterval] {
        guard count > 0, span > 0 else { return [] }
        let width = span / Double(count)
        let start = now.addingTimeInterval(-span)
        return (0..<count).map { index -> DateInterval in
            let from = start.addingTimeInterval(Double(index) * width)
            let to = index == count - 1 ? now : start.addingTimeInterval(Double(index + 1) * width)
            return DateInterval(start: from, end: max(from, to))
        }
    }

    private static func cell(for interval: DateInterval, history: [StatusEventSnapshot], currentState: ReachabilityState, firstSeen: Date, now: Date) -> UptimeCell {
        let lower = max(interval.start, firstSeen)
        let upper = min(interval.end, now)
        guard lower < upper else {
            return UptimeCell(interval: interval, state: .noData, availability: nil, offlineSeconds: 0, outages: 0)
        }
        var seconds: [ReachabilityState: TimeInterval] = [:]
        var reading = ActivityDensity.state(at: lower, history: history, current: currentState)
        var cursor = lower
        var outages = 0
        for (index, event) in history.enumerated() where event.timestamp >= lower && event.timestamp < upper {
            // Before its first event an offline device was up, so a first offline event starts an outage.
            if event.state == .offline && (index == 0 || history[index - 1].state != .offline) {
                outages += 1
            }
            guard event.timestamp > lower else { continue }
            seconds[reading, default: 0] += event.timestamp.timeIntervalSince(cursor)
            reading = event.state
            cursor = event.timestamp
        }
        seconds[reading, default: 0] += upper.timeIntervalSince(cursor)

        let offline = seconds[.offline, default: 0]
        let unstable = seconds[.degraded, default: 0]
        let up = seconds[.online, default: 0] + unstable
        let known = up + offline
        return UptimeCell(
            interval: interval,
            state: state(offlineSeconds: offline, unstableSeconds: unstable, knownSeconds: known, duration: interval.duration),
            availability: known > 0 ? up / known : nil,
            offlineSeconds: offline,
            outages: outages
        )
    }

    /// Network-wide outages from the timeline builder (a router drop is one), each from its start to its end,
    /// or to now while it lasts.
    private static func outagePeriods(events: [StatusEventSnapshot], devices: [DeviceSnapshot], gatewayID: UUID?, now: Date) -> [DateInterval] {
        let byID = Dictionary(devices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = NetworkTimelineBuilder.entries(
            events: events,
            devices: byID,
            gatewayID: gatewayID,
            outageWindowSeconds: 90,
            outageFraction: 0.6,
            now: now
        )
        var periods: [DateInterval] = []
        var openStart: Date?
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            switch entry.kind {
            case .outageStarted:
                if openStart == nil {
                    openStart = entry.date
                }
            case .outageEnded:
                if let start = openStart {
                    periods.append(DateInterval(start: start, end: max(start, entry.date)))
                    openStart = nil
                }
            case .newDevice, .left, .returned:
                break
            }
        }
        if let openStart {
            periods.append(DateInterval(start: openStart, end: max(openStart, now)))
        }
        return periods
    }

    private static func forcingOffline(_ cell: UptimeCell, during outages: [DateInterval], now: Date) -> UptimeCell {
        let lower = cell.interval.start
        let upper = min(cell.interval.end, now)
        let overlapping = outages.filter { $0.start < upper && ($0.end > lower || $0.start >= lower) }
        guard !overlapping.isEmpty else { return cell }
        let down = overlapping.map { min($0.end, upper).timeIntervalSince(max($0.start, lower)) }.reduce(0, +)
        let starts = overlapping.filter { $0.start >= lower }.count
        let span = upper.timeIntervalSince(lower)
        let outageAvailability = span > 0 ? max(0, 1 - down / span) : 0
        return UptimeCell(
            interval: cell.interval,
            state: .offline,
            availability: min(cell.availability ?? 1, outageAvailability),
            offlineSeconds: max(cell.offlineSeconds, down),
            outages: max(cell.outages, starts)
        )
    }
}

/// One device's presence per hour column.
nonisolated struct PresenceRow: Sendable, Hashable, Identifiable {
    let deviceID: UUID
    let name: String
    let kind: DeviceKind
    /// Up seconds ÷ the column's seconds since the device was first seen; nil before it existed.
    let shares: [Double?]

    var id: UUID { deviceID }

    init(deviceID: UUID, name: String, kind: DeviceKind, shares: [Double?]) {
        self.deviceID = deviceID
        self.name = name
        self.kind = kind
        self.shares = shares
    }
}

/// Who is on the network in each of the last hours, aligned to the clock.
nonisolated enum PresenceGrid {
    /// The start of the current hour and the `hours − 1` before it, oldest first. The last column ends now.
    static func hourStarts(hours: Int, now: Date, calendar: Calendar = .current) -> [Date] {
        guard hours > 0, let current = calendar.dateInterval(of: .hour, for: now)?.start else { return [] }
        return (0..<hours).compactMap { index in
            calendar.date(byAdding: .hour, value: index - (hours - 1), to: current)
        }
    }

    /// One row per device: rows whose presence varies most first, then by kind family, then by name.
    static func rows(devices: [DeviceSnapshot], events: [StatusEventSnapshot], hourStarts: [Date], now: Date) -> [PresenceRow] {
        let byDevice = Dictionary(grouping: events.sorted { $0.timestamp < $1.timestamp }, by: \.deviceID)
        let rows = devices.map { device -> PresenceRow in
            let history = byDevice[device.id] ?? []
            let shares = hourStarts.indices.map { column -> Double? in
                let end = column + 1 < hourStarts.count ? hourStarts[column + 1] : now
                return share(from: max(hourStarts[column], device.firstSeen), to: end, history: history, currentState: device.state)
            }
            return PresenceRow(deviceID: device.id, name: device.displayName, kind: device.kind, shares: shares)
        }
        return rows.sorted(by: precedes)
    }

    /// Devices present at some point in the column.
    static func online(rows: [PresenceRow], column: Int) -> Int {
        rows.filter { row in
            guard row.shares.indices.contains(column), let share = row.shares[column] else { return false }
            return share > 0
        }.count
    }

    /// "Busiest 7 PM – 10 PM · quietest 3 AM – 6 AM": the three-hour windows with the most and the least
    /// presence; nil when every window is the same.
    static func headline(rows: [PresenceRow], hourStarts: [Date]) -> String? {
        let window = 3
        guard !rows.isEmpty, hourStarts.count >= window else { return nil }
        let totals = hourStarts.indices.map { column in
            rows.map { row in row.shares.indices.contains(column) ? row.shares[column] ?? 0 : 0 }.reduce(0, +)
        }
        let sums = (0...(totals.count - window)).map { start in
            totals[start..<(start + window)].reduce(0, +)
        }
        guard let busiest = sums.indices.max(by: { sums[$0] < sums[$1] }),
              let quietest = sums.indices.min(by: { sums[$0] < sums[$1] }),
              sums[busiest] > sums[quietest] else { return nil }
        return "Busiest \(windowTitle(start: busiest, length: window, hourStarts: hourStarts)) · quietest \(windowTitle(start: quietest, length: window, hourStarts: hourStarts))"
    }

    private static func share(from lower: Date, to upper: Date, history: [StatusEventSnapshot], currentState: ReachabilityState) -> Double? {
        guard lower < upper else { return nil }
        var reading = ActivityDensity.state(at: lower, history: history, current: currentState)
        var cursor = lower
        var up = 0.0
        for event in history where event.timestamp > lower && event.timestamp < upper {
            if reading.isUp {
                up += event.timestamp.timeIntervalSince(cursor)
            }
            reading = event.state
            cursor = event.timestamp
        }
        if reading.isUp {
            up += upper.timeIntervalSince(cursor)
        }
        return up / upper.timeIntervalSince(lower)
    }

    private static func precedes(_ lhs: PresenceRow, _ rhs: PresenceRow) -> Bool {
        let lhsSpread = spread(lhs.shares)
        let rhsSpread = spread(rhs.shares)
        if lhsSpread != rhsSpread {
            return lhsSpread > rhsSpread
        }
        let lhsFamily = KindFamily(lhs.kind).rawValue
        let rhsFamily = KindFamily(rhs.kind).rawValue
        if lhsFamily != rhsFamily {
            return lhsFamily < rhsFamily
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private static func spread(_ shares: [Double?]) -> Double {
        let known = shares.compactMap { $0 }
        guard let high = known.max(), let low = known.min() else { return 0 }
        return high - low
    }

    private static func windowTitle(start: Int, length: Int, hourStarts: [Date]) -> String {
        let from = hourStarts[start]
        let endIndex = start + length
        let to = endIndex < hourStarts.count ? hourStarts[endIndex] : hourStarts[endIndex - 1].addingTimeInterval(3600)
        return "\(from.formatted(.dateTime.hour())) – \(to.formatted(.dateTime.hour()))"
    }
}

/// One line of the "Since you last looked" card.
nonisolated struct JournalLine: Sendable, Hashable, Identifiable {
    /// Rank order: what matters most comes first.
    nonisolated enum Kind: Int, Sendable, Hashable, Comparable {
        case newDevice, outage, repeatedDrops, wentOffline, recovered

        static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
    }

    let id: String
    let kind: Kind
    let text: String
    /// The device the line names, if any.
    let deviceID: UUID?

    init(id: String, kind: Kind, text: String, deviceID: UUID?) {
        self.id = id
        self.kind = kind
        self.text = text
        self.deviceID = deviceID
    }
}

/// What happened since the person last looked, at most a few lines, most important first.
nonisolated enum Journal {
    /// From the timeline entries after `since`: new devices, network outages, devices that dropped out more
    /// than once, devices that went offline, devices that came back; newest first within a kind.
    static func lines(entries: [TimelineEntry], devices: [UUID: DeviceSnapshot], since: Date, limit: Int = 3) -> [JournalLine] {
        let recent = entries.filter { $0.date > since }.sorted { $0.date < $1.date }
        var ranked: [(line: JournalLine, date: Date)] = []

        for (index, entry) in recent.enumerated() where entry.kind == .outageStarted {
            let time = entry.date.formatted(date: .omitted, time: .shortened)
            let end = recent[(index + 1)...].first { $0.kind == .outageEnded }
            let text = end.map { "Network outage at \(time) · \(Formatters.duration($0.date.timeIntervalSince(entry.date)))" }
                ?? "Network outage at \(time)"
            ranked.append((JournalLine(id: "outage:\(entry.id)", kind: .outage, text: text, deviceID: nil), entry.date))
        }

        var byDevice: [UUID: [TimelineEntry]] = [:]
        for entry in recent {
            guard let deviceID = entry.deviceID else { continue }
            byDevice[deviceID, default: []].append(entry)
        }
        for (deviceID, history) in byDevice {
            let device = devices[deviceID]
            let name = device?.displayName ?? history[0].title
            for entry in history where entry.kind == .newDevice {
                let text = device.map { "\(name) joined · \($0.host)" } ?? "\(name) joined"
                ranked.append((JournalLine(id: "new:\(entry.id)", kind: .newDevice, text: text, deviceID: deviceID), entry.date))
            }
            let drops = history.filter { $0.kind == .left }
            if drops.count >= 2, let last = drops.last {
                let line = JournalLine(id: "drops:\(deviceID.uuidString)", kind: .repeatedDrops, text: "\(name) dropped out \(drops.count) times", deviceID: deviceID)
                ranked.append((line, last.date))
            } else if let drop = drops.first {
                if let back = history.last(where: { $0.kind == .returned && $0.date > drop.date }) {
                    ranked.append((JournalLine(id: "back:\(back.id)", kind: .recovered, text: "\(name) is back", deviceID: deviceID), back.date))
                } else {
                    let time = drop.date.formatted(date: .omitted, time: .shortened)
                    ranked.append((JournalLine(id: "left:\(drop.id)", kind: .wentOffline, text: "\(name) went offline at \(time)", deviceID: deviceID), drop.date))
                }
            } else if let back = history.last(where: { $0.kind == .returned }) {
                ranked.append((JournalLine(id: "back:\(back.id)", kind: .recovered, text: "\(name) is back", deviceID: deviceID), back.date))
            }
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.line.kind != rhs.line.kind { return lhs.line.kind < rhs.line.kind }
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.line.id < rhs.line.id
            }
            .prefix(max(limit, 0))
            .map { $0.line }
    }
}
