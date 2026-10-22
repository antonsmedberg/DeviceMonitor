import Foundation
import Testing
@testable import DeviceMonitor

@Suite("Demo fixtures")
struct DemoFixturesTests {
    @Test func devicesAreUniqueAndStable() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = DemoFixtures.devices(now: now)
        let b = DemoFixtures.devices(now: now)
        #expect(a.count == 14)
        #expect(a.map(\.id) == b.map(\.id))
        #expect(Set(a.map(\.host)).count == a.count)
        #expect(Set(a.map(\.id)).count == a.count)
        #expect(a.filter(\.isGateway).count == 1)
        #expect(a.contains { $0.isNew(now: now) })
        #expect(Set(DemoFixtures.script.keys) == Set(a.map(\.host)))
        #expect(a.map(\.displayName) == DemoFixtures.seeds.map { $0.nickname ?? $0.name })
    }

    @Test func everySeedIsOnTheDemoSubnet() throws {
        let subnet = try #require(IPv4Subnet(cidr: DemoFixtures.subnetCIDR))
        for seed in DemoFixtures.seeds {
            let host = try #require(IPv4Host(seed.host))
            #expect(subnet.contains(host))
        }
    }

    @Test func storageLatencyHasItsTwoBackupSpikes() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let nas = try #require(DemoFixtures.devices(now: now).first { $0.host == "192.168.178.2" })
        let baseline = try #require(nas.latencyMilliseconds)
        let values = DemoFixtures.latencySamples(now: now, deviceID: nas.id, baseline: baseline).map(\.milliseconds)
        let band = try #require(LatencyNarrative.typicalBand(values))
        let threshold = LatencyNarrative.spikeThreshold(for: band)
        #expect(values[110] > threshold)
        #expect(values[116] > threshold)
        #expect(values.filter { $0 > threshold }.count >= 2)
        let median = try #require(LatencySummary(samples: values)?.median)
        #expect(abs(median - baseline) <= baseline * 0.2)
    }

    @Test func historyIsConsistent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let events = DemoFixtures.statusEvents(now: now)
        let ids = Set(DemoFixtures.devices(now: now).map(\.id))
        let historyStart = now.addingTimeInterval(-DemoFixtures.historySeconds)
        #expect(events.allSatisfy { ids.contains($0.deviceID) })
        #expect(events == events.sorted { $0.timestamp < $1.timestamp })
        #expect(events == DemoFixtures.statusEvents(now: now))
        #expect(Set(events.map(\.id)).count == events.count)
        #expect(events.allSatisfy { $0.timestamp >= historyStart && $0.timestamp <= now })
        let samples = DemoFixtures.latencySamples(now: now, deviceID: ids.first!, baseline: 10)
        #expect(samples.count == 180)
        #expect(samples.allSatisfy { $0.milliseconds > 0 })
        #expect(DemoFixtures.stableNoise("a", salt: 1) == DemoFixtures.stableNoise("a", salt: 1))
        #expect(DemoFixtures.stableNoise("a", salt: 1) != DemoFixtures.stableNoise("a", salt: 2))
    }

    @Test func historyEndsInEachSeededState() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let historyStart = now.addingTimeInterval(-DemoFixtures.historySeconds)
        let byDevice = Dictionary(grouping: DemoFixtures.statusEvents(now: now), by: \.deviceID)
        for device in DemoFixtures.devices(now: now) {
            let history = byDevice[device.id] ?? []
            if let last = history.last {
                #expect(last.state == device.state)
            }
            if device.state == .offline {
                #expect(history.last?.timestamp == device.lastSeen)
            }
            // Only devices first seen inside the week get an arrival event.
            let arrived = history.contains { $0.timestamp == device.firstSeen }
            #expect(arrived == (device.firstSeen > historyStart))
        }
    }

    @Test func activityFollowsDailyRoutines() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let devices = DemoFixtures.devices(now: now)
        let events = DemoFixtures.statusEvents(now: now)
        for range in TimelineRange.allCases {
            let online = ActivityDensity(events: events, devices: devices, range: range, now: now).buckets.map(\.online)
            let low = online.min() ?? 0
            let high = online.max() ?? 0
            #expect(high - low >= 2)
            #expect(low >= 9 && high <= 13)
        }
    }

    @Test func demoSecurityScoreNeedsAttention() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let score = SecurityAssessor.score(devices: DemoFixtures.devices(now: now), now: now)
        #expect(score.value == 60)
        #expect(score.grade == "Needs attention")
        #expect(score.findings.count == 5)
    }

    @Test func demoProbeFollowsScript() async {
        let probe = DemoProbe(script: ["h": [.reachable(latencyMilliseconds: 10), .timedOut]], dateProvider: FixedDateProvider(Date(timeIntervalSince1970: 0)))
        let first = await probe.probe(host: "h", port: nil, timeoutSeconds: 1)
        let second = await probe.probe(host: "h", port: nil, timeoutSeconds: 1)
        let third = await probe.probe(host: "h", port: nil, timeoutSeconds: 1)
        #expect(first.outcome.indicatesHostUp)
        #expect(second.outcome == .timedOut)
        #expect(third.outcome.indicatesHostUp)
        #expect(first.kind == .demo)
    }
}

@Suite("Monitor engine")
struct MonitorEngineTests {
    @Test func emitsProbeAndTransitionEvents() async throws {
        let probe = DemoProbe(script: ["10.0.0.5": [.reachable(latencyMilliseconds: 5)]], dateProvider: FixedDateProvider(Date(timeIntervalSince1970: 100)))
        var settings = MonitorSettings()
        settings.baseIntervalSeconds = 10
        let engine = MonitorEngine(probes: [probe], policy: .standard, settings: settings)
        let id = UUID()
        await engine.setTargets([MonitoredTarget(id: id, host: "10.0.0.5")])
        await engine.start()

        // Cancelling the collector ends the stream iteration, so a silent engine cannot hang the test.
        let collector = Task { () -> (probe: Bool, transition: Bool, round: Bool) in
            var sawProbe = false
            var sawTransition = false
            var sawRound = false
            for await event in engine.events {
                switch event {
                case .probe(let deviceID, let result, _):
                    #expect(deviceID == id)
                    #expect(result.outcome.indicatesHostUp)
                    sawProbe = true
                case .transition(let deviceID, let transition, let tracker):
                    #expect(deviceID == id)
                    #expect(transition.to == .online)
                    #expect(tracker.state == .online)
                    sawTransition = true
                case .roundCompleted:
                    sawRound = true
                default:
                    break
                }
                if sawProbe && sawTransition && sawRound { break }
            }
            return (sawProbe, sawTransition, sawRound)
        }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(5))
            collector.cancel()
        }
        let seen = await collector.value
        timeout.cancel()
        #expect(seen.probe && seen.transition && seen.round)
        let tracker = await engine.tracker(for: id)
        #expect(tracker?.state == .online)
        await engine.stop()
        let stillRunning = await engine.isRunning
        #expect(stillRunning == false)
    }

    @Test func checkNowReturnsAResultAndPauseStopsLoops() async throws {
        let probe = DemoProbe(script: ["10.0.0.9": [.timedOut]])
        let engine = MonitorEngine(probes: [probe], policy: .standard, settings: .standard)
        let id = UUID()
        await engine.setTargets([MonitoredTarget(id: id, host: "10.0.0.9")])
        await engine.start()
        let result = await engine.checkNow(deviceID: id)
        #expect(result?.outcome == .timedOut)
        await engine.pause(reason: "test")
        let pausedRunning = await engine.isRunning
        #expect(pausedRunning == false)
        await engine.resume()
        let resumedRunning = await engine.isRunning
        #expect(resumedRunning == true)
        await engine.removeTargets(ids: [id])
        let removedTracker = await engine.tracker(for: id)
        #expect(removedTracker == nil)
        let removedResult = await engine.checkNow(deviceID: id)
        #expect(removedResult == nil)
        await engine.stop()
    }

    @Test func unsupportedProbesAreSkipped() async throws {
        let unsupported = FixedOutcomeProbe(kind: .icmp, outcome: .unsupported)
        let working = DemoProbe(script: ["10.0.0.77": [.reachable(latencyMilliseconds: 2)]])
        let engine = MonitorEngine(probes: [unsupported, working], policy: .standard, settings: .standard)
        let id = UUID()
        await engine.setTargets([MonitoredTarget(id: id, host: "10.0.0.77")])
        let maybeResult = await engine.checkNow(deviceID: id)
        let result = try #require(maybeResult)
        #expect(result.outcome.indicatesHostUp)
        #expect(result.kind == .demo)
        let probedAgain = await unsupported.callCount
        #expect(probedAgain == 1)
        let second = await engine.checkNow(deviceID: id)
        #expect(second?.kind == .demo)
        let stillOne = await unsupported.callCount
        #expect(stillOne == 1)
    }
}

@Suite("Monitor engine control")
struct MonitorEngineControlTests {
    @Test func pauseBeforeStartKeepsTheEnginePaused() async {
        let probe = FixedOutcomeProbe(kind: .tcp, outcome: .reachable(latencyMilliseconds: 1))
        let engine = MonitorEngine(probes: [probe], policy: .standard, settings: .standard)
        await engine.setTargets([MonitoredTarget(id: UUID(), host: "10.0.0.2")])
        await engine.pause(reason: "Not on Wi‑Fi")
        await engine.start()
        let running = await engine.isRunning
        #expect(running == false)
        try? await Task.sleep(for: .milliseconds(200))
        let calls = await probe.callCount
        #expect(calls == 0)
        await engine.resume()
        let resumed = await engine.isRunning
        #expect(resumed == true)
        await engine.stop()
    }

    @Test func staleActivationIsIgnored() async {
        let engine = MonitorEngine(probes: [FixedOutcomeProbe(kind: .tcp, outcome: .timedOut)], policy: .standard, settings: .standard)
        await engine.setActive(false, reason: "Paused by you", generation: 2)
        await engine.setActive(true, reason: "", generation: 1)
        let running = await engine.isRunning
        #expect(running == false)
        await engine.setActive(true, reason: "", generation: 3)
        let active = await engine.isRunning
        #expect(active == true)
        await engine.stop()
    }

    @Test func icmpIsNotUsedForHostnamesAndStaysAvailable() async throws {
        let icmp = FixedOutcomeProbe(kind: .icmp, outcome: .reachable(latencyMilliseconds: 1))
        let tcp = FixedOutcomeProbe(kind: .tcp, outcome: .timedOut)
        let engine = MonitorEngine(probes: [tcp, icmp], policy: .standard, settings: .standard)
        let named = UUID()
        let numeric = UUID()
        await engine.setTargets([MonitoredTarget(id: named, host: "nas.local"), MonitoredTarget(id: numeric, host: "10.0.0.9")])
        let namedResult = await engine.checkNow(deviceID: named)
        #expect(namedResult?.kind == .tcp)
        let numericResult = await engine.checkNow(deviceID: numeric)
        #expect(numericResult?.kind == .icmp)
        #expect(numericResult?.outcome.indicatesHostUp == true)
    }

    @Test func scanResultsReachTheTracker() async {
        let engine = MonitorEngine(probes: [FixedOutcomeProbe(kind: .tcp, outcome: .timedOut)], policy: .standard, settings: .standard)
        let id = UUID()
        await engine.setTargets([MonitoredTarget(id: id, host: "10.0.0.3")])
        await engine.record(ProbeResult(host: "10.0.0.3", port: nil, kind: .tcp, outcome: .reachable(latencyMilliseconds: 2), timestamp: Date()), for: id)
        let tracker = await engine.tracker(for: id)
        #expect(tracker?.state == .online)
    }
}

/// A probe of a chosen kind that always reports the same outcome; counts how often it was asked.
private actor FixedOutcomeProbe: HostProbing {
    nonisolated let kind: ProbeKind
    private let outcome: ProbeOutcome
    private(set) var callCount = 0

    init(kind: ProbeKind, outcome: ProbeOutcome) {
        self.kind = kind
        self.outcome = outcome
    }

    func probe(host: String, port: UInt16?, timeoutSeconds: Double) async -> ProbeResult {
        callCount += 1
        return ProbeResult(host: host, port: port, kind: kind, outcome: outcome, timestamp: Date())
    }
}
