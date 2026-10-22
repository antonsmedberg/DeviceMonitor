import Foundation
import SwiftUI
import SwiftData
import Observation
import os

/// Composition root. Owns the store, the monitoring engine and the discovery streams,
/// and is the single writer of `DeviceDirectory`.
@Observable
@MainActor
final class AppEnvironment {
    let isDemo: Bool
    let directory: DeviceDirectory
    let router: AppRouter
    let settings: SettingsStore
    let haptics: HapticsController
    let insightProvider: any InsightProviding

    private(set) var store: DeviceStore?
    private(set) var startupError: DeviceMonitorError?
    private(set) var bannerError: DeviceMonitorError?
    private(set) var pathStatus: NetworkPathStatus
    private(set) var permissionState: LocalNetworkPermissionState = .undetermined
    private(set) var isPausedByUser = false
    private(set) var pauseReason: String?
    private(set) var isScanning = false
    private(set) var scanProgress: ScanProgress?
    private(set) var scanFound: [DiscoveredHost] = []
    private(set) var lastScanAt: Date?
    private(set) var currentSubnet: IPv4Subnet?
    private(set) var currentNetworkKey: String?
    private(set) var unsupportedProbes: Set<ProbeKind> = []
    private(set) var hasStarted = false

    private let engine: MonitorEngine
    private let probes: [any HostProbing]
    private let pathObserver: NetworkPathObserver?
    private let bonjour: BonjourBrowser?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var pathTask: Task<Void, Never>?
    @ObservationIgnored private var bonjourTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var pendingBatch: [(deviceID: UUID, result: ProbeResult, tracker: ReachabilityTracker, transition: ReachabilityTransition?)] = []
    @ObservationIgnored private var ownAddresses: Set<String> = []
    @ObservationIgnored private var monitoringGeneration = 0
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var isInForeground = true
    @ObservationIgnored private var hasPathStatus = false

    private init(
        isDemo: Bool,
        startup: ModelContainerFactory.Startup,
        probes: [any HostProbing],
        pathObserver: NetworkPathObserver?,
        bonjour: BonjourBrowser?,
        settings: SettingsStore
    ) {
        self.isDemo = isDemo
        self.settings = settings
        self.router = AppRouter()
        self.directory = DeviceDirectory()
        self.haptics = HapticsController(settings: settings)
        self.insightProvider = FoundationModelsInsightProvider()
        self.probes = probes
        self.pathObserver = pathObserver
        self.bonjour = bonjour
        self.store = startup.container.map { DeviceStore(container: $0) }
        self.startupError = startup.container == nil ? startup.error : nil
        self.bannerError = startup.container != nil ? startup.error : nil
        self.pathStatus = isDemo
            ? NetworkPathStatus(isSatisfied: true, isWiFi: true, isExpensive: false, isConstrained: false, wifiInterfaceName: "en0", gatewayHosts: [DemoFixtures.gatewayHost], isLocalNetworkDenied: false)
            : .unavailable
        self.engine = MonitorEngine(probes: probes, policy: settings.policy, settings: settings.monitor)
        AppLog.store.info("Store opened: \(startup.outcome.rawValue, privacy: .public)")
    }

    static func make(arguments: LaunchArguments) -> AppEnvironment {
        arguments.usesDemoData || SettingsStore.usesDemoDataOnLaunch ? demo() : live()
    }

    static func live() -> AppEnvironment {
        AppEnvironment(
            isDemo: false,
            startup: ModelContainerFactory.makePersistent(),
            probes: [TCPProbe(), ICMPProbe(), UDPProbe()],
            pathObserver: NetworkPathObserver(),
            bonjour: BonjourBrowser(),
            settings: SettingsStore()
        )
    }

    static func demo() -> AppEnvironment {
        let defaults = UserDefaults(suiteName: "eu.smedberg.DeviceMonitor.demo") ?? .standard
        let settings = SettingsStore(defaults: defaults)
        settings.hasCompletedOnboarding = true
        let startup: ModelContainerFactory.Startup
        do {
            startup = ModelContainerFactory.Startup(container: try ModelContainerFactory.makeInMemory(), outcome: .inMemoryFallback, error: nil)
        } catch {
            startup = ModelContainerFactory.Startup(container: nil, outcome: .inMemoryFallback, error: .storeUnavailable(underlying: error.localizedDescription))
        }
        let environment = AppEnvironment(isDemo: true, startup: startup, probes: [DemoProbe()], pathObserver: nil, bonjour: nil, settings: settings)
        environment.seedDemoData()
        return environment
    }

    // MARK: - Lifecycle

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        haptics.prepare()
        ownAddresses = Set(LocalInterfaceEnumerator.ipv4Interfaces().map { $0.address.description })

        if !isDemo {
            loadFromStore()
        }
        startEventConsumer()
        startPathObserver()
        // Browsing is what shows the Local Network alert, so before onboarding it waits for the
        // welcome screen (or the first scan) to explain why the app asks.
        if settings.hasCompletedOnboarding {
            startBonjour()
        }

        let targets = makeTargets()
        Task {
            await engine.setTargets(targets)
        }
        // Without a path observer (demo) there is no network to wait for; otherwise the first
        // path status decides whether monitoring may run.
        if pathObserver == nil {
            updateMonitoring()
        }

        pruneHistory(silently: true)

        if settings.pendingScanRequested {
            settings.pendingScanRequested = false
            router.present(.scan)
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard hasStarted else { return }
        switch phase {
        case .background:
            flushBatch()
            isInForeground = false
            updateMonitoring()
            Task { await bonjour?.stop() }
        case .active:
            let isReturning = !isInForeground
            isInForeground = true
            // Back from the background (often from Settings): look at a denial again. Browsing
            // restarts below and reports it at once if access is still off, and so does a scan.
            if isReturning, permissionState == .denied {
                permissionState = .undetermined
            }
            updateMonitoring()
            if bonjourTask != nil {
                Task { await bonjour?.start() }
            }
        default:
            break
        }
    }

    func applySettings() {
        let monitor = settings.monitor
        let policy = settings.policy
        Task { await engine.updateSettings(monitor, policy: policy) }
        updateMonitoring()
    }

    /// Whether the network allows probing the LAN right now.
    private var canMonitor: Bool {
        if pathObserver == nil { return true }
        guard hasPathStatus, pathStatus.isSatisfied else { return false }
        return pathStatus.isWiFi || !settings.monitor.pauseOnCellular
    }

    private var pauseReasonText: String {
        if !isInForeground { return "App in background" }
        if isPausedByUser { return "Paused by you" }
        if !pathStatus.isSatisfied { return "No network connection" }
        return "Not on Wi‑Fi"
    }

    /// The one place that decides whether the engine runs. Every input (path, scene, user pause,
    /// settings) calls this, and the generation keeps late-arriving calls from undoing newer ones.
    private func updateMonitoring(checkAll: Bool = false) {
        monitoringGeneration += 1
        let generation = monitoringGeneration
        let active = canMonitor && isInForeground && !isPausedByUser
        let reason = pauseReasonText
        Task { await engine.setActive(active, reason: reason, generation: generation, checkAll: checkAll) }
    }

    // MARK: - Monitoring controls

    func checkAllNow() {
        guard !isPausedByUser else { return }
        haptics.impact()
        Task { await engine.checkAllNow() }
    }

    /// Probes one device now and writes the result before returning, so callers can reload history.
    func checkNow(deviceID: UUID) async {
        // Off the LAN a probe can only fail, and recording that would log an outage that never happened.
        guard canMonitor else {
            bannerError = .noWiFi
            haptics.warning()
            return
        }
        _ = await engine.checkNow(deviceID: deviceID)
        // Let the event consumer handle what the engine just emitted, then persist it.
        try? await Task.sleep(for: .milliseconds(120))
        flushBatch()
    }

    func togglePause() {
        isPausedByUser.toggle()
        updateMonitoring()
    }

    // MARK: - Devices

    func addManualDevice(name: String, host: String, preferredPort: UInt16?) throws(DeviceMonitorError) {
        guard let store else { throw DeviceMonitorError.storeUnavailable(underlying: "no store") }
        // An address on this Wi‑Fi's subnet belongs to this network; hostnames and other addresses
        // mean the same thing everywhere and stay unscoped.
        let address = IPv4Host(host.trimmingCharacters(in: .whitespacesAndNewlines))
        let networkKey = address.flatMap { currentSubnet?.contains($0) == true ? currentNetworkKey : nil }
        let snapshot: DeviceSnapshot
        do {
            snapshot = try store.addManual(name: name, host: host, preferredPort: preferredPort, networkKey: networkKey)
        } catch let error as DeviceMonitorError {
            throw error
        } catch {
            throw DeviceMonitorError.storeUnavailable(underlying: error.localizedDescription)
        }
        directory.apply(snapshot)
        let target = MonitoredTarget(snapshot: snapshot, isGateway: false)
        Task { await engine.addTarget(target) }
        haptics.success()
    }

    func remove(deviceIDs: [UUID]) {
        guard let store, !deviceIDs.isEmpty else { return }
        do {
            try store.delete(ids: deviceIDs)
            directory.remove(ids: deviceIDs)
            if let selected = router.selectedDeviceID, deviceIDs.contains(selected) {
                router.selectedDeviceID = nil
            }
            Task { await engine.removeTargets(ids: deviceIDs) }
        } catch {
            report(error)
        }
    }

    func apply(_ edit: DeviceEdit) throws(DeviceMonitorError) {
        guard let store else { throw DeviceMonitorError.storeUnavailable(underlying: "no store") }
        do {
            if let snapshot = try store.applyEdit(edit) {
                directory.apply(snapshot)
                let target = MonitoredTarget(snapshot: snapshot, isGateway: snapshot.isGateway)
                Task { await engine.setTargets(self.makeTargets().map { $0.id == target.id ? target : $0 }) }
            }
        } catch let error as DeviceMonitorError {
            throw error
        } catch {
            throw DeviceMonitorError.storeUnavailable(underlying: error.localizedDescription)
        }
    }

    func toggleFavorite(_ id: UUID) {
        guard let store, let device = directory.device(id: id) else { return }
        do {
            if let snapshot = try store.setFavorite(deviceID: id, isFavorite: !device.isFavorite) {
                directory.apply(snapshot)
                haptics.selection()
            }
        } catch {
            report(error)
        }
    }

    func toggleTrusted(_ id: UUID) {
        guard let store, let device = directory.device(id: id) else { return }
        do {
            if let snapshot = try store.setTrusted(deviceID: id, isTrusted: !device.isTrusted) {
                directory.apply(snapshot)
                haptics.selection()
            }
        } catch {
            report(error)
        }
    }

    func addDiscovered(_ hosts: [DiscoveredHost]) {
        guard let store else { return }
        let filtered = hosts.filter { !ownAddresses.contains($0.host) }
        guard !filtered.isEmpty else { return }
        do {
            let knownStates = Dictionary(directory.devices.map { ($0.id, $0.state) }, uniquingKeysWith: { first, _ in first })
            let snapshots = try store.upsert(discovered: filtered, networkKey: currentNetworkKey, gatewayHosts: Set(pathStatus.gatewayHosts))
            directory.apply(snapshots)

            // Known devices may have moved to a new address; setTargets updates host and port and
            // keeps their trackers. Their fresh probe results go to the engine, which owns state.
            let probesByHost = Dictionary(filtered.compactMap { host in host.probe.map { (host.host, $0) } }, uniquingKeysWith: { first, _ in first })
            let forwarded: [(UUID, ProbeResult)] = snapshots.compactMap { snapshot in
                guard let probe = probesByHost[snapshot.host], let state = knownStates[snapshot.id], state != .unknown else { return nil }
                return (snapshot.id, probe)
            }
            let targets = makeTargets()
            Task {
                await engine.setTargets(targets)
                for (id, probe) in forwarded {
                    await engine.record(probe, for: id)
                }
            }
            if filtered.contains(where: { $0.probe?.outcome.indicatesHostUp == true }) {
                markLocalNetworkWorking()
            }
        } catch {
            report(error)
        }
    }

    /// Any answer from the LAN proves access works, including after the user enabled it in Settings.
    private func markLocalNetworkWorking() {
        if permissionState != .likelyGranted {
            permissionState = .likelyGranted
        }
    }

    // MARK: - Scanning

    /// Parallel probes per scan.
    static let scanConcurrency = 32

    /// `probeCount` is how many probes each silent address waits out in turn; the time ceiling
    /// grows with it and with the subnet, so a /22 (eero's default) is swept completely.
    func makeScanRequest(probeCount: Int = 3) throws(DeviceMonitorError) -> ScanRequest {
        guard pathStatus.isWiFi else { throw DeviceMonitorError.noWiFi }
        guard let subnet = currentSubnet else { throw DeviceMonitorError.noIPv4Address }
        guard subnet.isScannable else { throw DeviceMonitorError.subnetTooLarge(prefixLength: subnet.prefixLength) }
        let timeout = isDemo ? 0.3 : 1.5
        let maxDuration = ScanRequest.durationCeiling(
            hostCount: subnet.hostCount,
            concurrency: Self.scanConcurrency,
            perHostSeconds: Double(max(1, probeCount)) * (timeout + ScanRequest.probeOverheadSeconds)
        )
        return ScanRequest(subnet: subnet, gatewayHosts: pathStatus.gatewayHosts, excludedHosts: ownAddresses, timeoutSeconds: timeout, maxDurationSeconds: maxDuration)
    }

    func startScan() {
        guard !isScanning else { return }
        // The scan honours the same probe switches as monitoring.
        let scanProbes = probes.filter { probe in
            switch probe.kind {
            case .icmp: return settings.monitor.isICMPEnabled && !unsupportedProbes.contains(.icmp)
            case .udp: return settings.monitor.isUDPEnabled && !unsupportedProbes.contains(.udp)
            case .tcp, .bonjour, .demo: return true
            }
        }
        let request: ScanRequest
        do {
            request = try makeScanRequest(probeCount: scanProbes.count)
        } catch {
            // Clear the previous scan so the sheet does not show it as if this one had finished.
            scanProgress = nil
            scanFound = []
            bannerError = error
            return
        }
        bannerError = nil
        isScanning = true
        scanFound = []
        scanProgress = ScanProgress(scanned: 0, total: request.subnet.hostCount, found: 0)
        // A user who chose "Not Now" at onboarding starts discovery with the first scan.
        startBonjour()
        let scanner = SubnetScanner(probes: scanProbes, concurrency: Self.scanConcurrency)
        scanGeneration += 1
        let generation = scanGeneration

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await update in scanner.scan(request) {
                    switch update {
                    case .progress(let progress):
                        scanProgress = progress
                    case .found(let host):
                        scanFound.append(host)
                        addDiscovered([host])
                    case .permissionDenied:
                        permissionState = .denied
                    case .finished:
                        break
                    }
                }
                // Cancelling ends the stream without an error; a stopped scan is not a finished one.
                guard !Task.isCancelled else { return }
                lastScanAt = Date()
                haptics.success()
            } catch let error as DeviceMonitorError {
                if error == .scanTimedOut { lastScanAt = Date() }
                if error != .scanCancelled { bannerError = error }
            } catch {
                bannerError = .scanTimedOut
            }
            guard generation == scanGeneration else { return }
            isScanning = false
            scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanGeneration += 1
        isScanning = false
    }

    /// A quick latency and loss reading: `count` probes in a row, preferring ping (ICMP) and
    /// falling back to a TCP connect. The results are shown, never fed into the device's state.
    func pingBurst(deviceID: UUID, count: Int = 5) async -> [PingSample] {
        guard let device = directory.device(id: deviceID) else { return [] }
        let usable = probes.filter { probe in
            switch probe.kind {
            case .icmp:
                return settings.monitor.isICMPEnabled && !unsupportedProbes.contains(.icmp) && IPv4Host(device.host) != nil
            case .tcp, .demo:
                return true
            case .udp, .bonjour:
                return false
            }
        }
        guard var probe = usable.first(where: { $0.kind == .icmp }) ?? usable.first else { return [] }
        let fallback = usable.first { $0.kind != .icmp }
        var samples: [PingSample] = []
        for index in 1...max(1, count) {
            guard !Task.isCancelled else { break }
            let port = probe.kind == .tcp ? device.preferredPort : nil
            var result = await probe.probe(host: device.host, port: port, timeoutSeconds: settings.monitor.probeTimeoutSeconds)
            if result.outcome == .unsupported, let fallback {
                probe = fallback
                result = await probe.probe(host: device.host, port: device.preferredPort, timeoutSeconds: settings.monitor.probeTimeoutSeconds)
            }
            samples.append(PingSample(index: index, outcome: result.outcome, kind: result.kind))
            if index < count {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        if samples.contains(where: { $0.outcome.indicatesHostUp }) {
            markLocalNetworkWorking()
        }
        return samples
    }

    /// Checks the common ports and saves the open ones. A scan that proves nothing (the device did
    /// not answer, or local network access is off) keeps the stored ports and throws instead.
    func scanPorts(deviceID: UUID) async throws(DeviceMonitorError) -> [PortScanResult] {
        guard let device = directory.device(id: deviceID) else { throw DeviceMonitorError.deviceNotFound(deviceID) }
        let scanner = PortScanner(probe: isDemo ? DemoPortProbe(openPorts: device.openPorts) : TCPProbe())
        let scan = await scanner.scan(host: device.host)
        guard scan.hostAnswered else {
            let error: DeviceMonitorError = scan.permissionDenied ? .localNetworkDenied : .deviceDidNotAnswer
            if scan.permissionDenied { permissionState = .denied }
            bannerError = error
            throw error
        }
        markLocalNetworkWorking()
        let results = scan.results
        let open = results.filter(\.isOpen).map(\.port)
        if let store {
            do {
                if let snapshot = try store.setOpenPorts(deviceID: deviceID, ports: open) {
                    directory.apply(snapshot)
                }
            } catch {
                report(error)
            }
        }
        // As in the security score, the router's own DNS and admin web ports are expected there.
        return results.map { result in
            PortScanResult(port: result.port, isOpen: result.isOpen, serviceName: result.serviceName, risk: SecurityAssessor.risk(port: result.port, isGateway: device.isGateway))
        }
    }

    // MARK: - Actions

    func wake(deviceID: UUID) async {
        guard let device = directory.device(id: deviceID), let macText = device.macAddress, let mac = MACAddress(macText) else {
            bannerError = .wakeFailed("this device has no MAC address yet; add one in Edit")
            return
        }
        do {
            try await WakeOnLANSender.send(mac: mac, toHost: device.host)
            haptics.success()
        } catch {
            bannerError = error
            haptics.error()
        }
    }

    func requestLocalNetworkPermission() async {
        guard !isDemo else {
            permissionState = .likelyGranted
            return
        }
        await LocalNetworkPermission.triggerPrompt()
        // The user has now been told why the app asks, so discovery may start.
        startBonjour()
        if permissionState == .undetermined {
            // The system alert is asynchronous; a later successful probe confirms the grant.
            try? await Task.sleep(for: .seconds(1))
        }
    }

    func dismissBannerError() {
        bannerError = nil
    }

    // MARK: - History and export

    func statusEvents(deviceID: UUID, limit: Int) -> [StatusEventSnapshot] {
        guard let store else { return [] }
        do {
            return try store.statusEvents(deviceID: deviceID, limit: limit)
        } catch {
            report(error)
            return []
        }
    }

    func latencySamples(deviceID: UUID, since: Date) -> [LatencySampleSnapshot] {
        guard let store else { return [] }
        do {
            return try store.latencySamples(deviceID: deviceID, since: since)
        } catch {
            report(error)
            return []
        }
    }

    /// Networks this phone has monitored, newest first.
    func knownNetworks() -> [(key: String, displayName: String, lastSeen: Date)] {
        guard let store else { return [] }
        do {
            return try store.knownNetworks()
        } catch {
            report(error)
            return []
        }
    }

    /// Newest first; every retained event unless `limit` is given.
    func recentEvents(since: Date, limit: Int? = nil) -> [StatusEventSnapshot] {
        guard let store else { return [] }
        do {
            return try store.recentEvents(since: since, limit: limit)
        } catch {
            report(error)
            return []
        }
    }

    func exportCSV() -> String {
        DeviceExport.csv(directory.devices)
    }

    func exportJSON() throws(DeviceMonitorError) -> Data {
        try DeviceExport.json(directory.devices, events: recentEvents(since: .distantPast))
    }

    func pruneHistory(silently: Bool = false) {
        guard let store else { return }
        do {
            let deleted = try store.pruneHistory()
            if !silently, deleted > 0 { haptics.success() }
        } catch {
            if !silently { report(error) }
        }
    }

    func deleteAllHistory() {
        guard let store else { return }
        do {
            try store.deleteAllHistory()
            directory.markHistoryChanged()
            haptics.success()
        } catch {
            report(error)
        }
    }

    func resetNicknames() {
        guard let store else { return }
        do {
            try store.resetNicknames()
            directory.replaceAll(try store.loadSnapshots())
        } catch {
            report(error)
        }
    }

    // MARK: - Private

    private func seedDemoData() {
        guard let store else { return }
        let now = Date()
        do {
            try store.seedDemo(devices: DemoFixtures.devices(now: now), events: DemoFixtures.statusEvents(now: now)) { id, baseline in
                DemoFixtures.latencySamples(now: now, deviceID: id, baseline: baseline)
            }
            try store.recordNetwork(key: DemoFixtures.networkKey, displayName: "Home", gatewayHost: DemoFixtures.gatewayHost, subnetCIDR: DemoFixtures.subnetCIDR)
            currentSubnet = IPv4Subnet(cidr: DemoFixtures.subnetCIDR)
            currentNetworkKey = DemoFixtures.networkKey
            directory.replaceAll(try store.loadSnapshots())
            directory.markRound(at: now)
            permissionState = .likelyGranted
            lastScanAt = now.addingTimeInterval(-1800)
        } catch {
            report(error)
        }
    }

    private func loadFromStore() {
        guard let store else { return }
        do {
            try store.removeMigratedSampleDevices()
            directory.replaceAll(try store.loadSnapshots())
        } catch {
            report(error)
        }
    }

    /// Devices of the current network, plus devices that belong to none (hostnames, manual
    /// addresses off this subnet, rows from 1.0). Devices of other networks are left alone: probing
    /// their addresses here would log false outages, or reach strangers that happen to use them.
    private func makeTargets() -> [MonitoredTarget] {
        let gateways = Set(pathStatus.gatewayHosts)
        return directory.devices
            .filter { $0.networkKey == nil || $0.networkKey == currentNetworkKey }
            .map { MonitoredTarget(snapshot: $0, isGateway: $0.isGateway || gateways.contains($0.host)) }
    }

    private func startEventConsumer() {
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in engine.events {
                handle(event)
            }
        }
    }

    private func handle(_ event: MonitorEvent) {
        switch event {
        case .probe(let id, let result, let tracker):
            if var snapshot = directory.device(id: id) {
                snapshot.state = tracker.state
                snapshot.confidence = tracker.confidence
                snapshot.lastChecked = result.timestamp
                if result.outcome.indicatesHostUp {
                    snapshot.lastSeen = result.timestamp
                    markLocalNetworkWorking()
                }
                if let latency = result.outcome.latencyMilliseconds {
                    snapshot.latencyMilliseconds = latency
                } else {
                    snapshot.latencyMilliseconds = nil
                }
                directory.apply(snapshot)
            }
            pendingBatch.append((deviceID: id, result: result, tracker: tracker, transition: nil))
            scheduleFlush()

        case .transition(let id, let transition, let tracker):
            if let index = pendingBatch.lastIndex(where: { $0.deviceID == id && $0.transition == nil }) {
                pendingBatch[index].transition = transition
                pendingBatch[index].tracker = tracker
            } else if let device = directory.device(id: id) {
                let synthetic = ProbeResult(host: device.host, port: nil, kind: .tcp, outcome: transition.to.isUp ? .reachable(latencyMilliseconds: device.latencyMilliseconds ?? 0) : .timedOut, timestamp: transition.at)
                pendingBatch.append((deviceID: id, result: synthetic, tracker: tracker, transition: transition))
            }
            if transition.to == .offline, let device = directory.device(id: id), device.isFavorite {
                haptics.warning()
            }
            // Transitions are rare and views reload history when a state changes, so write the
            // event now instead of after the coalescing delay.
            flushBatch()

        case .roundCompleted(let at):
            // Views reload on a new round; the round's last results must be stored by then.
            flushBatch()
            directory.markRound(at: at)
            // Siri reads this summary; demo rounds must not stand in for the user's own network.
            if !isDemo {
                NetworkStatusSummary(
                    online: directory.onlineCount,
                    unstable: directory.degradedCount,
                    offline: directory.offlineCount,
                    total: directory.devices.count,
                    checkedAt: at
                ).save()
            }

        case .paused(let reason):
            pauseReason = reason

        case .resumed:
            pauseReason = nil

        case .permissionDenied:
            permissionState = .denied

        case .probeUnsupported(let kind):
            unsupportedProbes.insert(kind)
        }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.flushBatch()
        }
    }

    private func flushBatch() {
        flushTask?.cancel()
        flushTask = nil
        guard let store, !pendingBatch.isEmpty else {
            pendingBatch.removeAll()
            return
        }
        let batch = pendingBatch
        pendingBatch.removeAll()
        do {
            let snapshots = try store.applyProbeBatch(batch)
            directory.apply(snapshots)
            if batch.contains(where: { $0.transition != nil }) {
                directory.markHistoryChanged()
            }
        } catch {
            report(error)
        }
    }

    private func startPathObserver() {
        guard let pathObserver else { return }
        pathTask = Task { [weak self] in
            let stream = await pathObserver.statuses()
            for await status in stream {
                guard let self else { return }
                handlePath(status)
            }
        }
    }

    private func handlePath(_ status: NetworkPathStatus) {
        let previous = pathStatus
        let isFirstStatus = !hasPathStatus
        pathStatus = status
        hasPathStatus = true
        if status.isLocalNetworkDenied {
            permissionState = .denied
        }
        refreshSubnet()
        updateMonitoring(checkAll: !isFirstStatus && status.isWiFi && !previous.isWiFi)

        if status.isWiFi, let store, !status.gatewayHosts.isEmpty {
            do {
                let changed = try store.markGateway(hosts: Set(status.gatewayHosts), networkKey: currentNetworkKey)
                if !changed.isEmpty {
                    directory.apply(changed)
                    let targets = makeTargets()
                    Task { await engine.setTargets(targets) }
                }
            } catch {
                report(error)
            }
        }
    }

    private func refreshSubnet() {
        guard !isDemo else { return }
        // Rebuilt on every path change: addresses change with DHCP leases and networks, and a stale
        // one would hide whichever device gets it next from scans and Bonjour.
        let interfaces = LocalInterfaceEnumerator.ipv4Interfaces()
        guard pathStatus.isWiFi, let interface = LocalInterfaceEnumerator.wifiInterface(named: pathStatus.wifiInterfaceName) else {
            ownAddresses = Set(interfaces.map { $0.address.description })
            currentSubnet = nil
            return
        }
        // Only this phone's addresses on the LAN: a cellular address that falls inside the subnet
        // belongs to someone else there.
        ownAddresses = Set(interfaces.filter { $0.name == interface.name }.map { $0.address.description })
        ownAddresses.insert(interface.address.description)
        currentSubnet = interface.subnet
        guard let subnet = interface.subnet else { return }
        // The first IPv4 gateway: an IPv6 link-local one would give the same network a second key.
        let gateway = pathStatus.gatewayHosts.first(where: { IPv4Host($0) != nil }) ?? IPv4Host(rawValue: subnet.network.rawValue &+ 1).description
        let key = "net:\(gateway)/\(subnet.description)"
        guard key != currentNetworkKey else { return }
        currentNetworkKey = key
        // Monitor this network's devices and stop probing the previous network's.
        let targets = makeTargets()
        Task { await engine.setTargets(targets) }
        do {
            try store?.recordNetwork(key: key, displayName: "Wi‑Fi \(subnet.description)", gatewayHost: gateway, subnetCIDR: subnet.description)
        } catch {
            report(error)
        }
    }

    /// Starts browsing once; later calls do nothing (the event stream has a single consumer).
    private func startBonjour() {
        guard let bonjour, bonjourTask == nil else { return }
        bonjourTask = Task { [weak self] in
            let stream = await bonjour.events()
            await bonjour.start()
            for await event in stream {
                guard let self else { return }
                handleDiscovery(event)
            }
        }
    }

    private func handleDiscovery(_ event: DiscoveryEvent) {
        switch event {
        case .serviceAdded(let service, let host, let hostname):
            guard let host, IPv4Host(host) != nil || HostInputValidator.isValidIPv6(host) else { return }
            // Browse results only arrive with local network access, so this proves it works.
            markLocalNetworkWorking()
            addDiscovered([DiscoveredHost(host: host, hostname: hostname, services: [service])])
        case .serviceRemoved:
            break
        case .permissionDenied:
            permissionState = .denied
        case .failed(let type, let message):
            AppLog.discovery.error("Bonjour \(type, privacy: .public): \(message, privacy: .public)")
        }
    }

    private func report(_ error: any Error) {
        if let known = error as? DeviceMonitorError {
            bannerError = known
        } else {
            bannerError = .storeUnavailable(underlying: error.localizedDescription)
        }
        AppLog.app.error("\(error.localizedDescription, privacy: .public)")
    }
}

/// Port probe for demo mode: reports the fixture's open ports without touching the network.
actor DemoPortProbe: HostProbing {
    nonisolated let kind: ProbeKind = .demo
    private let openPorts: Set<UInt16>

    init(openPorts: [UInt16]) {
        self.openPorts = Set(openPorts)
    }

    func probe(host: String, port: UInt16?, timeoutSeconds: Double) async -> ProbeResult {
        try? await Task.sleep(for: .milliseconds(60))
        let isOpen = port.map { openPorts.contains($0) } ?? false
        return ProbeResult(host: host, port: port, kind: .demo, outcome: isOpen ? .reachable(latencyMilliseconds: 3) : .refused(latencyMilliseconds: 2), timestamp: Date())
    }
}
