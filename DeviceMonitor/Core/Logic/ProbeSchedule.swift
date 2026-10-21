import Foundation

/// Adaptive probe intervals: unstable devices are checked more often, long-offline ones less often.
nonisolated enum ProbeSchedule {
    static func intervalSeconds(for tracker: ReachabilityTracker, settings: MonitorSettings) -> Double {
        let base = settings.baseIntervalSeconds
        switch tracker.state {
        case .online:
            return base
        case .degraded:
            return max(5, base / 3)
        case .offline:
            // A device that just answered again is confirmed quickly instead of after the back-off.
            if tracker.consecutiveHits > 0 { return max(5, base / 3) }
            let exponent = Double(min(tracker.offlineRounds, 3))
            return min(settings.maxIntervalSeconds, base * pow(2, exponent))
        case .unknown:
            return 5
        }
    }

    /// Deterministic ±10 % jitter so devices do not all probe in the same instant.
    static func jitteredInterval(_ seconds: Double, for id: UUID) -> Double {
        let fraction = DeviceIdentity.jitterFraction(for: id)
        return seconds * (0.9 + 0.2 * fraction)
    }

    /// Lower runs first. The gateway is always first.
    static func priority(of target: MonitoredTarget) -> Int {
        if target.isGateway { return 0 }
        switch target.tracker.state {
        case .degraded: return 1
        case .unknown: return 2
        case .online: return 3
        case .offline: return 4
        }
    }

    static func ordered(_ targets: [MonitoredTarget]) -> [MonitoredTarget] {
        targets.sorted { lhs, rhs in
            let lp = priority(of: lhs)
            let rp = priority(of: rhs)
            if lp != rp { return lp < rp }
            return lhs.host < rhs.host
        }
    }
}
