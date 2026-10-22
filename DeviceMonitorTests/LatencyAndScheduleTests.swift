import Foundation
import Testing
@testable import DeviceMonitor

@Suite("Latency statistics")
struct LatencyStatisticsTests {
    @Test func summaryHandlesSingleSample() throws {
        let summary = try #require(LatencySummary(samples: [7]))
        #expect(summary.count == 1)
        #expect(summary.minimum == 7)
        #expect(summary.maximum == 7)
        #expect(summary.median == 7)
        #expect(summary.jitter == 0)
        #expect(LatencySummary(samples: []) == nil)
    }
}

@Suite("Latency narrative")
struct LatencyNarrativeTests {
    @Test func typicalBandIsTenthToNinetiethPercentile() throws {
        let samples = (1...10).map { Double($0) }
        let band = try #require(LatencyNarrative.typicalBand(samples))
        #expect(band.lowerBound == 1)
        #expect(band.upperBound == 9)
        #expect(LatencyNarrative.typicalBand([1, 2, 3]) == nil)
        #expect(LatencyNarrative.typicalBand([1, 2, 3, -1, .nan, .infinity]) == nil)
    }

    @Test func spikeThresholdKeepsAMillisecondOfHeadroom() {
        #expect(LatencyNarrative.spikeThreshold(for: 10...20) == 30)
        #expect(LatencyNarrative.spikeThreshold(for: 1...2) == 3)
        #expect(LatencyNarrative.spikeThreshold(for: 0...0.5) == 1.5)
    }

    @Test func steadySeries() {
        let samples = (0..<20).map { $0.isMultiple(of: 2) ? 2.0 : 2.2 }
        let headline = LatencyNarrative.headline(samples: samples)
        #expect(headline == "Steady around 2.0 ms")
    }

    @Test func spikesAreCountedAboveTheThreshold() {
        var samples = Array(repeating: 2.0, count: 40)
        for index in [5, 17, 33] { samples[index] = 9 }
        let headline = LatencyNarrative.headline(samples: samples)
        #expect(headline == "3 spikes above 3.0 ms")
        samples[5] = 2
        samples[17] = 2
        let single = LatencyNarrative.headline(samples: samples)
        #expect(single == "1 spike above 3.0 ms")
    }

    @Test func slowerThanUsualWinsOverSpikes() {
        let samples = Array(repeating: 2.0, count: 110) + Array(repeating: 18.0, count: 10)
        let headline = LatencyNarrative.headline(samples: samples)
        #expect(headline == "Slower than usual: 18 ms vs 2.0 ms typical")
    }

    @Test func noHeadlineBelowFourSamples() {
        let headline = LatencyNarrative.headline(samples: [2, 2, 2])
        #expect(headline == nil)
    }
}

@Suite("Probe scheduling")
struct ProbeScheduleTests {
    private let settings = MonitorSettings.standard

    @Test func intervalsFollowState() {
        var online = ReachabilityTracker(state: .online, confidence: 1, lastSeen: nil)
        #expect(ProbeSchedule.intervalSeconds(for: online, settings: settings) == 30)
        let degraded = ReachabilityTracker(state: .degraded, confidence: 0.5, lastSeen: nil)
        #expect(ProbeSchedule.intervalSeconds(for: degraded, settings: settings) == 10)
        let unknown = ReachabilityTracker()
        #expect(ProbeSchedule.intervalSeconds(for: unknown, settings: settings) == 5)
        let offline = ReachabilityTracker(state: .offline, confidence: 0, lastSeen: nil)
        #expect(ProbeSchedule.intervalSeconds(for: offline, settings: settings) == 30)
        for index in 0..<6 {
            _ = online.record(ProbeResult(host: "h", port: nil, kind: .tcp, outcome: .timedOut, timestamp: Date(timeIntervalSince1970: Double(index))), policy: .standard)
        }
        #expect(online.state == .offline)
        let backedOff = ProbeSchedule.intervalSeconds(for: online, settings: settings)
        #expect(backedOff > 30 && backedOff <= settings.maxIntervalSeconds)
        _ = online.record(ProbeResult(host: "h", port: nil, kind: .tcp, outcome: .reachable(latencyMilliseconds: 3), timestamp: Date(timeIntervalSince1970: 10)), policy: .standard)
        #expect(online.state == .offline)
        #expect(ProbeSchedule.intervalSeconds(for: online, settings: settings) == 10)
    }

    @Test func jitterIsBoundedAndDeterministic() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let first = ProbeSchedule.jitteredInterval(30, for: id)
        let second = ProbeSchedule.jitteredInterval(30, for: id)
        #expect(first == second)
        #expect(first >= 27 && first <= 33)
    }

    @Test func gatewayAlwaysFirst() {
        let gateway = MonitoredTarget(id: UUID(), host: "192.168.1.1", isGateway: true, tracker: ReachabilityTracker(state: .online, confidence: 1, lastSeen: nil))
        let degraded = MonitoredTarget(id: UUID(), host: "192.168.1.50", tracker: ReachabilityTracker(state: .degraded, confidence: 0.4, lastSeen: nil))
        let online = MonitoredTarget(id: UUID(), host: "192.168.1.20", tracker: ReachabilityTracker(state: .online, confidence: 1, lastSeen: nil))
        let ordered = ProbeSchedule.ordered([online, degraded, gateway])
        #expect(ordered.map(\.host) == ["192.168.1.1", "192.168.1.50", "192.168.1.20"])
    }

    @Test func settingsClampToSupportedRanges() {
        var settings = MonitorSettings()
        settings.baseIntervalSeconds = 1
        settings.probeTimeoutSeconds = 99
        settings.maxConcurrentProbes = 0
        let clamped = settings.clamped()
        #expect(clamped.baseIntervalSeconds == 10)
        #expect(clamped.probeTimeoutSeconds == 10)
        #expect(clamped.maxConcurrentProbes == 1)
        var policy = ReachabilityPolicy()
        policy.missesToOffline = 40
        policy.onlineThreshold = 2
        #expect(policy.clamped().missesToOffline == 8)
        #expect(policy.clamped().onlineThreshold == 0.95)
    }
}
