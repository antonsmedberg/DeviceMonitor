import Foundation
import Testing
@testable import DeviceMonitor

@Suite("Reachability hysteresis")
struct ReachabilityTrackerTests {
    private let policy = ReachabilityPolicy.standard
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func result(_ outcome: ProbeOutcome, offset: TimeInterval) -> ProbeResult {
        ProbeResult(host: "10.0.0.2", port: 80, kind: .tcp, outcome: outcome, timestamp: start.addingTimeInterval(offset))
    }

    @Test func firstHitGoesOnline() {
        var tracker = ReachabilityTracker()
        let transition = tracker.record(result(.reachable(latencyMilliseconds: 4), offset: 0), policy: policy)
        #expect(transition?.from == .unknown)
        #expect(transition?.to == .online)
        #expect(tracker.confidence >= 0.75)
        #expect(tracker.lastSeen == start)
    }

    @Test func refusedCountsAsUp() {
        var tracker = ReachabilityTracker()
        let transition = tracker.record(result(.refused(latencyMilliseconds: 2), offset: 0), policy: policy)
        #expect(transition?.to == .online)
    }

    @Test func singleMissOnlyDegrades() {
        var tracker = ReachabilityTracker(state: .online, confidence: 1, lastSeen: start)
        let transition = tracker.record(result(.timedOut, offset: 30), policy: policy)
        #expect(transition?.to == .degraded)
        #expect(tracker.state == .degraded)
        let recovery = tracker.record(result(.reachable(latencyMilliseconds: 5), offset: 60), policy: policy)
        #expect(recovery?.to == .online)
    }

    @Test func threeMissesGoOffline() {
        var tracker = ReachabilityTracker(state: .online, confidence: 1, lastSeen: start)
        _ = tracker.record(result(.timedOut, offset: 30), policy: policy)
        let second = tracker.record(result(.timedOut, offset: 60), policy: policy)
        #expect(second == nil)
        #expect(tracker.state == .degraded)
        let third = tracker.record(result(.unreachable(code: 65), offset: 90), policy: policy)
        #expect(third?.from == .degraded)
        #expect(third?.to == .offline)
        #expect(tracker.confidence < 0.25)
    }

    @Test func missesToOfflineIsExact() {
        var oneMiss = ReachabilityPolicy()
        oneMiss.missesToOffline = 1
        var tracker = ReachabilityTracker(state: .online, confidence: 1, lastSeen: start)
        let transition = tracker.record(result(.timedOut, offset: 30), policy: oneMiss)
        #expect(transition?.to == .offline)

        var twoMisses = ReachabilityPolicy()
        twoMisses.missesToOffline = 2
        var saturated = ReachabilityTracker(state: .online, confidence: 1, lastSeen: start)
        _ = saturated.record(result(.timedOut, offset: 30), policy: twoMisses)
        #expect(saturated.state == .degraded)
        let second = saturated.record(result(.timedOut, offset: 60), policy: twoMisses)
        #expect(second?.to == .offline)

        var eightMisses = ReachabilityPolicy()
        eightMisses.missesToOffline = 8
        var patient = ReachabilityTracker(state: .online, confidence: 1, lastSeen: start)
        for index in 1...7 {
            _ = patient.record(result(.timedOut, offset: Double(index) * 30), policy: eightMisses)
        }
        #expect(patient.state == .degraded)
        _ = patient.record(result(.timedOut, offset: 240), policy: eightMisses)
        #expect(patient.state == .offline)
    }

    @Test func recoveryFromOfflineNeedsTwoHits() {
        var tracker = ReachabilityTracker(state: .online, confidence: 1, lastSeen: start)
        for offset in [30.0, 60, 90] {
            _ = tracker.record(result(.timedOut, offset: offset), policy: policy)
        }
        #expect(tracker.state == .offline)
        let first = tracker.record(result(.reachable(latencyMilliseconds: 3), offset: 120), policy: policy)
        #expect(first == nil)
        #expect(tracker.state == .offline)
        let second = tracker.record(result(.reachable(latencyMilliseconds: 3), offset: 150), policy: policy)
        #expect(second?.to == .online)
        #expect(tracker.offlineRounds == 0)
    }

    @Test func neutralOutcomesDoNothing() {
        var tracker = ReachabilityTracker(state: .online, confidence: 0.9, lastSeen: start)
        #expect(tracker.record(result(.permissionDenied, offset: 10), policy: policy) == nil)
        #expect(tracker.record(result(.unsupported, offset: 20), policy: policy) == nil)
        #expect(tracker.state == .online)
        #expect(tracker.confidence == 0.9)
        #expect(tracker.lastResultAt == nil)
    }

    @Test func unknownGoesOfflineAfterRepeatedMisses() {
        var tracker = ReachabilityTracker()
        _ = tracker.record(result(.timedOut, offset: 0), policy: policy)
        _ = tracker.record(result(.timedOut, offset: 5), policy: policy)
        #expect(tracker.state == .unknown)
        let third = tracker.record(result(.timedOut, offset: 10), policy: policy)
        #expect(third?.to == .offline)
    }

    @Test func confidenceStaysInRange() {
        var tracker = ReachabilityTracker()
        for index in 0..<50 {
            _ = tracker.record(result(.reachable(latencyMilliseconds: 1), offset: Double(index)), policy: policy)
            #expect(tracker.confidence <= 1 && tracker.confidence >= 0)
        }
        for index in 50..<100 {
            _ = tracker.record(result(.timedOut, offset: Double(index)), policy: policy)
            #expect(tracker.confidence <= 1 && tracker.confidence >= 0)
        }
        #expect(tracker.state == .offline)
        #expect(tracker.offlineRounds > 0)
    }

    @Test func trackerIsCodable() throws {
        var tracker = ReachabilityTracker()
        _ = tracker.record(result(.reachable(latencyMilliseconds: 9), offset: 0), policy: policy)
        let data = try JSONEncoder().encode(tracker)
        let decoded = try JSONDecoder().decode(ReachabilityTracker.self, from: data)
        #expect(decoded == tracker)
    }
}
