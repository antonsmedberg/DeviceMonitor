import Foundation

/// Deterministic probe used by previews, UI tests, screenshots and the in-app demo mode.
actor DemoProbe: HostProbing {
    nonisolated let kind: ProbeKind = .demo

    private let script: [String: [ProbeOutcome]]
    private var cursors: [String: Int] = [:]
    private let dateProvider: any DateProviding

    init(script: [String: [ProbeOutcome]] = DemoFixtures.script, dateProvider: any DateProviding = SystemDateProvider()) {
        self.script = script
        self.dateProvider = dateProvider
    }

    func probe(host: String, port: UInt16?, timeoutSeconds: Double) async -> ProbeResult {
        let delay = 40 + DemoFixtures.stableNoise(host, salt: cursors[host, default: 0]) * 160
        try? await Task.sleep(for: .milliseconds(Int(delay)))
        let outcomes = script[host] ?? [.timedOut]
        let index = cursors[host, default: 0]
        cursors[host] = index + 1
        var outcome = outcomes[index % outcomes.count]
        if case .reachable(let base) = outcome {
            // Log-normal noise around the scripted median, with the host's own spread.
            let z = DemoFixtures.standardNormal(host, index: index)
            outcome = .reachable(latencyMilliseconds: base * exp(DemoFixtures.sigma(forHost: host) * z))
        }
        return ProbeResult(host: host, port: port, kind: .demo, outcome: outcome, timestamp: dateProvider.now())
    }
}

/// Anna's flat on a FRITZ!Box: 14 devices on 192.168.178.0/24 with DHCP-style addresses, two devices off,
/// a stranger that joined two hours ago, a week of daily routines and a few real incidents.
nonisolated enum DemoFixtures {
    static let networkKey = "demo:192.168.178.0/24"
    static let gatewayHost = "192.168.178.1"
    static let subnetCIDR = "192.168.178.0/24"

    nonisolated struct Seed: Sendable {
        let name: String
        var nickname: String? = nil
        let host: String
        let hostname: String?
        let kind: DeviceKind
        let vendor: String?
        let state: ReachabilityState
        /// Median latency in milliseconds.
        let latency: Double
        /// Spread of the log-normal latency around the median.
        let sigma: Double
        let ageDays: Double
        let favorite: Bool
        let trusted: Bool
        let ports: [UInt16]
        let services: [DiscoveredService]
        let mac: String?
        var routine: Routine? = nil
        var incidents: [Incident] = []
        var spikes: [Spike] = []
        /// Share of samples that hit a Wi‑Fi power-save wake-up (5–14 × the median).
        var powerSave: Double = 0
    }

    /// A daily window, in local hours, when a device is not in its seeded state: away or asleep
    /// for a device that is up now, switched on for a device that is off now.
    nonisolated struct Routine: Sendable {
        let startHour: Double
        let hours: Double
        let weekdaysOnly: Bool
    }

    /// A past outage: offline from its start, back in the seeded state `minutes` later.
    nonisolated struct Incident: Sendable {
        nonisolated enum Start: Sendable {
            /// A local clock time `daysAgo` days before today; one day earlier when it would end after now.
            case clock(hour: Int, minute: Int, daysAgo: Int)
            case minutesAgo(Int)
        }

        let start: Start
        let minutes: Int

        init(startHour: Int, minute: Int, daysAgo: Int, minutes: Int) {
            start = .clock(hour: startHour, minute: minute, daysAgo: daysAgo)
            self.minutes = minutes
        }

        init(minutesAgo: Int, minutes: Int) {
            start = .minutesAgo(minutesAgo)
            self.minutes = minutes
        }

        func interval(now: Date, calendar: Calendar) -> DateInterval {
            let duration = TimeInterval(minutes * 60)
            switch start {
            case .minutesAgo(let ago):
                return DateInterval(start: now.addingTimeInterval(-TimeInterval(ago * 60)), duration: duration)
            case .clock(let hour, let minute, let daysAgo):
                let today = calendar.startOfDay(for: now)
                let offset = TimeInterval(hour * 3600 + minute * 60)
                let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
                if day.addingTimeInterval(offset + duration) <= now {
                    return DateInterval(start: day.addingTimeInterval(offset), duration: duration)
                }
                let earlier = calendar.date(byAdding: .day, value: -1, to: day) ?? day
                return DateInterval(start: earlier.addingTimeInterval(offset), duration: duration)
            }
        }
    }

    /// A latency sample, by index in the seeded series, replaced by `factor` × the median.
    nonisolated struct Spike: Sendable {
        let index: Int
        let factor: Double
    }

    nonisolated struct LatencyProfile: Sendable {
        let sigma: Double
        let spikes: [Spike]
        let powerSave: Double
    }

    /// How far back the seeded history reaches: the 7-day activity chart.
    static let historySeconds: TimeInterval = 7 * 86_400

    /// How long ago an offline device without a routine was last seen: the office printer, off since this morning.
    private static let offlineSeconds: TimeInterval = 6 * 3600 + 18 * 60

    /// Latency spread for hosts that are not seeds, such as scripted test hosts.
    private static let fallbackSigma = 0.25

    static let seeds: [Seed] = [
        Seed(name: "Fritz!Box 7590", host: "192.168.178.1", hostname: "fritz.box", kind: .router, vendor: "AVM", state: .online, latency: 1.4, sigma: 0.18, ageDays: 400, favorite: true, trusted: true, ports: [53, 80, 443], services: [DiscoveredService(type: "_http._tcp", name: "FRITZ!Box 7590", port: 80, txt: [:])], mac: "3C:A6:2F:11:22:33", incidents: [Incident(startHour: 4, minute: 7, daysAgo: 0, minutes: 4)]),
        Seed(name: "DiskStation", host: "192.168.178.2", hostname: "diskstation.local", kind: .nas, vendor: "Synology", state: .online, latency: 1.8, sigma: 0.20, ageDays: 365, favorite: true, trusted: true, ports: [22, 443, 445, 5001], services: [DiscoveredService(type: "_smb._tcp", name: "DiskStation", port: 445, txt: [:]), DiscoveredService(type: "_https._tcp", name: "DiskStation", port: 5001, txt: ["vendor": "Synology"])], mac: "00:11:32:AB:CD:EF", incidents: [Incident(startHour: 3, minute: 20, daysAgo: 6, minutes: 12)], spikes: [Spike(index: 110, factor: 2.9), Spike(index: 116, factor: 3.4)]),
        Seed(name: "Anna's MacBook Pro", host: "192.168.178.23", hostname: "annas-macbook-pro.local", kind: .computer, vendor: "Apple", state: .online, latency: 4.6, sigma: 0.30, ageDays: 300, favorite: true, trusted: true, ports: [22], services: [DiscoveredService(type: "_ssh._tcp", name: "Anna's MacBook Pro", port: 22, txt: [:]), DiscoveredService(type: "_device-info._tcp", name: "Anna's MacBook Pro", port: nil, txt: ["model": "MacBookPro18,3"])], mac: "F0:18:98:AA:BB:CC", routine: Routine(startHour: 23, hours: 7.5, weekdaysOnly: false)),
        Seed(name: "Anna's iPhone", host: "192.168.178.31", hostname: "annas-iphone.local", kind: .phone, vendor: "Apple", state: .online, latency: 6.5, sigma: 0.35, ageDays: 300, favorite: false, trusted: true, ports: [62078], services: [DiscoveredService(type: "_companion-link._tcp", name: "Anna's iPhone", port: nil, txt: [:])], mac: nil, routine: Routine(startHour: 8, hours: 9, weekdaysOnly: true), powerSave: 0.08),
        Seed(name: "Living Room Apple TV", host: "192.168.178.38", hostname: "living-room.local", kind: .tv, vendor: "Apple", state: .online, latency: 2.7, sigma: 0.22, ageDays: 250, favorite: false, trusted: true, ports: [7000, 62078], services: [DiscoveredService(type: "_airplay._tcp", name: "Living Room", port: 7000, txt: ["model": "AppleTV14,1"])], mac: "C8:69:CD:12:34:56", routine: Routine(startHour: 0.5, hours: 6.5, weekdaysOnly: false)),
        Seed(name: "Kitchen HomePod", host: "192.168.178.44", hostname: "kitchen-homepod.local", kind: .hub, vendor: "Apple", state: .online, latency: 5.2, sigma: 0.30, ageDays: 200, favorite: false, trusted: true, ports: [7000], services: [DiscoveredService(type: "_airplay._tcp", name: "Kitchen", port: 7000, txt: ["model": "AudioAccessory5,1"])], mac: nil),
        Seed(name: "Brother HL-L2350DW", nickname: "Office Printer", host: "192.168.178.52", hostname: "brother-printer.local", kind: .printer, vendor: "Brother", state: .offline, latency: 4.8, sigma: 0.30, ageDays: 180, favorite: false, trusted: true, ports: [631, 9100], services: [DiscoveredService(type: "_ipp._tcp", name: "Brother HL-L2350DW series", port: 631, txt: ["ty": "Brother HL-L2350DW series"])], mac: "30:05:5C:77:88:99"),
        Seed(name: "Hue Bridge", host: "192.168.178.57", hostname: "philips-hue.local", kind: .hub, vendor: "Philips Hue", state: .online, latency: 3.1, sigma: 0.22, ageDays: 150, favorite: false, trusted: true, ports: [443], services: [DiscoveredService(type: "_hue._tcp", name: "Philips Hue - 1A2B3C", port: 443, txt: ["modelid": "BSB002"])], mac: nil),
        Seed(name: "Sonos One", host: "192.168.178.61", hostname: "sonos-one.local", kind: .speaker, vendor: "Sonos", state: .online, latency: 17, sigma: 0.45, ageDays: 120, favorite: false, trusted: true, ports: [1400], services: [DiscoveredService(type: "_sonos._tcp", name: "Sonos-ABC123@Living Room", port: 1400, txt: [:])], mac: nil, incidents: [Incident(minutesAgo: 190, minutes: 6), Incident(minutesAgo: 1560, minutes: 9)]),
        Seed(name: "Front Door Camera", host: "192.168.178.68", hostname: "front-door-cam.local", kind: .camera, vendor: "Reolink", state: .online, latency: 9.5, sigma: 0.35, ageDays: 90, favorite: true, trusted: true, ports: [443, 554], services: [], mac: nil),
        Seed(name: "Shelly Plug", host: "192.168.178.74", hostname: "shellyplug-s-1F2E3D.local", kind: .iot, vendor: "Shelly", state: .online, latency: 13, sigma: 0.40, ageDays: 60, favorite: false, trusted: true, ports: [80], services: [DiscoveredService(type: "_http._tcp", name: "shellyplug-s-1F2E3D", port: 80, txt: [:])], mac: nil),
        Seed(name: "PlayStation 5", host: "192.168.178.89", hostname: "ps5.local", kind: .console, vendor: "Sony", state: .offline, latency: 3.4, sigma: 0.25, ageDays: 45, favorite: false, trusted: true, ports: [], services: [], mac: "78:C8:81:44:55:66", routine: Routine(startHour: 19, hours: 2.5, weekdaysOnly: false)),
        Seed(name: "Robot Vacuum", host: "192.168.178.102", hostname: "roborock-vacuum.local", kind: .iot, vendor: "Roborock", state: .online, latency: 21, sigma: 0.45, ageDays: 30, favorite: false, trusted: true, ports: [], services: [], mac: nil),
        Seed(name: "esp_3a7f21", host: "192.168.178.117", hostname: nil, kind: .iot, vendor: "Espressif", state: .online, latency: 11, sigma: 0.40, ageDays: 0.08, favorite: false, trusted: false, ports: [80], services: [], mac: nil),
    ]

    static func devices(now: Date) -> [DeviceSnapshot] {
        seeds.map { seed in
            let lastSeen: Date
            if seed.state != .offline {
                lastSeen = now.addingTimeInterval(-20)
            } else if let routine = seed.routine, let lastSession = routineWindows(routine, host: seed.host, now: now).last {
                lastSeen = lastSession.end
            } else {
                lastSeen = now.addingTimeInterval(-offlineSeconds)
            }
            return DeviceSnapshot(
                id: id(of: seed),
                name: seed.name,
                nickname: seed.nickname,
                hostname: DeviceIdentity.normalizedHostname(seed.hostname),
                host: seed.host,
                macAddress: seed.mac,
                vendor: seed.vendor,
                kind: seed.kind,
                state: seed.state,
                confidence: seed.state == .online ? 0.97 : (seed.state == .degraded ? 0.42 : 0.05),
                latencyMilliseconds: seed.state == .offline ? nil : seed.latency,
                firstSeen: now.addingTimeInterval(-seed.ageDays * 86_400),
                lastSeen: lastSeen,
                lastChecked: now.addingTimeInterval(-20),
                isUserAdded: false,
                isFavorite: seed.favorite,
                isTrusted: seed.trusted,
                isGateway: seed.host == gatewayHost,
                tags: seed.favorite ? ["important"] : [],
                notes: "",
                preferredPort: seed.ports.first,
                openPorts: seed.ports,
                services: seed.services,
                networkKey: networkKey
            )
        }
    }

    /// Per-host outcome cycles: online devices answer; offline devices miss eight checks, then answer
    /// once, which is not enough to come back.
    static let script: [String: [ProbeOutcome]] = {
        var result: [String: [ProbeOutcome]] = [:]
        for seed in seeds {
            let answer = ProbeOutcome.reachable(latencyMilliseconds: seed.latency)
            result[seed.host] = seed.state == .offline ? Array(repeating: ProbeOutcome.timedOut, count: 8) + [answer] : [answer]
        }
        return result
    }()

    /// A week of history that ends in every device's seeded state: an arrival for devices first seen
    /// inside the week, daily routines, and incidents (the router's firmware restart, the NAS update,
    /// the speaker dropping off Wi‑Fi). Older devices get no arrival event, because a device's state
    /// before its first event is inferred from that event.
    static func statusEvents(now: Date) -> [StatusEventSnapshot] {
        let historyStart = now.addingTimeInterval(-historySeconds)
        let calendar = Calendar.current
        var events: [StatusEventSnapshot] = []
        for (seed, device) in zip(seeds, devices(now: now)) {
            if device.firstSeen > historyStart {
                events.append(event(device, "joined", at: device.firstSeen, .online))
            }
            if let routine = seed.routine {
                let exception: ReachabilityState = device.state == .offline ? .online : .offline
                for window in routineWindows(routine, host: device.host, now: now) {
                    let stamp = Int(window.start.timeIntervalSinceReferenceDate)
                    events.append(event(device, "routine:\(stamp):start", at: window.start, exception))
                    events.append(event(device, "routine:\(stamp):end", at: window.end, device.state))
                }
            } else if device.state == .offline {
                events.append(event(device, "left", at: device.lastSeen ?? now, .offline))
            }
            for (number, incident) in seed.incidents.enumerated() {
                let window = incident.interval(now: now, calendar: calendar)
                guard window.start >= historyStart, window.end <= now else { continue }
                events.append(event(device, "incident:\(number):start", at: window.start, .offline))
                events.append(event(device, "incident:\(number):end", at: window.end, device.state))
            }
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    /// Completed routine windows that start inside the history, oldest first. A stable per-day jitter
    /// keeps the week lived-in and the same calendar day identical across launches.
    private static func routineWindows(_ routine: Routine, host: String, now: Date) -> [DateInterval] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let historyStart = now.addingTimeInterval(-historySeconds)
        return (0...7).reversed().compactMap { offset -> DateInterval? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            if routine.weekdaysOnly && calendar.isDateInWeekend(day) { return nil }
            let dayNumber = Int(day.timeIntervalSinceReferenceDate / 86_400)
            let start = day.addingTimeInterval(3600 * (routine.startHour + stableNoise(host, salt: dayNumber * 2) * 0.75))
            let end = start.addingTimeInterval(3600 * (routine.hours + stableNoise(host, salt: dayNumber * 2 + 1) - 0.5))
            guard start >= historyStart, end < now else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    private static func event(_ device: DeviceSnapshot, _ tag: String, at timestamp: Date, _ state: ReachabilityState) -> StatusEventSnapshot {
        StatusEventSnapshot(id: DeviceIdentity.uuid(forKey: "evt:\(device.host):\(tag)"), deviceID: device.id, timestamp: timestamp, state: state)
    }

    /// The identifier `devices(now:)` gives a seed.
    private static func id(of seed: Seed) -> UUID {
        DeviceIdentity.uuid(forKey: DeviceIdentity.key(macAddress: seed.mac, hostname: seed.hostname, bonjourName: seed.services.first?.name, host: seed.host))
    }

    private static let profiles: [UUID: LatencyProfile] = Dictionary(uniqueKeysWithValues: seeds.map { seed in
        (id(of: seed), LatencyProfile(sigma: seed.sigma, spikes: seed.spikes, powerSave: seed.powerSave))
    })

    private static let sigmas: [String: Double] = Dictionary(uniqueKeysWithValues: seeds.map { ($0.host, $0.sigma) })

    /// The latency character of the seed with this identifier; nil for other devices.
    static func profile(for deviceID: UUID) -> LatencyProfile? {
        profiles[deviceID]
    }

    /// The seed's latency spread for a host, or the fallback for hosts that are not seeds.
    static func sigma(forHost host: String) -> Double {
        sigmas[host] ?? fallbackSigma
    }

    /// Thirty-second samples ending now, oldest first: log-normal around `baseline` with AR(1) runs,
    /// plus the seed's spikes and power-save outliers. Nothing is periodic.
    static func latencySamples(now: Date, deviceID: UUID, baseline: Double, count: Int = 180) -> [LatencySampleSnapshot] {
        let key = "lat:\(deviceID.uuidString)"
        let character = profile(for: deviceID) ?? LatencyProfile(sigma: fallbackSigma, spikes: [], powerSave: 0)
        let spikes = Dictionary(character.spikes.map { ($0.index, $0.factor) }, uniquingKeysWith: { _, last in last })
        let persistence = 0.65
        var walk = 0.0
        var samples: [LatencySampleSnapshot] = []
        samples.reserveCapacity(count)
        for index in 0..<count {
            walk = persistence * walk + (1 - persistence * persistence).squareRoot() * standardNormal(key, index: index)
            var value = baseline * exp(character.sigma * walk)
            if let factor = spikes[index] {
                value = baseline * factor
            }
            if character.powerSave > 0, stableNoise(key, salt: 10_000 + index) < character.powerSave {
                value = baseline * (5 + 9 * stableNoise(key, salt: 20_000 + index))
            }
            samples.append(LatencySampleSnapshot(
                id: DeviceIdentity.uuid(forKey: "lat:\(deviceID.uuidString):\(index)"),
                deviceID: deviceID,
                timestamp: now.addingTimeInterval(-Double(count - 1 - index) * 30),
                milliseconds: max(0.3, value),
                probeKind: .demo
            ))
        }
        return samples
    }

    /// Deterministic standard normal value (Box–Muller) from a string and an index.
    static func standardNormal(_ text: String, index: Int) -> Double {
        let u1 = max(stableNoise(text, salt: 2 * index), 0.0001)
        let u2 = stableNoise(text, salt: 2 * index + 1)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    /// Deterministic pseudo-random value in 0..<1 from a string and a salt.
    static func stableNoise(_ text: String, salt: Int) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        hash ^= UInt64(truncatingIfNeeded: salt) &* 0x9e37_79b9_7f4a_7c15
        hash ^= hash >> 29
        hash &*= 0xbf58_476d_1ce4_e5b9
        hash ^= hash >> 32
        return Double(hash % 10_000) / 10_000
    }
}
