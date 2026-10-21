import Foundation

nonisolated struct ReachabilityTransition: Sendable, Codable, Hashable {
    let from: ReachabilityState
    let to: ReachabilityState
    let at: Date

    init(from: ReachabilityState, to: ReachabilityState, at: Date) {
        self.from = from
        self.to = to
        self.at = at
    }
}

/// Confidence-based hysteresis state machine.
///
/// A single dropped probe never flips a device offline; an offline device needs
/// repeated answers before it is reported online again. See `ReachabilityPolicy`.
nonisolated struct ReachabilityTracker: Sendable, Codable, Hashable {
    private(set) var state: ReachabilityState
    private(set) var confidence: Double
    private(set) var consecutiveMisses: Int
    private(set) var consecutiveHits: Int
    private(set) var offlineRounds: Int
    private(set) var lastSeen: Date?
    private(set) var lastResultAt: Date?

    init() {
        self.init(state: .unknown, confidence: 0, lastSeen: nil)
    }

    init(state: ReachabilityState, confidence: Double, lastSeen: Date?) {
        self.state = state
        self.confidence = min(max(confidence, 0), 1)
        self.consecutiveMisses = 0
        self.consecutiveHits = 0
        self.offlineRounds = 0
        self.lastSeen = lastSeen
        self.lastResultAt = nil
    }

    /// Applies one probe result and returns a transition when the state changed.
    mutating func record(_ result: ProbeResult, policy: ReachabilityPolicy) -> ReachabilityTransition? {
        let outcome = result.outcome
        guard !outcome.isNeutral else { return nil }

        lastResultAt = result.timestamp
        let previous = state

        if outcome.indicatesHostUp {
            consecutiveMisses = 0
            consecutiveHits += 1
            lastSeen = result.timestamp

            if state == .unknown && consecutiveHits == 1 {
                confidence = max(confidence, 0.75)
            } else {
                confidence += policy.confidenceGain * (1 - confidence)
            }

            switch state {
            case .unknown:
                if consecutiveHits >= policy.hitsToOnline { state = .online }
            case .degraded:
                state = .online
            case .offline:
                if consecutiveHits >= policy.offlineRecoveryHits || confidence >= policy.onlineThreshold {
                    state = .online
                    offlineRounds = 0
                }
            case .online:
                break
            }
        } else {
            consecutiveHits = 0
            consecutiveMisses += 1

            if state == .unknown && consecutiveMisses == 1 {
                confidence = min(confidence, 0.2)
            } else {
                confidence *= (1 - policy.confidenceDecay)
            }

            // The miss count is the only rule for going offline, so the user's
            // "misses before offline" setting means exactly what it says.
            switch state {
            case .unknown, .degraded:
                if consecutiveMisses >= policy.missesToOffline { state = .offline }
            case .online:
                state = policy.missesToOffline <= 1 ? .offline : .degraded
            case .offline:
                offlineRounds += 1
            }
        }

        confidence = min(max(confidence, 0), 1)

        guard state != previous else { return nil }
        return ReachabilityTransition(from: previous, to: state, at: result.timestamp)
    }
}
