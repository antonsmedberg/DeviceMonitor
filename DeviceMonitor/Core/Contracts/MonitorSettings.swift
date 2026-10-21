import Foundation

/// Injectable clock so logic and tests stay deterministic.
nonisolated protocol DateProviding: Sendable {
    func now() -> Date
}

nonisolated struct SystemDateProvider: DateProviding {
    init() {}
    func now() -> Date { Date() }
}

nonisolated struct FixedDateProvider: DateProviding {
    var date: Date
    init(_ date: Date) { self.date = date }
    func now() -> Date { date }
}

/// User-tunable monitoring behaviour. Values are clamped when read back from storage.
nonisolated struct MonitorSettings: Sendable, Codable, Hashable {
    var baseIntervalSeconds: Double = 30
    var probeTimeoutSeconds: Double = 2.5
    var maxIntervalSeconds: Double = 240
    var maxConcurrentProbes: Int = 12
    var isICMPEnabled: Bool = true
    var isUDPEnabled: Bool = true
    var pauseOnCellular: Bool = true

    static let standard = MonitorSettings()

    init() {}

    /// Returns a copy with every value inside its supported range.
    func clamped() -> MonitorSettings {
        var copy = self
        copy.baseIntervalSeconds = min(max(copy.baseIntervalSeconds, 10), 300)
        copy.probeTimeoutSeconds = min(max(copy.probeTimeoutSeconds, 0.5), 10)
        copy.maxIntervalSeconds = min(max(copy.maxIntervalSeconds, copy.baseIntervalSeconds), 900)
        copy.maxConcurrentProbes = min(max(copy.maxConcurrentProbes, 1), 32)
        return copy
    }
}

/// Hysteresis parameters for the reachability state machine.
nonisolated struct ReachabilityPolicy: Sendable, Codable, Hashable {
    var hitsToOnline: Int = 1
    var missesToOffline: Int = 3
    var offlineRecoveryHits: Int = 2
    var confidenceGain: Double = 0.35
    var confidenceDecay: Double = 0.45
    var onlineThreshold: Double = 0.6

    static let standard = ReachabilityPolicy()

    init() {}

    func clamped() -> ReachabilityPolicy {
        var copy = self
        copy.hitsToOnline = min(max(copy.hitsToOnline, 1), 5)
        copy.missesToOffline = min(max(copy.missesToOffline, 1), 8)
        copy.offlineRecoveryHits = min(max(copy.offlineRecoveryHits, 1), 5)
        copy.confidenceGain = min(max(copy.confidenceGain, 0.05), 0.95)
        copy.confidenceDecay = min(max(copy.confidenceDecay, 0.05), 0.95)
        copy.onlineThreshold = min(max(copy.onlineThreshold, 0.1), 0.95)
        return copy
    }
}

/// Hard caps that keep the SwiftData store bounded.
nonisolated struct StorageLimits: Sendable, Hashable {
    var maxStatusEventsPerDevice: Int = 400
    var maxLatencySamplesPerDevice: Int = 720
    var latencyRetentionDays: Int = 7
    var eventRetentionDays: Int = 90
    var minLatencySampleSpacingSeconds: Double = 10
    var maxDevices: Int = 254
    var maxNameLength: Int = 64
    var maxNotesLength: Int = 2000
    var maxTags: Int = 10
    var maxTagLength: Int = 24

    static let standard = StorageLimits()

    init() {}
}
