import Foundation
import os

/// Sweeps an IPv4 subnet with bounded concurrency. Emits found hosts immediately and progress every few hosts.
actor SubnetScanner {
    private let probes: [any HostProbing]
    private let concurrency: Int
    private let dateProvider: any DateProviding

    init(probes: [any HostProbing], concurrency: Int = 32, dateProvider: any DateProviding = SystemDateProvider()) {
        self.probes = probes
        self.concurrency = max(1, concurrency)
        self.dateProvider = dateProvider
    }

    nonisolated func scan(_ request: ScanRequest) -> AsyncThrowingStream<ScanUpdate, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await self.run(request, continuation: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ request: ScanRequest, continuation: AsyncThrowingStream<ScanUpdate, any Error>.Continuation) async {
        guard request.subnet.isScannable else {
            continuation.finish(throwing: DeviceMonitorError.subnetTooLarge(prefixLength: request.subnet.prefixLength))
            return
        }

        let all = request.subnet.hosts().map(\.description).filter { !request.excludedHosts.contains($0) }
        let gateways = all.filter { request.gatewayHosts.contains($0) }
        let hosts = gateways + all.filter { !request.gatewayHosts.contains($0) }
        let total = hosts.count
        let deadline = dateProvider.now().addingTimeInterval(request.maxDurationSeconds)
        var scanned = 0
        var found: [DiscoveredHost] = []
        var permissionDenied = false
        var timedOut = false

        AppLog.discovery.info("Scanning \(request.subnet.description, privacy: .private) (\(total) hosts)")

        await withTaskGroup(of: DiscoveredHost?.self) { group in
            var iterator = hosts.makeIterator()
            var inFlight = 0

            for _ in 0..<min(concurrency, total) {
                guard let host = iterator.next() else { break }
                group.addTask { await self.probeHost(host, request: request) }
                inFlight += 1
            }

            while inFlight > 0 {
                guard let result = await group.next() else { break }
                inFlight -= 1
                scanned += 1

                if let result {
                    if result.probe?.outcome == .permissionDenied {
                        permissionDenied = true
                    } else {
                        found.append(result)
                        continuation.yield(.found(result))
                    }
                }

                if scanned % 8 == 0 || scanned == total {
                    continuation.yield(.progress(ScanProgress(scanned: scanned, total: total, found: found.count)))
                }

                if Task.isCancelled || permissionDenied {
                    group.cancelAll()
                    break
                }
                if dateProvider.now() > deadline {
                    timedOut = true
                    group.cancelAll()
                    break
                }
                if let host = iterator.next() {
                    group.addTask { await self.probeHost(host, request: request) }
                    inFlight += 1
                }
            }
        }

        if permissionDenied {
            continuation.yield(.permissionDenied)
            continuation.finish(throwing: DeviceMonitorError.localNetworkDenied)
            return
        }
        if Task.isCancelled {
            continuation.finish(throwing: DeviceMonitorError.scanCancelled)
            return
        }
        continuation.yield(.progress(ScanProgress(scanned: scanned, total: total, found: found.count)))
        continuation.yield(.finished(found))
        if timedOut {
            // Report a partial scan as such instead of as a complete one.
            AppLog.discovery.warning("Scan hit the time ceiling after \(scanned) of \(total) hosts")
            continuation.finish(throwing: DeviceMonitorError.scanTimedOut)
        } else {
            continuation.finish()
        }
    }

    nonisolated private func probeHost(_ host: String, request: ScanRequest) async -> DiscoveredHost? {
        for probe in probes {
            if Task.isCancelled { return nil }
            let result = await probe.probe(host: host, port: nil, timeoutSeconds: request.timeoutSeconds)
            if result.outcome == .permissionDenied {
                return DiscoveredHost(host: host, probe: result)
            }
            if result.outcome.indicatesHostUp {
                return DiscoveredHost(host: host, probe: result)
            }
        }
        return nil
    }
}

/// What a port scan found, and whether it proved anything about the host.
nonisolated struct PortScanReport: Sendable, Hashable {
    let results: [PortScanResult]
    /// Some port accepted or refused a connection, so the host is up and closed ports really are closed.
    /// Without an answer every port merely timed out, which says nothing about what is open.
    let hostAnswered: Bool
    let permissionDenied: Bool

    init(results: [PortScanResult], hostAnswered: Bool, permissionDenied: Bool) {
        self.results = results
        self.hostAnswered = hostAnswered
        self.permissionDenied = permissionDenied
    }
}

/// Checks a list of TCP ports on one host with bounded concurrency.
actor PortScanner {
    private let probe: any HostProbing
    private let concurrency: Int

    init(probe: any HostProbing = TCPProbe(), concurrency: Int = 8) {
        self.probe = probe
        self.concurrency = max(1, concurrency)
    }

    func scan(host: String, ports: [UInt16] = SecurityAssessor.commonPorts, timeoutSeconds: Double = 1.0) async -> PortScanReport {
        await withTaskGroup(of: (PortScanResult?, ProbeOutcome).self, returning: PortScanReport.self) { group in
            var iterator = ports.makeIterator()
            var inFlight = 0
            var results: [PortScanResult] = []
            var hostAnswered = false
            var permissionDenied = false

            for _ in 0..<min(concurrency, ports.count) {
                guard let port = iterator.next() else { break }
                group.addTask { await self.check(host: host, port: port, timeoutSeconds: timeoutSeconds) }
                inFlight += 1
            }

            while inFlight > 0 {
                guard let entry = await group.next() else { break }
                let (result, outcome) = entry
                inFlight -= 1
                if let result { results.append(result) }
                if outcome.indicatesHostUp { hostAnswered = true }
                if outcome == .permissionDenied { permissionDenied = true }
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let port = iterator.next() {
                    group.addTask { await self.check(host: host, port: port, timeoutSeconds: timeoutSeconds) }
                    inFlight += 1
                }
            }
            return PortScanReport(results: results.sorted { $0.port < $1.port }, hostAnswered: hostAnswered, permissionDenied: permissionDenied)
        }
    }

    nonisolated private func check(host: String, port: UInt16, timeoutSeconds: Double) async -> (PortScanResult?, ProbeOutcome) {
        let result = await probe.probe(host: host, port: port, timeoutSeconds: timeoutSeconds)
        switch result.outcome {
        case .reachable:
            return (PortScanResult(port: port, isOpen: true, serviceName: SecurityAssessor.serviceName(port: port), risk: SecurityAssessor.risk(port: port)), result.outcome)
        case .refused, .timedOut, .unreachable:
            return (PortScanResult(port: port, isOpen: false, serviceName: SecurityAssessor.serviceName(port: port), risk: SecurityAssessor.risk(port: port)), result.outcome)
        case .permissionDenied, .unsupported:
            return (nil, result.outcome)
        }
    }
}
