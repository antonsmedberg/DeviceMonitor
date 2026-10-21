import Foundation

/// The span the activity ribbon covers.
nonisolated enum TimelineRange: String, Sendable, Hashable, CaseIterable {
    case day, week

    var title: String {
        switch self {
        case .day: return "24 hours"
        case .week: return "7 days"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .day: return 24 * 3600
        case .week: return 7 * 24 * 3600
        }
    }

    /// Hourly buckets for a day, six-hour buckets for a week.
    var bucketCount: Int {
        switch self {
        case .day: return 24
        case .week: return 28
        }
    }
}

/// How many devices were online at the start of each bucket of a range, and how many status
/// changes happened inside it.
nonisolated struct ActivityDensity: Sendable, Hashable {
    nonisolated struct Bucket: Sendable, Hashable, Identifiable {
        let index: Int
        let start: Date
        let end: Date
        let online: Int
        let events: Int

        var id: Int { index }

        init(index: Int, start: Date, end: Date, online: Int, events: Int) {
            self.index = index
            self.start = start
            self.end = end
            self.online = online
            self.events = events
        }
    }

    let range: TimelineRange
    let buckets: [Bucket]

    var peakOnline: Int { buckets.map(\.online).max() ?? 0 }

    /// A device's state at an instant is its last event at or before it. Before its first event
    /// it was in the state the tracker must have left to get there: it came online, so it was down;
    /// it became unstable or dropped, so it was up (only an online device becomes unstable). With
    /// no events at all its current state is used. Devices first seen after the instant do not count.
    init(events: [StatusEventSnapshot], devices: [DeviceSnapshot], range: TimelineRange, now: Date) {
        self.range = range
        let start = now.addingTimeInterval(-range.seconds)
        let width = range.seconds / Double(range.bucketCount)
        let byDevice = Dictionary(grouping: events.sorted { $0.timestamp < $1.timestamp }, by: \.deviceID)
        let sortedTimes = events.map(\.timestamp).sorted()

        buckets = (0..<range.bucketCount).map { index in
            let bucketStart = start.addingTimeInterval(Double(index) * width)
            let bucketEnd = bucketStart.addingTimeInterval(width)
            let online = devices.reduce(0) { count, device in
                guard device.firstSeen <= bucketStart else { return count }
                let history = byDevice[device.id] ?? []
                let state = Self.state(at: bucketStart, history: history, current: device.state)
                return state.isUp ? count + 1 : count
            }
            let eventCount = Self.count(in: bucketStart..<bucketEnd, sortedTimes: sortedTimes)
            return Bucket(index: index, start: bucketStart, end: bucketEnd, online: online, events: eventCount)
        }
    }

    static func state(at instant: Date, history: [StatusEventSnapshot], current: ReachabilityState) -> ReachabilityState {
        if let last = history.last(where: { $0.timestamp <= instant }) {
            return last.state
        }
        if let first = history.first {
            switch first.state {
            case .online: return .offline
            case .degraded, .offline: return .online
            case .unknown: return current
            }
        }
        return current
    }

    /// Number of timestamps in the half-open range, by binary search over sorted times.
    static func count(in range: Range<Date>, sortedTimes: [Date]) -> Int {
        lowerBound(of: range.upperBound, in: sortedTimes) - lowerBound(of: range.lowerBound, in: sortedTimes)
    }

    private static func lowerBound(of date: Date, in times: [Date]) -> Int {
        var low = 0
        var high = times.count
        while low < high {
            let middle = (low + high) / 2
            if times[middle] < date {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}
