import Foundation
import Testing
@testable import DeviceMonitor

/// Noon on a fixed day, so "same day", "yesterday" and "this week" do not depend on when the tests run.
private let noon = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)).addingTimeInterval(12 * 3600)

private func device(
    _ name: String,
    host: String = "10.0.0.\(Int.random(in: 2...250))",
    kind: DeviceKind = .unknown,
    state: ReachabilityState = .online,
    firstSeen: Date = noon.addingTimeInterval(-30 * 86_400),
    lastSeen: Date? = nil,
    isUserAdded: Bool = false,
    isGateway: Bool = false,
    networkKey: String? = nil
) -> DeviceSnapshot {
    DeviceSnapshot(
        id: UUID(),
        name: name,
        host: host,
        kind: kind,
        state: state,
        firstSeen: firstSeen,
        lastSeen: lastSeen,
        isUserAdded: isUserAdded,
        isGateway: isGateway,
        networkKey: networkKey
    )
}

private func event(_ deviceID: UUID, _ state: ReachabilityState, at date: Date) -> StatusEventSnapshot {
    StatusEventSnapshot(id: UUID(), deviceID: deviceID, timestamp: date, state: state)
}

@Suite("Header status")
struct HeaderStatusTests {
    private func status(_ devices: [DeviceSnapshot], isPaused: Bool = false, pauseReason: String? = nil) -> HeaderStatus {
        HeaderStatus.make(devices: devices, isPaused: isPaused, pauseReason: pauseReason, now: noon)
    }

    @Test func emptyAndPaused() {
        let empty = status([])
        #expect(empty.title == "No devices yet")
        #expect(empty.target == HeaderStatus.Target.none)

        let byUser = status([device("NAS")], isPaused: true)
        #expect(byUser.title == "Monitoring paused")
        #expect(byUser.subtitle == nil)

        let offWiFi = status([device("NAS")], isPaused: true, pauseReason: "Paused off Wi‑Fi")
        #expect(offWiFi.subtitle == "Paused off Wi‑Fi")
        #expect(offWiFi.target == HeaderStatus.Target.none)
    }

    @Test func routerOfflineBeatsOfflineDevices() {
        let router = device("Router", state: .offline, isGateway: true)
        let result = status([router, device("Printer", state: .offline), device("Console", state: .offline)])
        #expect(result.title == "Your router isn't answering")
        #expect(result.target == .device(router.id))
    }

    @Test func noProblems() {
        #expect(status([device("Router", isGateway: true), device("NAS")]).title == "All devices answering")
        #expect(status([device("NAS", state: .unknown), device("TV", state: .unknown)]).title == "Checking devices")
    }

    @Test func oneOfflineDeviceIsNamedWithItsStory() {
        let lastSeen = noon.addingTimeInterval(-3 * 3600)
        let printer = device("Printer", state: .offline, lastSeen: lastSeen)
        let result = status([device("NAS"), printer])
        #expect(result.title == "Printer is offline")
        #expect(result.subtitle == HeaderStatus.sincePhrase(lastSeen, now: noon))
        #expect(result.target == .device(printer.id))

        let speaker = device("Speaker", state: .degraded)
        let unstable = status([device("NAS"), speaker])
        #expect(unstable.title == "Speaker is unstable")
        #expect(unstable.subtitle == "Missing some checks")
    }

    @Test func sincePhraseByAge() {
        let sameDay = noon.addingTimeInterval(-3 * 3600)
        #expect(HeaderStatus.sincePhrase(sameDay, now: noon) == "Since \(sameDay.formatted(date: .omitted, time: .shortened))")
        let yesterday = noon.addingTimeInterval(-86_400)
        #expect(HeaderStatus.sincePhrase(yesterday, now: noon) == "Since yesterday, \(yesterday.formatted(date: .omitted, time: .shortened))")
        let threeDays = noon.addingTimeInterval(-3 * 86_400)
        #expect(HeaderStatus.sincePhrase(threeDays, now: noon) == "Since \(threeDays.formatted(.dateTime.weekday(.wide)))")
        let tenDays = noon.addingTimeInterval(-10 * 86_400)
        #expect(HeaderStatus.sincePhrase(tenDays, now: noon) == "Since \(tenDays.formatted(date: .abbreviated, time: .omitted))")
    }

    @Test func twoOfflineDevicesAreListedMostRecentFirst() {
        let printer = device("Printer", state: .offline, lastSeen: noon.addingTimeInterval(-3600))
        let console = device("Console", state: .offline, lastSeen: noon.addingTimeInterval(-7200))
        let result = status([console, device("NAS"), printer])
        #expect(result.title == ListFormatter.localizedString(byJoining: ["Printer", "Console"]) + " are offline")
        #expect(result.target == .offlineDevices)
    }

    @Test func mixedProblemsNeedAttention() {
        let result = status([device("Printer", state: .offline), device("Speaker", state: .degraded)])
        #expect(result.title == ListFormatter.localizedString(byJoining: ["Printer", "Speaker"]) + " need attention")
        #expect(result.target == HeaderStatus.Target.none)
    }

    @Test func manyProblemsAreCounted() {
        let devices = (1...5).map { device("Device \($0)", state: .offline) }
        let result = status(devices)
        #expect(result.title == "5 devices need attention")
        #expect(result.target == .offlineDevices)
    }
}

@Suite("Monitor status")
struct MonitorStatusTests {
    private func status(
        isScanning: Bool = false,
        isPausedByUser: Bool = false,
        pauseReason: String? = nil,
        isOnWiFi: Bool = true,
        isDemo: Bool = false,
        hasDevices: Bool = true,
        lastRoundAt: Date? = noon
    ) -> MonitorStatus {
        MonitorStatus.make(
            isScanning: isScanning,
            scanProgress: ScanProgress(scanned: 160, total: 254, found: 9),
            isPausedByUser: isPausedByUser,
            pauseReason: pauseReason,
            isOnWiFi: isOnWiFi,
            isDemo: isDemo,
            hasDevices: hasDevices,
            lastRoundAt: lastRoundAt,
            intervalSeconds: 30,
            now: noon
        )
    }

    @Test func precedence() {
        #expect(status(isScanning: true, isPausedByUser: true, isOnWiFi: false).kind == .scanning(fraction: 160.0 / 254.0, found: 9))
        #expect(status(isPausedByUser: true, isOnWiFi: false).kind == .paused(reason: nil))
        #expect(status(pauseReason: "Paused off Wi‑Fi", isOnWiFi: false).kind == .paused(reason: "Paused off Wi‑Fi"))
        #expect(status(isOnWiFi: false, hasDevices: false).kind == .offWiFi)
        #expect(status(isOnWiFi: false, isDemo: true).kind == .live)
        #expect(status(hasDevices: false).kind == .empty)
    }

    @Test func staleOnlyAfterTwoIntervalsAndTenSeconds() {
        #expect(status(lastRoundAt: noon.addingTimeInterval(-70)).kind == .live)
        let last = noon.addingTimeInterval(-71)
        #expect(status(lastRoundAt: last).kind == .stale(lastRound: last))
        #expect(status(lastRoundAt: nil).isLive)
    }

    @Test func accessoryOnlyForNews() {
        #expect(status().showsAccessory == false)
        #expect(status(hasDevices: false).showsAccessory == false)
        #expect(status(isScanning: true).showsAccessory)
        #expect(status(isPausedByUser: true).showsAccessory)
        #expect(status(isOnWiFi: false).showsAccessory)
        #expect(status(lastRoundAt: noon.addingTimeInterval(-600)).showsAccessory)
    }

    @Test func texts() {
        let live = MonitorStatus(kind: .live)
        #expect(live.headline(now: noon) == "Live")
        #expect(live.shortHeadline(now: noon) == "Live")
        #expect(live.symbol == "circle.fill")

        let scanning = MonitorStatus(kind: .scanning(fraction: 0.63, found: 9))
        #expect(scanning.headline(now: noon) == "Scanning · \(Formatters.percent(0.63)) · 9 found")
        #expect(scanning.shortHeadline(now: noon) == "Scanning \(Formatters.percent(0.63))")
        #expect(scanning.symbol == "dot.radiowaves.left.and.right")

        let paused = MonitorStatus(kind: .paused(reason: nil))
        #expect(paused.headline(now: noon) == "Monitoring paused")
        #expect(paused.shortHeadline(now: noon) == "Paused")
        #expect(MonitorStatus(kind: .paused(reason: "Paused off Wi‑Fi")).headline(now: noon) == "Paused off Wi‑Fi")

        let offWiFi = MonitorStatus(kind: .offWiFi)
        #expect(offWiFi.headline(now: noon) == "Not on Wi‑Fi")
        #expect(offWiFi.shortHeadline(now: noon) == "Off Wi‑Fi")
        #expect(offWiFi.symbol == "wifi.slash")

        let stale = MonitorStatus(kind: .stale(lastRound: noon.addingTimeInterval(-360)))
        #expect(stale.headline(now: noon) == "Last checked 6 min ago")
        #expect(stale.shortHeadline(now: noon) == "6 min ago")
        #expect(stale.symbol == "clock.badge.exclamationmark")

        let empty = MonitorStatus(kind: .empty)
        #expect(empty.headline(now: noon) == "No devices yet")
        #expect(empty.shortHeadline(now: noon) == "No devices")
        #expect(empty.symbol == "circle.dashed")
    }
}

@Suite("Latency quality")
struct LatencyQualityTests {
    private let steady = [1.8, 1.9, 2.0, 2.1, 2.2]

    @Test func grades() {
        #expect(LatencyQuality.assess(latest: nil, samples: steady) == nil)
        #expect(LatencyQuality.assess(latest: 2.0, samples: steady) == .fast)
        #expect(LatencyQuality.assess(latest: 2.5, samples: steady) == .normal)
        #expect(LatencyQuality.assess(latest: 5, samples: steady) == .slower)
        #expect(LatencyQuality.assess(latest: 120, samples: steady) == .slow)
    }

    /// Slower than usual needs both twice the median and one more millisecond.
    @Test func slowerNeedsAMillisecondMore() {
        let tiny = [0.4, 0.5, 0.5, 0.6, 0.6]
        #expect(LatencyQuality.assess(latest: 1.2, samples: tiny) == .normal)
        #expect(LatencyQuality.assess(latest: 1.6, samples: tiny) == .slower)
    }

    @Test func fewerThanFourSamplesUseTheAbsoluteRule() {
        let few = [2.0, 2.0]
        #expect(LatencyQuality.assess(latest: 5, samples: few) == .fast)
        #expect(LatencyQuality.assess(latest: 30, samples: few) == .normal)
        #expect(LatencyQuality.assess(latest: 100, samples: few) == .slow)
        #expect(LatencyQuality.isOutOfBand(latest: 30, samples: few) == false)
        #expect(LatencyQuality.isOutOfBand(latest: 100, samples: few))
    }

    @Test func showsTypicalOnlyWhenItSaysSomething() {
        let samples = [18.0, 19, 20, 21, 22]
        #expect(LatencyQuality.showsTypical(latest: 20, samples: samples) == false)
        #expect(LatencyQuality.showsTypical(latest: 22.8, samples: samples) == false)
        #expect(LatencyQuality.showsTypical(latest: 23, samples: samples))
        #expect(LatencyQuality.showsTypical(latest: 45, samples: samples))
        #expect(LatencyQuality.showsTypical(latest: 150, samples: [20, 20]) == false)
    }
}

@Suite("Uptime cells")
struct UptimeCellsTests {
    @Test func stateRule() {
        #expect(UptimeCells.state(offlineSeconds: 119, unstableSeconds: 0, knownSeconds: 3600, duration: 3600) == .unstable)
        #expect(UptimeCells.state(offlineSeconds: 120, unstableSeconds: 0, knownSeconds: 3600, duration: 3600) == .offline)
        #expect(UptimeCells.state(offlineSeconds: 240, unstableSeconds: 0, knownSeconds: 86_400, duration: 86_400) == .unstable)
        #expect(UptimeCells.state(offlineSeconds: 0, unstableSeconds: 300, knownSeconds: 3600, duration: 3600) == .unstable)
        #expect(UptimeCells.state(offlineSeconds: 0, unstableSeconds: 0, knownSeconds: 0, duration: 3600) == .noData)
        #expect(UptimeCells.state(offlineSeconds: 0, unstableSeconds: 0, knownSeconds: 3600, duration: 3600) == .online)
    }

    @Test func recentCellsEndNowAndStartAtFirstSeen() {
        let cells = UptimeCells.recent(count: 24, span: 86_400, events: [], currentState: .online, firstSeen: noon.addingTimeInterval(-7200), now: noon)
        #expect(cells.count == 24)
        #expect(cells.first?.interval.start == noon.addingTimeInterval(-86_400))
        #expect(cells.last?.interval.end == noon)
        #expect(cells.prefix(22).allSatisfy { $0.state == .noData && $0.availability == nil })
        #expect(cells.suffix(2).allSatisfy { $0.state == .online && $0.availability == 1 })
    }

    @Test func unstableTimeCountsAsUp() throws {
        let id = UUID()
        let hourStart = noon.addingTimeInterval(-3600)
        let events = [event(id, .degraded, at: hourStart.addingTimeInterval(600)), event(id, .online, at: hourStart.addingTimeInterval(1200))]
        let cells = UptimeCells.recent(count: 1, span: 3600, events: events, currentState: .online, firstSeen: noon.addingTimeInterval(-86_400), now: noon)
        let cell = try #require(cells.first)
        #expect(cell.state == .unstable)
        #expect(cell.availability == 1)
        #expect(cell.offlineSeconds == 0)
    }

    @Test func outagesAreCountedWhereTheyStart() throws {
        let id = UUID()
        let hourStart = noon.addingTimeInterval(-3600)
        let events = [
            event(id, .offline, at: hourStart.addingTimeInterval(300)), event(id, .online, at: hourStart.addingTimeInterval(400)),
            event(id, .offline, at: hourStart.addingTimeInterval(1000)), event(id, .online, at: hourStart.addingTimeInterval(1300)),
        ]
        let cells = UptimeCells.recent(count: 1, span: 3600, events: events, currentState: .online, firstSeen: noon.addingTimeInterval(-86_400), now: noon)
        let cell = try #require(cells.first)
        #expect(cell.outages == 2)
        #expect(cell.offlineSeconds == 400)
        #expect(cell.state == .offline)
        #expect(cell.availability == 3200.0 / 3600.0)
    }

    @Test func dayCellsAlignToTheCalendar() throws {
        let calendar = Calendar.current
        let id = UUID()
        let sixDaysAgo = calendar.startOfDay(for: noon).addingTimeInterval(-6 * 86_400 + 3 * 3600)
        let events = [event(id, .offline, at: sixDaysAgo), event(id, .online, at: sixDaysAgo.addingTimeInterval(720))]
        let cells = UptimeCells.days(count: 30, events: events, currentState: .online, firstSeen: noon.addingTimeInterval(-365 * 86_400), now: noon)
        #expect(cells.count == 30)
        #expect(cells.allSatisfy { calendar.startOfDay(for: $0.interval.start) == $0.interval.start })
        #expect(cells.last?.interval.start == calendar.startOfDay(for: noon))
        let incident = try #require(cells.first { $0.outages > 0 })
        #expect(incident.offlineSeconds == 720)
        #expect(incident.state == .unstable)
        #expect(cells.filter { $0.state != .online }.count == 1)
    }

    @Test func routerIncidentMarksOneNetworkCell() {
        let router = device("Router", isGateway: true)
        let others = [device("NAS"), device("TV")]
        let start = noon.addingTimeInterval(-86_400 + 10 * 1800 + 300)
        let events = [event(router.id, .offline, at: start), event(router.id, .online, at: start.addingTimeInterval(240))]
        let cells = UptimeCells.network(count: 48, span: 86_400, events: events, devices: [router] + others, gatewayID: router.id, now: noon)
        #expect(cells.count == 48)
        #expect(cells.indices.filter { cells[$0].state == .offline } == [10])
        #expect(cells[10].offlineSeconds == 240)
    }

    @Test func massDropMarksNetworkCellsWithoutARouter() {
        let devices = (0..<5).map { device("Device \($0)") }
        let start = noon.addingTimeInterval(-86_400 + 20 * 1800 + 100)
        var events: [StatusEventSnapshot] = []
        for (index, member) in devices.prefix(3).enumerated() {
            events.append(event(member.id, .offline, at: start.addingTimeInterval(Double(index) * 10)))
            events.append(event(member.id, .online, at: start.addingTimeInterval(600 + Double(index) * 10)))
        }
        let cells = UptimeCells.network(count: 48, span: 86_400, events: events, devices: devices, gatewayID: nil, now: noon)
        #expect(cells.indices.filter { cells[$0].state == .offline } == [20])
        #expect(cells.filter { $0.state == .noData }.isEmpty)
    }

    @Test func networkCellsBeforeTheFirstDeviceHaveNoData() {
        let devices = [device("NAS", firstSeen: noon.addingTimeInterval(-3600))]
        let cells = UptimeCells.network(count: 24, span: 86_400, events: [], devices: devices, gatewayID: nil, now: noon)
        #expect(cells.prefix(23).allSatisfy { $0.state == .noData })
        #expect(cells.last?.state == .online)
    }

    @Test func headlines() {
        let day = UptimeCells.recent(count: 24, span: 86_400, events: [], currentState: .online, firstSeen: noon.addingTimeInterval(-86_400 * 2), now: noon)
        #expect(UptimeCells.headline(day, days: 1) == "Up all day")

        let id = UUID()
        let drop = noon.addingTimeInterval(-5 * 3600)
        let down = UptimeCells.recent(
            count: 24, span: 86_400,
            events: [event(id, .offline, at: drop), event(id, .online, at: drop.addingTimeInterval(240))],
            currentState: .online, firstSeen: noon.addingTimeInterval(-86_400 * 2), now: noon
        )
        #expect(UptimeCells.headline(down, days: 1) == "Down 4 min today")

        // Typed parts, so the type checker does not time out on one large expression.
        let month = (0..<30).map { index -> UptimeCell in
            let start: Date = noon.addingTimeInterval(Double(index - 30) * 86_400)
            let isIncident: Bool = index == 20
            let state: UptimeState = isIncident ? .unstable : .online
            let availability: Double = isIncident ? 0.99 : 1
            let offlineSeconds: TimeInterval = isIncident ? 864 : 0
            let outages: Int = isIncident ? 1 : 0
            return UptimeCell(
                interval: DateInterval(start: start, duration: 86_400),
                state: state,
                availability: availability,
                offlineSeconds: offlineSeconds,
                outages: outages
            )
        }
        #expect(UptimeCells.headline(month, days: 30) == "Up 99.9% · 1 outage in 30 days")
        let calm = month.map { UptimeCell(interval: $0.interval, state: .online, availability: 1, offlineSeconds: 0, outages: 0) }
        #expect(UptimeCells.headline(calm, days: 30) == "Up 100% · no outages in 30 days")
    }
}

@Suite("Presence grid")
struct PresenceGridTests {
    private let hours = PresenceGrid.hourStarts(hours: 24, now: noon.addingTimeInterval(1500))

    @Test func hourStartsAlignToTheClock() {
        #expect(hours.count == 24)
        #expect(hours.last == noon)
        #expect(hours.first == noon.addingTimeInterval(-23 * 3600))
    }

    @Test func sharesStartAtFirstSeen() throws {
        let now = noon.addingTimeInterval(1500)
        let laptop = device("Laptop", firstSeen: noon.addingTimeInterval(-2 * 3600))
        let rows = PresenceGrid.rows(devices: [laptop], events: [], hourStarts: hours, now: now)
        let row = try #require(rows.first)
        #expect(row.shares.prefix(21).allSatisfy { $0 == nil })
        #expect(row.shares.suffix(3).allSatisfy { $0 == 1 })
    }

    @Test func halfAnHourOnlineIsHalf() throws {
        let now = noon.addingTimeInterval(1500)
        let phone = device("Phone")
        let hour = hours[20]
        let events = [event(phone.id, .offline, at: hour.addingTimeInterval(1800)), event(phone.id, .online, at: hours[21])]
        let rows = PresenceGrid.rows(devices: [phone], events: events, hourStarts: hours, now: now)
        let row = try #require(rows.first)
        #expect(row.shares[20] == 0.5)
        #expect(row.shares[21] == 1)
        #expect(PresenceGrid.online(rows: rows, column: 20) == 1)
    }

    @Test func varyingRowsComeFirst() {
        let now = noon.addingTimeInterval(1500)
        let router = device("Router", kind: .router)
        let phone = device("Phone", kind: .phone)
        let events = [event(phone.id, .offline, at: hours[10]), event(phone.id, .online, at: hours[15])]
        let rows = PresenceGrid.rows(devices: [router, phone], events: events, hourStarts: hours, now: now)
        #expect(rows.map(\.deviceID) == [phone.id, router.id])
        #expect(PresenceGrid.online(rows: rows, column: 12) == 1)
    }

    @Test func headlineNamesTheBusiestAndQuietestWindows() {
        let shares = (0..<24).map { column -> Double? in (5...7).contains(column) ? 1 : 0 }
        let rows = [PresenceRow(deviceID: UUID(), name: "Phone", kind: .phone, shares: shares)]
        let expected = "Busiest \(hours[5].formatted(.dateTime.hour())) – \(hours[8].formatted(.dateTime.hour()))"
            + " · quietest \(hours[0].formatted(.dateTime.hour())) – \(hours[3].formatted(.dateTime.hour()))"
        #expect(PresenceGrid.headline(rows: rows, hourStarts: hours) == expected)

        let flat = [PresenceRow(deviceID: UUID(), name: "Router", kind: .router, shares: (0..<24).map { _ -> Double? in 1 })]
        #expect(PresenceGrid.headline(rows: flat, hourStarts: hours) == nil)
    }
}

@Suite("Journal")
struct JournalTests {
    private let since = noon.addingTimeInterval(-12 * 3600)

    private func entry(_ kind: TimelineEntry.Kind, _ deviceID: UUID?, _ title: String, at offset: TimeInterval) -> TimelineEntry {
        TimelineEntry(id: UUID().uuidString, date: since.addingTimeInterval(offset), kind: kind, deviceID: deviceID, title: title, subtitle: nil)
    }

    @Test func ranksAndLimits() {
        let plug = device("esp_3a7f21", host: "192.168.178.117")
        let sonos = device("Sonos One")
        let printer = device("Office Printer")
        let console = device("PlayStation 5")
        let old = device("Camera")
        let devices = Dictionary(uniqueKeysWithValues: [plug, sonos, printer, console, old].map { ($0.id, $0) })
        let entries = [
            entry(.left, old.id, "Camera", at: -100),
            entry(.newDevice, plug.id, "esp_3a7f21", at: 100),
            entry(.outageStarted, nil, "Network outage", at: 200),
            entry(.outageEnded, nil, "Network restored", at: 440),
            entry(.left, sonos.id, "Sonos One", at: 300),
            entry(.returned, sonos.id, "Sonos One", at: 320),
            entry(.left, sonos.id, "Sonos One", at: 500),
            entry(.left, printer.id, "Office Printer", at: 600),
            entry(.returned, console.id, "PlayStation 5", at: 700),
        ]

        let all = Journal.lines(entries: entries, devices: devices, since: since, limit: 10)
        #expect(all.map(\.kind) == [.newDevice, .outage, .repeatedDrops, .wentOffline, .recovered])
        #expect(all[0].text == "esp_3a7f21 joined · 192.168.178.117")
        #expect(all[1].text.hasSuffix("· 4 min"))
        #expect(all[2].text == "Sonos One dropped out 2 times")
        #expect(all[3].text.hasPrefix("Office Printer went offline at "))
        #expect(all[4].text == "PlayStation 5 is back")
        #expect(all.contains { $0.deviceID == old.id } == false)

        #expect(Journal.lines(entries: entries, devices: devices, since: since).map(\.kind) == [.newDevice, .outage, .repeatedDrops])
    }

    @Test func aDeviceThatCameBackIsRecovered() {
        let sonos = device("Sonos One")
        let entries = [entry(.left, sonos.id, "Sonos One", at: 100), entry(.returned, sonos.id, "Sonos One", at: 460)]
        let lines = Journal.lines(entries: entries, devices: [sonos.id: sonos], since: since)
        #expect(lines.map(\.kind) == [.recovered])
        #expect(lines.first?.deviceID == sonos.id)
    }
}

@Suite("Scan narrative")
struct ScanNarrativeTests {
    private func phases(_ progress: ScanProgress?, isScanning: Bool, isFinished: Bool) -> [ScanStage.Phase] {
        ScanStage.stages(progress: progress, isScanning: isScanning, isFinished: isFinished, measured: 3, identified: 2).map(\.phase)
    }

    @Test func stagesFollowTheScan() {
        #expect(phases(nil, isScanning: false, isFinished: false) == [.waiting, .waiting, .waiting, .waiting])
        #expect(phases(ScanProgress(scanned: 100, total: 254, found: 0), isScanning: true, isFinished: false) == [.running, .waiting, .waiting, .waiting])
        #expect(phases(ScanProgress(scanned: 100, total: 254, found: 5), isScanning: true, isFinished: false) == [.running, .running, .running, .waiting])
        #expect(phases(ScanProgress(scanned: 254, total: 254, found: 5), isScanning: true, isFinished: false) == [.done, .running, .running, .running])
        #expect(phases(ScanProgress(scanned: 254, total: 254, found: 5), isScanning: false, isFinished: true) == [.done, .done, .done, .done])

        let stages = ScanStage.stages(progress: ScanProgress(scanned: 100, total: 254, found: 5), isScanning: true, isFinished: false, measured: 3, identified: 2)
        #expect(stages.map(\.step) == ScanStage.Step.allCases)
        #expect(stages.map(\.count) == [100, 3, 2, nil])
        #expect(stages.map(\.title) == ["Sweep addresses", "Measure response", "Identify devices", "Compare with last scan"])
    }

    private func host(_ address: String, latency: Double? = nil) -> DiscoveredHost {
        let probe = latency.map {
            ProbeResult(host: address, port: 80, kind: .tcp, outcome: .reachable(latencyMilliseconds: $0), timestamp: noon)
        }
        return DiscoveredHost(host: address, probe: probe)
    }

    @Test func summaryLeadsWithTheCount() {
        let known = [
            device("Router", host: "10.0.0.1", networkKey: "home"),
            device("NAS", host: "10.0.0.9", networkKey: "home"),
            device("Plug", host: "10.0.0.10", firstSeen: noon.addingTimeInterval(-3600), networkKey: "home"),
            device("Printer", host: "10.0.0.20", networkKey: "home"),
            device("Console", host: "10.0.0.21", networkKey: "home"),
            device("Manual", host: "10.0.0.30", isUserAdded: true, networkKey: "home"),
            device("Elsewhere", host: "10.0.0.40", networkKey: "office"),
        ]
        let found = [host("10.0.0.1", latency: 2.0), host("10.0.0.9", latency: 1.1), host("10.0.0.10")]
        #expect(ScanSummary.text(found: found, known: known, networkKey: "home", now: noon) == "3 found · 1 new · 2 not answering · fastest 1.1 ms")

        let calm = Array(known.prefix(2))
        #expect(ScanSummary.text(found: Array(found.prefix(2)), known: calm, networkKey: "home", now: noon) == "2 found · fastest 1.1 ms")
    }

    @Test func newHostsFirstThenNumericOrder() {
        let plug = device("Plug", host: "10.0.0.20", firstSeen: noon.addingTimeInterval(-3600))
        let manual = device("Manual", host: "10.0.0.3", firstSeen: noon.addingTimeInterval(-3600), isUserAdded: true)
        let found = [host("10.0.0.10"), host("10.0.0.9"), host("10.0.0.3"), host("10.0.0.20")]
        let ordered = ScanSummary.ordered(found: found, known: [plug.host: plug, manual.host: manual], now: noon)
        #expect(ordered.map(\.host) == ["10.0.0.20", "10.0.0.3", "10.0.0.9", "10.0.0.10"])
        #expect(ScanSummary.isNew(plug, now: noon))
        #expect(ScanSummary.isNew(manual, now: noon) == false)
        #expect(ScanSummary.isNew(nil, now: noon) == false)
    }
}
