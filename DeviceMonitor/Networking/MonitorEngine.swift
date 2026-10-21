import Foundation
import os

/// Continuous monitoring: one adaptive loop per target, a concurrency budget for probes,
/// and a single event stream consumed by `AppEnvironment`.
actor MonitorEngine {
    nonisolated let events: AsyncStream<MonitorEvent>

    private let continuation: AsyncStream<MonitorEvent>.Continuation
    private let dateProvider: any DateProviding
    private var probes: [any HostProbing]
    private var policy: ReachabilityPolicy
    private var settings: MonitorSettings

    private var targets: [UUID: MonitoredTarget] = [:]
    private var loops: [UUID: Task<Void, Never>] = [:]
    private var running = false
    private var paused = false
    private var pauseReason: String?
    private var activeGeneration = -1
    private var activeProbes = 0
    private var slotWaiters: [CheckedContinuation<Void, Never>] = []
    private var unsupportedKinds: Set<ProbeKind> = []
    private var pendingInRound: Set<UUID> = []

    init(probes: [any HostProbing], policy: ReachabilityPolicy, settings: MonitorSettings, dateProvider: any DateProviding = SystemDateProvider()) {
        self.probes = probes
        self.policy = policy.clamped()
        self.settings = settings.clamped()
        self.dateProvider = dateProvider
        let (stream, continuation) = AsyncStream.makeStream(of: MonitorEvent.self, bufferingPolicy: .unbounded)
        self.events = stream
        self.continuation = continuation
    }

    var isRunning: Bool { running && !paused }

    func updateSettings(_ settings: MonitorSettings, policy: ReachabilityPolicy) {
        let previous = self.settings
        self.settings = settings.clamped()
        self.policy = policy.clamped()
        // A shorter interval would otherwise wait out each loop's old sleep (up to about 5 minutes).
        // A longer one needs nothing: the next cycle already uses it.
        guard running, !paused, self.settings.baseIntervalSeconds < previous.baseIntervalSeconds else { return }
        for (id, target) in targets {
            let interval = ProbeSchedule.intervalSeconds(for: target.tracker, settings: self.settings)
            startLoop(for: id, initialDelay: ProbeSchedule.jitteredInterval(interval, for: id))
        }
    }

    func setTargets(_ newTargets: [MonitoredTarget]) {
        let incoming = Dictionary(uniqueKeysWithValues: newTargets.map { ($0.id, $0) })
        for id in targets.keys where incoming[id] == nil {
            loops[id]?.cancel()
            loops[id] = nil
            targets[id] = nil
            pendingInRound.remove(id)
        }
        for (id, target) in incoming {
            if var existing = targets[id] {
                existing.host = target.host
                existing.preferredPort = target.preferredPort
                existing.isGateway = target.isGateway
                targets[id] = existing
            } else {
                targets[id] = target
                pendingInRound.insert(id)
                if running && !paused { startLoop(for: id) }
            }
        }
    }

    func addTarget(_ target: MonitoredTarget) {
        guard targets[target.id] == nil else { return }
        targets[target.id] = target
        pendingInRound.insert(target.id)
        if running && !paused { startLoop(for: target.id) }
    }

    func removeTargets(ids: [UUID]) {
        for id in ids {
            loops[id]?.cancel()
            loops[id] = nil
            targets[id] = nil
            pendingInRound.remove(id)
        }
    }

    /// Starts monitoring. A pause requested earlier (for example "not on Wi‑Fi" arriving before
    /// the first start) is kept, so no probe ever runs while monitoring should be paused.
    func start() {
        guard !running else { return }
        running = true
        guard !paused else { return }
        startAllLoops()
        continuation.yield(.resumed)
        AppLog.engine.info("Monitoring started for \(self.targets.count) targets")
    }

    func pause(reason: String) {
        guard !paused || pauseReason != reason else { return }
        let wasPaused = paused
        paused = true
        pauseReason = reason
        if !wasPaused { cancelAllLoops() }
        continuation.yield(.paused(reason: reason))
        AppLog.engine.info("Monitoring paused: \(reason, privacy: .public)")
    }

    func resume() {
        guard paused else { return }
        paused = false
        pauseReason = nil
        if running { startAllLoops() }
        continuation.yield(.resumed)
        AppLog.engine.info("Monitoring resumed")
    }

    /// Single entry point for the app's "should we be probing" decision. Calls can arrive out of
    /// order from separate tasks, so a call older than the last one applied is ignored.
    func setActive(_ active: Bool, reason: String, generation: Int, checkAll: Bool = false) {
        guard generation > activeGeneration else { return }
        activeGeneration = generation
        if active {
            if paused { resume() }
            if !running { start() } else if checkAll { checkAllNow() }
        } else {
            pause(reason: reason)
        }
    }

    func stop() {
        running = false
        paused = false
        pauseReason = nil
        cancelAllLoops()
    }

    /// Feeds a result measured elsewhere (a subnet scan) into the device's tracker, so the
    /// engine and the store agree and a returning device is confirmed on the fast schedule.
    func record(_ result: ProbeResult, for deviceID: UUID) {
        guard targets[deviceID] != nil else { return }
        apply(result, to: deviceID)
        if running && !paused { startLoop(for: deviceID, initialDelay: ProbeSchedule.intervalSeconds(for: targets[deviceID]?.tracker ?? ReachabilityTracker(), settings: settings)) }
    }

    /// Probes one device immediately and restarts its schedule.
    func checkNow(deviceID: UUID) async -> ProbeResult? {
        guard let target = targets[deviceID] else { return nil }
        loops[deviceID]?.cancel()
        loops[deviceID] = nil
        let result = await probeAndApply(target)
        if running && !paused { startLoop(for: deviceID, initialDelay: nil) }
        return result
    }

    /// Restarts every loop so each target is probed again right away.
    func checkAllNow() {
        guard running, !paused else { return }
        cancelAllLoops()
        pendingInRound = Set(targets.keys)
        for (index, id) in ProbeSchedule.ordered(Array(targets.values)).map(\.id).enumerated() {
            startLoop(for: id, initialDelay: Double(index) * 0.05)
        }
    }

    func tracker(for deviceID: UUID) -> ReachabilityTracker? {
        targets[deviceID]?.tracker
    }

    // MARK: - Loops

    private func startLoop(for id: UUID, initialDelay: Double? = nil) {
        loops[id]?.cancel()
        loops[id] = Task { [weak self] in
            if let initialDelay, initialDelay > 0 {
                try? await Task.sleep(for: .seconds(initialDelay))
            }
            await self?.loop(for: id)
        }
    }

    private func startAllLoops() {
        // Every target is probed right away here, backed-off ones included, so all of them count.
        pendingInRound = Set(targets.keys)
        for id in ProbeSchedule.ordered(Array(targets.values)).map(\.id) {
            startLoop(for: id)
        }
    }

    private func cancelAllLoops() {
        for task in loops.values { task.cancel() }
        loops.removeAll()
    }

    private func loop(for id: UUID) async {
        while !Task.isCancelled, running, !paused {
            guard let target = targets[id] else { return }
            let result = await probeAndApply(target)
            guard !Task.isCancelled, let updated = targets[id] else { return }
            // Nothing was learned (permission denied, no usable probe): back off to the base interval.
            let base = result.outcome.isNeutral
                ? settings.baseIntervalSeconds
                : ProbeSchedule.intervalSeconds(for: updated.tracker, settings: settings)
            let interval = ProbeSchedule.jitteredInterval(base, for: id)
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }
        }
    }

    private func probeAndApply(_ target: MonitoredTarget) async -> ProbeResult {
        await acquireSlot()
        // A loop cancelled while it waited for a slot (refresh, pause, removal) must not spend
        // the slot on a probe; the neutral result is never applied.
        guard !Task.isCancelled else {
            releaseSlot()
            return ProbeResult(host: target.host, port: target.preferredPort, kind: .tcp, outcome: .unsupported, timestamp: dateProvider.now())
        }
        let result = await probeRound(target)
        releaseSlot()

        // A probe interrupted by pause, refresh or removal says nothing about the device.
        guard !Task.isCancelled else { return result }
        apply(result, to: target.id)
        return result
    }

    private func apply(_ result: ProbeResult, to deviceID: UUID) {
        guard var current = targets[deviceID] else { return }
        let transition = current.tracker.record(result, policy: policy)
        targets[deviceID] = current

        if !result.outcome.isNeutral {
            continuation.yield(.probe(deviceID: deviceID, result: result, tracker: current.tracker))
        }
        if let transition {
            continuation.yield(.transition(deviceID: deviceID, transition: transition, tracker: current.tracker))
            AppLog.engine.info("\(current.host, privacy: .private) \(transition.from.rawValue, privacy: .public) → \(transition.to.rawValue, privacy: .public)")
        }

        pendingInRound.remove(deviceID)
        if pendingInRound.isEmpty {
            continuation.yield(.roundCompleted(at: dateProvider.now()))
            pendingInRound = Self.roundMembers(of: targets, settings: settings)
        }
    }

    /// The targets a round waits for: those probed at the base interval or faster. An offline
    /// device on back-off (up to `maxIntervalSeconds`) would otherwise hold every round, and with it
    /// the "checked" time, the Siri summary and the views that refresh per round, for minutes.
    nonisolated static func roundMembers(of targets: [UUID: MonitoredTarget], settings: MonitorSettings) -> Set<UUID> {
        Set(targets.filter { _, target in
            ProbeSchedule.intervalSeconds(for: target.tracker, settings: settings) <= settings.baseIntervalSeconds
        }.keys)
    }

    private func probeRound(_ target: MonitoredTarget) async -> ProbeResult {
        var last: ProbeResult?
        for probe in probes where !unsupportedKinds.contains(probe.kind) {
            if probe.kind == .icmp && (!settings.isICMPEnabled || IPv4Host(target.host) == nil) { continue }
            if probe.kind == .udp && !settings.isUDPEnabled { continue }
            if Task.isCancelled, let last { return last }

            let port = probe.kind == .tcp ? target.preferredPort : nil
            let result = await probe.probe(host: target.host, port: port, timeoutSeconds: settings.probeTimeoutSeconds)

            switch result.outcome {
            case .unsupported:
                unsupportedKinds.insert(probe.kind)
                continuation.yield(.probeUnsupported(probe.kind))
                continue
            case .permissionDenied:
                continuation.yield(.permissionDenied)
                return result
            default:
                break
            }
            if result.outcome.indicatesHostUp { return result }
            last = result
        }
        return last ?? ProbeResult(host: target.host, port: target.preferredPort, kind: .tcp, outcome: .unsupported, timestamp: dateProvider.now())
    }

    // MARK: - Concurrency budget

    private func acquireSlot() async {
        while activeProbes >= settings.maxConcurrentProbes {
            await withCheckedContinuation { continuation in
                slotWaiters.append(continuation)
            }
        }
        activeProbes += 1
    }

    private func releaseSlot() {
        activeProbes = max(0, activeProbes - 1)
        if !slotWaiters.isEmpty {
            slotWaiters.removeFirst().resume()
        }
    }
}
