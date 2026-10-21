import Foundation
import SwiftData
import os

/// All SwiftData reads and writes, on the main context. Views never touch models directly:
/// they read `DeviceSnapshot` values from `DeviceDirectory`.
@MainActor
final class DeviceStore {
    /// The store owns the container: a `ModelContext` does not keep its container alive, and a
    /// context whose container was released crashes on first use.
    let container: ModelContainer
    let modelContext: ModelContext
    let limits: StorageLimits
    let dateProvider: any DateProviding

    init(container: ModelContainer, limits: StorageLimits = .standard, dateProvider: any DateProviding = SystemDateProvider()) {
        self.container = container
        self.modelContext = container.mainContext
        self.limits = limits
        self.dateProvider = dateProvider
    }

    // MARK: - Reading

    func loadSnapshots() throws -> [DeviceSnapshot] {
        try fetchAllDevices().map { $0.snapshot() }.sorted(by: Self.defaultOrder)
    }

    func snapshot(id: UUID) throws -> DeviceSnapshot? {
        try fetchDevice(id: id)?.snapshot()
    }

    func statusEvents(deviceID: UUID, limit: Int) throws -> [StatusEventSnapshot] {
        guard let device = try fetchDevice(id: deviceID) else { return [] }
        return device.statusHistory
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(max(0, limit))
            .map { $0.snapshot(deviceID: deviceID) }
    }

    /// Newest first. Without a limit every retained event is returned; retention already bounds
    /// the total (`maxStatusEventsPerDevice` per device, `eventRetentionDays`).
    func recentEvents(since: Date, limit: Int? = nil) throws -> [StatusEventSnapshot] {
        var descriptor = FetchDescriptor<StatusEvent>(
            predicate: #Predicate { $0.timestamp >= since },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        if let limit {
            descriptor.fetchLimit = max(1, limit)
        }
        return try modelContext.fetch(descriptor).compactMap { event in
            guard let deviceID = event.device?.id else { return nil }
            return event.snapshot(deviceID: deviceID)
        }
    }

    func latencySamples(deviceID: UUID, since: Date) throws -> [LatencySampleSnapshot] {
        guard let device = try fetchDevice(id: deviceID) else { return [] }
        return device.latencySamples
            .filter { $0.timestamp >= since }
            .sorted { $0.timestamp < $1.timestamp }
            .map { $0.snapshot(deviceID: deviceID) }
    }

    func knownNetworks() throws -> [(key: String, displayName: String, lastSeen: Date)] {
        let descriptor = FetchDescriptor<KnownNetwork>(sortBy: [SortDescriptor(\.lastSeen, order: .reverse)])
        return try modelContext.fetch(descriptor).map { ($0.key, $0.displayName, $0.lastSeen) }
    }

    // MARK: - Discovery and manual devices

    /// Merges scan/Bonjour results by stable identity so nicknames, notes and tags never reset.
    ///
    /// A probe attached to a host is applied here only for devices that are new or still unknown;
    /// for known devices the monitor engine owns reachability, and the caller forwards the probe there.
    @discardableResult
    func upsert(discovered hosts: [DiscoveredHost], networkKey: String?, gatewayHosts: Set<String> = []) throws -> [DeviceSnapshot] {
        let now = dateProvider.now()
        var existing = try fetchAllDevices()
        var touched: [Device] = []

        for host in hosts {
            let hostname = DeviceIdentity.normalizedHostname(host.hostname)
            let bonjourName = host.services.first?.name
            let harvestedMAC = DeviceIdentity.bonjourIdentity(bonjourName)?.mac?.description
            let key = DeviceIdentity.key(macAddress: host.macAddress ?? harvestedMAC, hostname: hostname, bonjourName: bonjourName, host: host.host)
            let globalMAC = (host.macAddress ?? harvestedMAC).flatMap { text -> String? in
                guard let mac = MACAddress(text), !mac.isLocallyAdministered else { return nil }
                return mac.description
            }

            let device: Device
            var isNewDevice = false
            if let match = Self.existingDevice(
                for: host, key: key, hostname: hostname, bonjourName: bonjourName, mac: globalMAC,
                networkKey: networkKey, now: now, in: existing
            ) {
                device = match
                device.ipAddress = host.host
                // The strongest identity wins, so a later AirPlay sighting never downgrades a MAC key.
                if DeviceIdentity.strength(of: key) > DeviceIdentity.strength(of: device.identityKey) {
                    device.identityKey = key
                }
            } else {
                guard existing.count < limits.maxDevices else {
                    AppLog.store.warning("Device limit reached; ignoring \(host.host, privacy: .private)")
                    continue
                }
                let suggested = DeviceClassifier.suggestedName(from: host.services, hostname: hostname, host: host.host)
                device = Device(name: Self.truncated(suggested, limits.maxNameLength), ipAddress: host.host, identityKey: key, firstSeen: now)
                modelContext.insert(device)
                existing.append(device)
                isNewDevice = true
            }

            if let hostname { device.hostname = hostname }
            if let mac = host.macAddress ?? harvestedMAC, let parsed = MACAddress(mac), device.macAddress == nil || host.macAddress != nil {
                device.macAddress = parsed.description
            }
            if !host.services.isEmpty {
                var merged = device.services.filter { current in !host.services.contains { $0.id == current.id } }
                merged.append(contentsOf: host.services)
                device.services = Array(merged.suffix(32))
            }
            // A discovered device's name is recomputed whenever Bonjour or hostname evidence arrives, so "Device 42"
            // from a bare scan becomes "Living Room" later. A user-added device keeps the name the user typed.
            if !device.isUserAdded, hostname != nil || !host.services.isEmpty {
                let suggested = DeviceClassifier.suggestedName(from: device.services, hostname: device.hostname, host: host.host)
                device.name = Self.truncated(suggested, limits.maxNameLength)
            }
            if let vendor = DeviceClassifier.vendor(from: device.services, hostname: device.hostname) {
                device.vendor = vendor
            }
            let isGateway = gatewayHosts.contains(host.host)
            if isGateway { device.isGateway = true }
            if !device.kindIsUserSet {
                let classified = DeviceClassifier.kind(
                    services: device.services,
                    openPorts: device.openPorts,
                    hostname: device.hostname,
                    vendor: device.vendor,
                    isGateway: device.isGateway
                )
                // A sighting without evidence (a bare connection probe) never downgrades a known kind.
                if classified != .unknown || device.kind == .unknown {
                    device.kind = classified
                }
            }
            if let networkKey { device.networkKey = networkKey }

            if let probe = host.probe, isNewDevice || device.state == .unknown {
                var tracker = ReachabilityTracker(state: device.state, confidence: device.confidence, lastSeen: device.lastSeen)
                let transition = tracker.record(probe, policy: .standard)
                apply(tracker: tracker, result: probe, transition: transition, to: device, now: now)
            } else if host.probe == nil, device.state == .unknown {
                // Seen on the network without a probe (Bonjour): treat as a soft hit.
                let synthetic = ProbeResult(host: host.host, port: nil, kind: .bonjour, outcome: .reachable(latencyMilliseconds: 0), timestamp: now)
                var tracker = ReachabilityTracker(state: device.state, confidence: device.confidence, lastSeen: device.lastSeen)
                let transition = tracker.record(synthetic, policy: .standard)
                apply(tracker: tracker, result: synthetic, transition: transition, to: device, now: now, recordLatency: false)
            }
            touched.append(device)
        }

        try save()
        return touched.map { $0.snapshot() }
    }

    /// `networkKey` scopes the device to the network it was added on (an address on that subnet);
    /// leave it nil for hostnames and other addresses that mean the same thing everywhere.
    func addManual(name: String, host: String, preferredPort: UInt16?, networkKey: String? = nil) throws -> DeviceSnapshot {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DeviceMonitorError.invalidInput(field: "name", reason: "Give the device a name.")
        }
        let input: HostInput
        switch HostInputValidator.validate(host) {
        case .success(let valid): input = valid
        case .failure(let error): throw error
        }
        let existing = try fetchAllDevices()
        let key = DeviceIdentity.key(macAddress: nil, hostname: input.kind == .hostname ? input.normalized : nil, bonjourName: nil, host: input.normalized)
        // Discovery may have moved a hostname-added device to its IP, so compare identities too.
        if existing.contains(where: { $0.identityKey == key || $0.ipAddress.caseInsensitiveCompare(input.normalized) == .orderedSame }) {
            throw DeviceMonitorError.duplicateDevice(host: input.normalized)
        }
        guard existing.count < limits.maxDevices else {
            throw DeviceMonitorError.deviceLimitReached(limit: limits.maxDevices)
        }

        let device = Device(
            name: Self.truncated(trimmedName, limits.maxNameLength),
            ipAddress: input.normalized,
            isUserAdded: true,
            identityKey: key,
            firstSeen: dateProvider.now()
        )
        device.preferredPortValue = preferredPort
        device.networkKey = networkKey
        modelContext.insert(device)
        try save()
        return device.snapshot()
    }

    // MARK: - Probe results

    func applyProbeBatch(_ batch: [(deviceID: UUID, result: ProbeResult, tracker: ReachabilityTracker, transition: ReachabilityTransition?)]) throws -> [DeviceSnapshot] {
        var snapshots: [DeviceSnapshot] = []
        let now = dateProvider.now()
        for item in batch {
            guard let device = try fetchDevice(id: item.deviceID) else { continue }
            apply(tracker: item.tracker, result: item.result, transition: item.transition, to: device, now: now)
            snapshots.append(device.snapshot())
        }
        try save()
        return snapshots
    }

    // MARK: - Editing

    @discardableResult
    func applyEdit(_ edit: DeviceEdit) throws -> DeviceSnapshot? {
        guard let device = try fetchDevice(id: edit.id) else {
            throw DeviceMonitorError.deviceNotFound(edit.id)
        }
        // Validate before touching the model: the main context is shared and saved by every later
        // write, so a rejected edit must leave nothing behind for the user's Cancel to undo.
        let macText = edit.macAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let macAddress = MACAddress(macText)
        if !macText.isEmpty && macAddress == nil {
            throw DeviceMonitorError.invalidInput(field: "MAC address", reason: "Enter a MAC address such as A4:83:E7:12:34:56.")
        }
        let nickname = edit.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        device.nickname = nickname.isEmpty ? nil : Self.truncated(nickname, limits.maxNameLength)
        if device.kind != edit.kind {
            device.kind = edit.kind
            device.kindIsUserSet = true
        }
        device.tags = Self.sanitizedTags(edit.tags, limits: limits)
        device.notes = Self.truncated(edit.notes, limits.maxNotesLength)
        device.isFavorite = edit.isFavorite
        device.isTrusted = edit.isTrusted
        device.macAddress = macAddress?.description
        device.preferredPortValue = edit.preferredPort
        try save()
        return device.snapshot()
    }

    func setFavorite(deviceID: UUID, isFavorite: Bool) throws -> DeviceSnapshot? {
        guard let device = try fetchDevice(id: deviceID) else { return nil }
        device.isFavorite = isFavorite
        try save()
        return device.snapshot()
    }

    func setTrusted(deviceID: UUID, isTrusted: Bool) throws -> DeviceSnapshot? {
        guard let device = try fetchDevice(id: deviceID) else { return nil }
        device.isTrusted = isTrusted
        try save()
        return device.snapshot()
    }

    func setOpenPorts(deviceID: UUID, ports: [UInt16]) throws -> DeviceSnapshot? {
        guard let device = try fetchDevice(id: deviceID) else { return nil }
        device.openPorts = ports
        if !device.kindIsUserSet {
            let classified = DeviceClassifier.kind(services: device.services, openPorts: ports, hostname: device.hostname, vendor: device.vendor, isGateway: device.isGateway)
            // As in discovery, a scan without evidence never downgrades a known kind.
            if classified != .unknown || device.kind == .unknown {
                device.kind = classified
            }
        }
        try save()
        return device.snapshot()
    }

    /// Flags the devices at the gateway addresses. With a `networkKey`, devices of other networks
    /// keep their flag, so the home router stays the router while the phone is elsewhere.
    func markGateway(hosts: Set<String>, networkKey: String? = nil) throws -> [DeviceSnapshot] {
        let devices = try fetchAllDevices()
        var changed: [DeviceSnapshot] = []
        for device in devices {
            if let networkKey, let deviceNetwork = device.networkKey, deviceNetwork != networkKey { continue }
            let shouldBeGateway = hosts.contains(device.ipAddress)
            if device.isGateway != shouldBeGateway {
                device.isGateway = shouldBeGateway
                if shouldBeGateway, !device.kindIsUserSet { device.kind = .router }
                changed.append(device.snapshot())
            }
        }
        if !changed.isEmpty { try save() }
        return changed
    }

    func delete(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        for device in try fetchAllDevices() where idSet.contains(device.id) {
            modelContext.delete(device)
        }
        try save()
    }

    func recordNetwork(key: String, displayName: String, gatewayHost: String, subnetCIDR: String) throws {
        let descriptor = FetchDescriptor<KnownNetwork>(predicate: #Predicate { $0.key == key })
        let now = dateProvider.now()
        if let network = try modelContext.fetch(descriptor).first {
            network.lastSeen = now
            network.gatewayHost = gatewayHost
            network.subnetCIDR = subnetCIDR
        } else {
            modelContext.insert(KnownNetwork(key: key, displayName: displayName, gatewayHost: gatewayHost, subnetCIDR: subnetCIDR, firstSeen: now, lastSeen: now))
        }
        try save()
    }

    // MARK: - Maintenance

    /// Enforces retention limits. Returns the number of deleted rows.
    @discardableResult
    func pruneHistory() throws -> Int {
        let now = dateProvider.now()
        let eventCutoff = now.addingTimeInterval(-Double(limits.eventRetentionDays) * 86_400)
        let sampleCutoff = now.addingTimeInterval(-Double(limits.latencyRetentionDays) * 86_400)
        var deleted = 0

        for device in try fetchAllDevices() {
            let events = device.statusHistory.sorted { $0.timestamp > $1.timestamp }
            for (index, event) in events.enumerated() where index >= limits.maxStatusEventsPerDevice || event.timestamp < eventCutoff {
                modelContext.delete(event)
                deleted += 1
            }
            let samples = device.latencySamples.sorted { $0.timestamp > $1.timestamp }
            for (index, sample) in samples.enumerated() where index >= limits.maxLatencySamplesPerDevice || sample.timestamp < sampleCutoff {
                modelContext.delete(sample)
                deleted += 1
            }
        }

        if deleted > 0 { try save() }
        return deleted
    }

    /// Version 1.0 had no discovery: every device it stored that the user did not add came from its
    /// built-in sample data (Camera-01, Gateway, NAS-Backup…). The migration carries those rows over
    /// with an empty identity and `distantPast` as first sighting, which nothing in this version
    /// writes, so they are removed with their history before they are monitored or merged.
    @discardableResult
    func removeMigratedSampleDevices() throws -> Int {
        let samples = try fetchAllDevices().filter { device in
            !device.isUserAdded && device.identityKey.isEmpty && device.firstSeen == Date.distantPast
        }
        guard !samples.isEmpty else { return 0 }
        for device in samples {
            modelContext.delete(device)
        }
        try save()
        AppLog.store.info("Removed \(samples.count) sample devices from version 1.0")
        return samples.count
    }

    func resetNicknames() throws {
        for device in try fetchAllDevices() {
            device.nickname = nil
        }
        try save()
    }

    func deleteAllHistory() throws {
        try modelContext.delete(model: StatusEvent.self)
        try modelContext.delete(model: LatencySample.self)
        try save()
    }

    func save() throws {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            // Drop the unsaved changes so the next write (or autosave) does not commit them anyway.
            modelContext.rollback()
            AppLog.store.error("Save failed: \(error.localizedDescription, privacy: .public)")
            throw DeviceMonitorError.storeUnavailable(underlying: error.localizedDescription)
        }
    }

    // MARK: - Private

    /// How recently a device must have been seen for a new service at its address to join it.
    static let siblingWindowSeconds: TimeInterval = 300

    /// Finds the stored device a sighting belongs to, or nil for a new device.
    ///
    /// Each Bonjour service arrives on its own, and one device's services carry different evidence:
    /// AirPlay says "Living Room", RAOP says "<MAC>@Living Room", Wi‑Fi sync says "<MAC>@<IPv6>".
    /// A MAC identifies a device anywhere; hostnames, Bonjour names and addresses are only unique
    /// on one network, so those match only devices of this network (or devices without one).
    private static func existingDevice(
        for host: DiscoveredHost,
        key: String,
        hostname: String?,
        bonjourName: String?,
        mac: String?,
        networkKey: String?,
        now: Date,
        in existing: [Device]
    ) -> Device? {
        let keyIsAddressOnly = key.hasPrefix("ip:")
        let onThisNetwork: (Device) -> Bool = { device in
            networkKey == nil || device.networkKey == nil || device.networkKey == networkKey
        }

        // 1. The same identity.
        if let exact = existing.first(where: { $0.identityKey == key && (key.hasPrefix("mac:") || onThisNetwork($0)) }) {
            return exact
        }

        // 2. The same device seen through another of its services: the same MAC, the same mDNS
        //    hostname (unique on a network), or at the same address a service with the same name
        //    ("Living Room" and "<MAC>@Living Room"; names are only unique per service type).
        if !keyIsAddressOnly {
            let identity = DeviceIdentity.bonjourIdentity(bonjourName)
            let sharesEvidence: (Device) -> Bool = { device in
                if let mac, device.macAddress == mac || device.identityKey == "mac:\(mac)" { return true }
                guard onThisNetwork(device) else { return false }
                if let hostname, device.hostname == hostname || device.identityKey == "host:\(hostname)" { return true }
                guard let identity, device.ipAddress == host.host else { return false }
                return device.identityKey == "bonjour:\(identity.name)"
                    || device.services.contains { DeviceIdentity.bonjourIdentity($0.name)?.name == identity.name }
            }
            let candidates = existing.filter(sharesEvidence)
            if let sibling = candidates.first(where: { $0.ipAddress == host.host }) ?? candidates.first {
                return sibling
            }
        }

        // 3. A scan only knows the address, so it joins whatever device already lives there;
        //    a stronger key (hostname, Bonjour, MAC) upgrades an address-only device.
        if let sameAddress = existing.first(where: {
            $0.ipAddress == host.host && onThisNetwork($0)
                && (keyIsAddressOnly || $0.identityKey.isEmpty || $0.identityKey.hasPrefix("ip:"))
        }) {
            return sameAddress
        }

        // 4. Two hosts cannot hold one IPv4 address at the same moment, so a service whose name
        //    shares nothing with the others (Wi‑Fi sync, Matter) belongs to the device just seen there.
        guard !keyIsAddressOnly, IPv4Host(host.host) != nil else { return nil }
        return existing.first { device in
            guard device.ipAddress == host.host, onThisNetwork(device),
                  let lastSeen = device.lastSeen, now.timeIntervalSince(lastSeen) < Self.siblingWindowSeconds else { return false }
            // A different mDNS hostname means a different host that was handed the address.
            if let hostname, let other = device.hostname, other != hostname { return false }
            return true
        }
    }

    private func apply(tracker: ReachabilityTracker, result: ProbeResult, transition: ReachabilityTransition?, to device: Device, now: Date, recordLatency: Bool = true) {
        device.state = tracker.state
        device.confidence = tracker.confidence
        device.lastChecked = result.timestamp
        if result.outcome.indicatesHostUp {
            device.lastSeen = result.timestamp
        }
        if let latency = result.outcome.latencyMilliseconds, recordLatency {
            device.latestLatencyMs = latency
            let lastSample = device.latencySamples.max { $0.timestamp < $1.timestamp }
            if lastSample == nil || result.timestamp.timeIntervalSince(lastSample!.timestamp) >= limits.minLatencySampleSpacingSeconds {
                let sample = LatencySample(timestamp: result.timestamp, milliseconds: latency, probeKindRaw: result.kind.rawValue, device: device)
                modelContext.insert(sample)
                trimLatencySamples(of: device)
            }
        } else if !result.outcome.indicatesHostUp, !result.outcome.isNeutral {
            device.latestLatencyMs = nil
        }
        if let transition {
            let event = StatusEvent(timestamp: transition.at, isOnline: transition.to.isUp, stateRaw: transition.to.rawValue, device: device)
            modelContext.insert(event)
            trimStatusEvents(of: device)
        }
    }

    private func trimStatusEvents(of device: Device) {
        let events = device.statusHistory.sorted { $0.timestamp > $1.timestamp }
        guard events.count > limits.maxStatusEventsPerDevice else { return }
        for event in events[limits.maxStatusEventsPerDevice...] {
            modelContext.delete(event)
        }
    }

    private func trimLatencySamples(of device: Device) {
        let samples = device.latencySamples.sorted { $0.timestamp > $1.timestamp }
        guard samples.count > limits.maxLatencySamplesPerDevice else { return }
        for sample in samples[limits.maxLatencySamplesPerDevice...] {
            modelContext.delete(sample)
        }
    }

    private func fetchAllDevices() throws -> [Device] {
        try modelContext.fetch(FetchDescriptor<Device>())
    }

    private func fetchDevice(id: UUID) throws -> Device? {
        var descriptor = FetchDescriptor<Device>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    static func defaultOrder(_ lhs: DeviceSnapshot, _ rhs: DeviceSnapshot) -> Bool {
        if lhs.isGateway != rhs.isGateway { return lhs.isGateway }
        if lhs.state.sortRank != rhs.state.sortRank { return lhs.state.sortRank < rhs.state.sortRank }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    static func truncated(_ value: String, _ limit: Int) -> String {
        value.count <= limit ? value : String(value.prefix(limit))
    }

    static func sanitizedTags(_ tags: [String], limits: StorageLimits) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in tags {
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { continue }
            let clipped = truncated(tag, limits.maxTagLength)
            let key = clipped.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(clipped)
            if result.count >= limits.maxTags { break }
        }
        return result
    }
}
