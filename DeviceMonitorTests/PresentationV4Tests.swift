import Foundation
import Testing
@testable import DeviceMonitor

/// Noon on a fixed day, so "today", "2 hours ago" and the demo counts do not depend on when the tests run.
private let fixedNow = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)).addingTimeInterval(12 * 3600)

/// A steady device: 1.8 and 2.1 ms in turn, so the jitter is 0.3 ms and 1.8 ms reads as fast.
private let steady: [Double] = [1.8, 2.1, 1.8, 2.1, 1.8]

private func makeDevice(
    _ name: String,
    host: String = "192.168.1.10",
    vendor: String? = nil,
    kind: DeviceKind = .unknown,
    state: ReachabilityState = .online,
    latency: Double? = nil,
    firstSeen: Date = fixedNow.addingTimeInterval(-30 * 86_400),
    lastSeen: Date? = nil,
    isUserAdded: Bool = false,
    isFavorite: Bool = false,
    isTrusted: Bool = true,
    isGateway: Bool = false,
    hostname: String? = nil,
    mac: String? = nil
) -> DeviceSnapshot {
    DeviceSnapshot(
        id: UUID(),
        name: name,
        hostname: hostname,
        host: host,
        macAddress: mac,
        vendor: vendor,
        kind: kind,
        state: state,
        latencyMilliseconds: latency,
        firstSeen: firstSeen,
        lastSeen: lastSeen,
        isUserAdded: isUserAdded,
        isFavorite: isFavorite,
        isTrusted: isTrusted,
        isGateway: isGateway
    )
}

/// `values` 30 s apart, the last one at `end`.
private func samples(_ values: [Double], endingAt end: Date = fixedNow) -> [LatencySampleSnapshot] {
    let deviceID = UUID()
    return values.enumerated().map { index, value in
        LatencySampleSnapshot(
            id: UUID(),
            deviceID: deviceID,
            timestamp: end.addingTimeInterval(-30 * Double(values.count - 1 - index)),
            milliseconds: value,
            probeKind: .tcp
        )
    }
}

@Suite("Latency series")
struct LatencySeriesTests {
    @Test func hourKeepsEverySample() {
        let input = samples((0..<100).map { 2 + Double($0 % 3) * 0.1 })
        let series = LatencySeries.make(samples: input, window: .hour, now: fixedNow, gapSeconds: 120)
        #expect(series.latency.points.map(\.value) == input.map { Optional($0.milliseconds) })
        #expect(series.jitter.points.count == input.count)
        #expect(series.jitter.points[0].value == nil)
        #expect(series.domain == fixedNow.addingTimeInterval(-3600)...fixedNow)
        #expect(series.latency.fillsArea)
        #expect(!series.jitter.fillsArea)
        #expect(series.latency.tone == .latency)
        #expect(series.jitter.tone == .jitter)
    }

    @Test func gapInsertsOneNilPointInBothSeries() {
        let before = samples(Array(repeating: 2.0, count: 40), endingAt: fixedNow.addingTimeInterval(-1800))
        let after = samples(Array(repeating: 2.0, count: 41))
        let series = LatencySeries.make(samples: before + after, window: .hour, now: fixedNow, gapSeconds: 120)
        let gaps = series.latency.points.indices.filter { series.latency.points[$0].value == nil }
        #expect(gaps == [40])
        #expect(series.latency.points.count == 82)
        #expect(series.jitter.points.count == 82)
        #expect(series.jitter.points[40].value == nil)
        // The jitter window restarts after the gap: nil at the run's first sample, then measured again.
        #expect(series.jitter.points[41].value == nil)
        #expect(series.jitter.points[42].value == 0)
    }

    @Test func oneSpikeDrawsOneJitterBump() {
        let height = 3.0
        var values = Array(repeating: 2.0, count: 21)
        values[10] += height
        let series = LatencySeries.make(samples: samples(values), window: .hour, now: fixedNow, gapSeconds: 120)
        let jitter = series.jitter.points.map(\.value)
        let raised = jitter.indices.filter { (jitter[$0] ?? 0) > 1e-12 }
        #expect(raised == Array(10...15))
        let peak = jitter.compactMap { $0 }.max() ?? 0
        #expect(abs(peak - 2 * height / 5) < 1e-9)
    }

    @Test func sixHoursBucketsByNearestRankMedian() {
        // Every 30 s, 15 s off the bucket edges: four samples per 2-minute bucket, valued 1, 2, 3 and 4.
        let lower = fixedNow.addingTimeInterval(-21_600)
        let input = (0..<720).map { index in
            LatencySampleSnapshot(
                id: UUID(),
                deviceID: UUID(),
                timestamp: lower.addingTimeInterval(15 + 30 * Double(index)),
                milliseconds: Double(index % 4 + 1),
                probeKind: .tcp
            )
        }
        let series = LatencySeries.make(samples: input, window: .sixHours, now: fixedNow, gapSeconds: 120)
        #expect(series.latency.points.count == 180)
        #expect(series.latency.points.allSatisfy { $0.value == 2 })
        #expect(series.jitter.points.allSatisfy { $0.value == 1 })
        #expect(series.latency.points.first?.date == lower.addingTimeInterval(60))
    }

    @Test func samplesOutsideTheWindowAreIgnored() {
        let early = LatencySampleSnapshot(id: UUID(), deviceID: UUID(), timestamp: fixedNow.addingTimeInterval(-3_700), milliseconds: 50, probeKind: .tcp)
        let late = LatencySampleSnapshot(id: UUID(), deviceID: UUID(), timestamp: fixedNow.addingTimeInterval(10), milliseconds: 50, probeKind: .tcp)
        let series = LatencySeries.make(samples: [early] + samples([2, 2, 2]) + [late], window: .hour, now: fixedNow, gapSeconds: 120)
        #expect(series.latency.points.compactMap(\.value) == [2, 2, 2])
        #expect(series.summary?.maximum == 2)
        #expect(series.worst?.milliseconds == 2)
    }

    @Test func thirtyMinutesCoverHalfAnHour() {
        let series = LatencySeries.make(samples: samples(Array(repeating: 2.0, count: 61)), window: .hour, now: fixedNow, gapSeconds: 120)
        #expect(abs(series.coveredSeconds - 1_800) <= 60)
    }

    @Test func emptyInput() {
        let series = LatencySeries.make(samples: [], window: .hour, now: fixedNow, gapSeconds: 120)
        #expect(series.summary == nil)
        #expect(series.latency.points.allSatisfy { $0.value == nil })
        #expect(series.jitter.points.allSatisfy { $0.value == nil })
        #expect(series.upperBound == 5)
        #expect(series.coveredSeconds == 0)
        #expect(series.spikeCount == 0)

        let day = LatencySeries.make(samples: [], window: .day, now: fixedNow, gapSeconds: 120)
        #expect(day.latency.points.isEmpty)
        #expect(day.jitter.points.isEmpty)
    }

    @Test func slowChecksKeepTheBucketedLineWholeAndGapsStillBreakIt() {
        // One check every 5 minutes: most 2-minute buckets stay empty, but no two samples are a gap apart.
        let lower = fixedNow.addingTimeInterval(-21_600)
        func sample(at offset: TimeInterval) -> LatencySampleSnapshot {
            LatencySampleSnapshot(id: UUID(), deviceID: UUID(), timestamp: lower.addingTimeInterval(offset), milliseconds: 2, probeKind: .tcp)
        }
        let offsets = (0..<72).map { 150 + 300 * Double($0) }
        let whole = LatencySeries.make(samples: offsets.map { sample(at: $0) }, window: .sixHours, now: fixedNow, gapSeconds: 900)
        #expect(whole.latency.points.count == 72)
        #expect(whole.latency.points.allSatisfy { $0.value == 2 })

        let withHole = offsets.filter { $0 < 7_200 || $0 > 10_800 }
        let broken = LatencySeries.make(samples: withHole.map { sample(at: $0) }, window: .sixHours, now: fixedNow, gapSeconds: 900)
        #expect(broken.latency.points.count == withHole.count + 1)
        #expect(broken.latency.points.filter { $0.value == nil }.count == 1)
    }

    @Test func slowChecksStillCoverTheHour() {
        // One check every 2 minutes for the whole hour: half the minutes hold no sample, but none is a gap.
        let input = (0..<30).map { index in
            LatencySampleSnapshot(id: UUID(), deviceID: UUID(), timestamp: fixedNow.addingTimeInterval(-3_590 + 120 * Double(index)), milliseconds: 2, probeKind: .tcp)
        }
        let series = LatencySeries.make(samples: input, window: .hour, now: fixedNow, gapSeconds: 360)
        #expect(series.coveredSeconds >= 3_480)
    }
}

@Suite("Chart axis")
struct ChartAxisTests {
    @Test func niceUpperBound() {
        #expect(ChartAxis.niceUpperBound(0) == 5)
        #expect(ChartAxis.niceUpperBound(4.2) == 5)
        #expect(ChartAxis.niceUpperBound(6) == 10)
        #expect(ChartAxis.niceUpperBound(23) == 50)
        #expect(ChartAxis.niceUpperBound(180) == 500)
    }

    @Test func ticks() {
        #expect(ChartAxis.ticks(upperBound: 10) == [0, 5, 10])
    }

    @Test func labelsSpanTheDomainAndEndWithNow() {
        let domain = fixedNow.addingTimeInterval(-3600)...fixedNow
        let labels = ChartAxis.labels(domain: domain, count: 5, style: .clock)
        #expect(labels.count == 5)
        #expect(labels.map(\.id) == [0, 1, 2, 3, 4])
        #expect(labels.first?.date == domain.lowerBound)
        #expect(labels.last?.date == domain.upperBound)
        #expect(labels.last?.text == "Now")
    }
}

@Suite("Quality scales")
struct QualityScaleTests {
    @Test func positions() {
        let latency = QualityScale.latency
        #expect(latency.position(of: 1) == 0)
        #expect(latency.position(of: 300) == 1)
        #expect(abs(latency.position(of: 10) - 0.4037) < 0.0001)
        #expect(latency.position(of: 0.5) == 0)
        #expect(latency.position(of: 1_000) == 1)
        #expect(QualityScale.securityScore.position(of: 60) == 0.6)
    }

    @Test func stopsAscendAroundTheGradeBoundaries() {
        let latency = QualityScale.latency
        #expect(latency.stops.map(\.location) == [0, 0.56, 0.64, 0.77, 0.85, 1])
        for scale in [QualityScale.latency, .securityScore] {
            #expect(zip(scale.stops, scale.stops.dropFirst()).allSatisfy { $0.location <= $1.location })
        }
        let thirty = latency.segment(at: latency.position(of: 30))
        #expect(thirty.lower.tone == .good && thirty.upper.tone == .warn)
        let hundred = latency.segment(at: latency.position(of: 100))
        #expect(hundred.lower.tone == .warn && hundred.upper.tone == .bad)
    }

    @Test func segments() {
        let latency = QualityScale.latency
        let transition = latency.segment(at: 0.60)
        #expect(transition.lower.tone == .good && transition.upper.tone == .warn)
        #expect(abs(transition.fraction - 0.5) < 1e-9)
        let good = latency.segment(at: 0.3)
        #expect(good.lower.tone == .good && good.upper.tone == .good)
        let beyond = latency.segment(at: 1.2)
        #expect(beyond.lower.tone == .bad && beyond.upper.tone == .bad)
        #expect(beyond.fraction == 0)
    }

    @Test func gradesAndQualityTones() {
        #expect(LatencyGrade.grade(milliseconds: 29.9) == .good)
        #expect(LatencyGrade.grade(milliseconds: 30) == .fair)
        #expect(LatencyGrade.grade(milliseconds: 99.9) == .fair)
        #expect(LatencyGrade.grade(milliseconds: 100) == .poor)
        #expect(LatencyQuality.fast.tone == .good)
        #expect(LatencyQuality.normal.tone == .good)
        #expect(LatencyQuality.slower.tone == .warn)
        #expect(LatencyQuality.slow.tone == .bad)
    }
}

@Suite("Device row facts")
struct DeviceRowFactsTests {
    @Test func fastOnlineDevice() {
        let nas = makeDevice("DiskStation", host: "192.168.1.2", vendor: "Synology", kind: .nas, latency: 1.8)
        let facts = DeviceRowFacts.make(device: nas, samples: steady, now: fixedNow, isNewcomer: false)
        #expect(facts.subtitle == ["192.168.1.2", "Synology"])
        #expect(facts.subtitleFallbacks == [["192.168.1.2"]])
        #expect(facts.primary == "1.8 ms")
        #expect(facts.primaryTone == .good)
        #expect(facts.secondary == "0.3 ms jitter")
        #expect(facts.accessibilityLabel == "DiskStation, Storage, Online")
        #expect(facts.accessibilityValue == "192.168.1.2, latency 1.8 ms, jitter 0.3 ms")

        let oneSample = DeviceRowFacts.make(device: nas, samples: [1.8], now: fixedNow, isNewcomer: false)
        #expect(oneSample.secondary == nil)
    }

    @Test func slowerThanUsualWarnsAndSlowIsBad() {
        let slower = makeDevice("TV", latency: 8)
        #expect(DeviceRowFacts.make(device: slower, samples: steady, now: fixedNow, isNewcomer: false).primaryTone == .warn)
        let slow = makeDevice("TV", latency: 120)
        #expect(DeviceRowFacts.make(device: slow, samples: steady, now: fixedNow, isNewcomer: false).primaryTone == .bad)
    }

    @Test func unstableDevice() {
        let speaker = makeDevice("Speaker", host: "192.168.1.61", vendor: "Sonos", state: .degraded, latency: 1.8)
        let facts = DeviceRowFacts.make(device: speaker, samples: steady, now: fixedNow, isNewcomer: false)
        #expect(facts.primaryTone == .warn)
        #expect(facts.subtitle == ["192.168.1.61", "Sonos", "Unstable"])
        #expect(facts.subtitleFallbacks == [["192.168.1.61", "Sonos"], ["192.168.1.61"]])
    }

    @Test func offlineDevice() {
        let lastSeen = fixedNow.addingTimeInterval(-2 * 3600)
        let printer = makeDevice("Printer", host: "192.168.1.52", kind: .printer, state: .offline, lastSeen: lastSeen)
        let facts = DeviceRowFacts.make(device: printer, samples: [], now: fixedNow, isNewcomer: false)
        #expect(facts.primary == "Offline")
        #expect(facts.primaryTone == .bad)
        #expect(facts.secondary == "2 hours ago")
        #expect(facts.subtitle == ["192.168.1.52", "Printer"])
        #expect(facts.subtitleFallbacks == [["192.168.1.52"]])
        #expect(facts.accessibilityValue == "192.168.1.52, last seen 2 hours ago")
    }

    /// The trailing column already says when an offline device was last seen.
    @Test func offlineSubtitleHasNoSinceSegment() {
        for hoursAgo in [2.0, 26, 120] {
            let lastSeen = fixedNow.addingTimeInterval(-hoursAgo * 3600)
            let console = makeDevice("Console", vendor: "Sony", state: .offline, lastSeen: lastSeen)
            let facts = DeviceRowFacts.make(device: console, samples: [], now: fixedNow, isNewcomer: false)
            #expect(facts.subtitle == ["192.168.1.10", "Sony"])
            for segments in [facts.subtitle] + facts.subtitleFallbacks {
                #expect(!segments.contains { $0.hasPrefix("Since") })
            }
            #expect(facts.secondary == Formatters.relative(lastSeen, now: fixedNow))
        }
    }

    @Test func checkingDevice() {
        let facts = DeviceRowFacts.make(device: makeDevice("Plug", state: .unknown), samples: [], now: fixedNow, isNewcomer: false)
        #expect(facts.primary == "Checking")
        #expect(facts.primaryTone == .neutral)
        #expect(facts.secondary == nil)
    }

    @Test func newcomerHasNoMetricsAndSaysWhenItJoined() {
        let esp = makeDevice("esp_3a7f21", host: "192.168.1.117", vendor: "Espressif", kind: .iot, latency: 11, firstSeen: fixedNow.addingTimeInterval(-3_700), isTrusted: false)
        let facts = DeviceRowFacts.make(device: esp, samples: [11, 12], now: fixedNow, isNewcomer: true)
        #expect(facts.primary == nil)
        #expect(facts.secondary == nil)
        #expect(facts.subtitle == ["192.168.1.117", "Espressif", "Joined 1 hour ago"])
        #expect(facts.subtitleFallbacks == [["192.168.1.117", "Joined 1 hour ago"], ["192.168.1.117"]])
        #expect(facts.accessibilityLabel == "esp_3a7f21, Smart Device, Online, New device")
    }

    @Test func vendorEqualToTheNameIsLeftOut() {
        let hue = makeDevice("Philips Hue", vendor: "Philips Hue", kind: .hub, latency: 3)
        let facts = DeviceRowFacts.make(device: hue, samples: [], now: fixedNow, isNewcomer: false)
        #expect(facts.subtitle == ["192.168.1.10", "Hub"])
        #expect(facts.subtitleFallbacks == [["192.168.1.10"]])
    }

    @Test func arrivalsNewcomersAndModelLine() {
        let stranger = makeDevice("esp", firstSeen: fixedNow.addingTimeInterval(-600), isTrusted: false)
        #expect(stranger.isRecentArrival(now: fixedNow))
        #expect(stranger.isNewcomer(now: fixedNow))
        let trusted = makeDevice("Phone", firstSeen: fixedNow.addingTimeInterval(-600))
        #expect(trusted.isRecentArrival(now: fixedNow))
        #expect(!trusted.isNewcomer(now: fixedNow))
        let added = makeDevice("NAS", firstSeen: fixedNow.addingTimeInterval(-600), isUserAdded: true, isTrusted: false)
        #expect(!added.isRecentArrival(now: fixedNow))
        #expect(!makeDevice("TV", isTrusted: false).isRecentArrival(now: fixedNow))
        #expect(makeDevice("DiskStation", vendor: "Synology", kind: .nas).modelLine == "Synology · Storage")
        #expect(makeDevice("Router", kind: .router).modelLine == "Router")
    }
}

@Suite("Device info grid")
struct DeviceInfoGridTests {
    @Test func fourRowsOfSelfDescribingValues() {
        let nas = makeDevice("DiskStation", host: "192.168.1.2", latency: 1.8, hostname: "diskstation.local", mac: "00:11:32:AB:CD:EF")
        let rows = DeviceInfoGrid.rows(device: nas, samples: steady, outagesSeen: 0, openPortCount: 4, now: fixedNow)
        #expect(rows.count == 4)
        #expect(rows[0].leading.text == "192.168.1.2")
        #expect(rows[0].leading.isCopyable)
        #expect(rows[0].trailing?.text == "00:11:32:AB:CD:EF")
        #expect(rows[1].leading.text == "1.8 ms")
        #expect(rows[1].leading.emphasis == .primary)
        #expect(rows[1].trailing?.text == "diskstation.local")
        #expect(rows[2].trailing?.text == "No outages seen · 30D")
        #expect(rows[2].trailing?.emphasis == .secondary)
        #expect(rows[3].leading.text == "4 open ports")
        #expect(rows[3].trailing?.text == "Trusted")
    }

    @Test func idleAndExceptionalValues() {
        let stranger = makeDevice("esp", latency: 8, isTrusted: false)
        let rows = DeviceInfoGrid.rows(device: stranger, samples: steady, outagesSeen: nil, openPortCount: nil, now: fixedNow)
        #expect(rows.count == 4)
        #expect(rows[0].trailing?.text == "MAC unknown")
        #expect(rows[0].trailing?.emphasis == .tertiary)
        #expect(rows[1].leading.emphasis == .tone(.warn))
        #expect(rows[1].trailing == nil)
        #expect(rows[2].trailing?.text == "No history yet")
        #expect(rows[2].trailing?.emphasis == .tertiary)
        #expect(rows[3].leading.text == "Ports not checked")
        #expect(rows[3].leading.emphasis == .tertiary)
        #expect(rows[3].trailing?.text == "Stranger")
        #expect(rows[3].trailing?.emphasis == .tone(.warn))

        let once = DeviceInfoGrid.rows(device: stranger, samples: steady, outagesSeen: 1, openPortCount: 0, now: fixedNow)
        #expect(once[2].trailing?.text == "1 outage seen · 30D")
        #expect(once[2].trailing?.emphasis == .tone(.warn))

        let offline = DeviceInfoGrid.rows(device: makeDevice("Printer", state: .offline), samples: [], outagesSeen: 3, openPortCount: 2, now: fixedNow)
        #expect(offline[1].leading.text == "Offline")
        #expect(offline[1].leading.emphasis == .tone(.bad))

        let texts = (rows + once + offline).flatMap { [$0.leading.text, $0.trailing?.text ?? ""] }
        #expect(!texts.contains { $0.contains("%") })
    }
}

@Suite("Overview narrative")
struct OverviewNarrativeTests {
    @Test func countersMatchTheDemoNetwork() {
        let counters = NetworkCounters.make(devices: DemoFixtures.devices(now: fixedNow), now: fixedNow)
        #expect(counters == NetworkCounters(online: 12, offline: 2, recentArrivals: 1, strangers: 1))
        #expect(NetworkCounters.zero == NetworkCounters(online: 0, offline: 0, recentArrivals: 0, strangers: 0))
    }

    @Test func attentionListsOfflineThenUnstableWithoutNewcomers() {
        let printer = makeDevice("Printer", state: .offline, lastSeen: fixedNow.addingTimeInterval(-6 * 3600))
        let console = makeDevice("Console", state: .offline, lastSeen: fixedNow.addingTimeInterval(-3600))
        let speaker = makeDevice("Speaker", state: .degraded)
        let bulb = makeDevice("Bulb", state: .degraded)
        let newcomer = makeDevice("esp", state: .offline, firstSeen: fixedNow.addingTimeInterval(-600), lastSeen: fixedNow.addingTimeInterval(-60), isTrusted: false)
        let result = OverviewAttention.devices([makeDevice("NAS"), printer, speaker, newcomer, bulb, console], now: fixedNow)
        #expect(result.map(\.name) == ["Console", "Printer", "Bulb", "Speaker"])
    }

    @Test func responseTimeMedian() {
        let devices = [makeDevice("A", latency: 5), makeDevice("B", latency: 1), makeDevice("C", latency: 3), makeDevice("D", state: .offline, latency: 0.5)]
        #expect(ResponseTime.latencies(devices) == [1, 3, 5])
        #expect(ResponseTime.median(devices) == 3)
        #expect(ResponseTime.median([makeDevice("E", state: .offline)]) == nil)
    }

    @Test func availabilityInWordsWithoutPercentages() {
        let start = fixedNow.addingTimeInterval(-3600)
        func cell(_ state: UptimeState, outages: Int = 0, down: TimeInterval = 0) -> UptimeCell {
            UptimeCell(interval: DateInterval(start: start, duration: 1800), state: state, availability: state == .noData ? nil : 1, offlineSeconds: down, outages: outages)
        }
        let clean = [cell(.online), cell(.online)]
        let one = [cell(.online), cell(.offline, outages: 1, down: 240)]
        let two = [cell(.offline, outages: 1, down: 300), cell(.unstable, outages: 1, down: 60)]

        #expect(AvailabilityNarrative.statusWord(cells: clean, isGatewayDown: false) == DSStatusWord("No outages seen", tone: .good))
        #expect(AvailabilityNarrative.statusWord(cells: one, isGatewayDown: false) == DSStatusWord("1 outage seen", tone: .warn))
        #expect(AvailabilityNarrative.statusWord(cells: two, isGatewayDown: false) == DSStatusWord("2 outages seen", tone: .warn))
        #expect(AvailabilityNarrative.statusWord(cells: one, isGatewayDown: true) == DSStatusWord("Router down", tone: .bad))
        #expect(AvailabilityNarrative.statusWord(cells: [cell(.noData)], isGatewayDown: false).tone == .neutral)

        let summary = AvailabilityNarrative.summary(cells: one)
        #expect(summary.items.map(\.label) == ["Outages"])
        #expect(summary.items.first?.value == "1")
        #expect(summary.items.first?.tone == nil)
        #expect(summary.trailing?.label == "Down")
        #expect(summary.trailing?.value == "4 min")
        #expect(summary.trailing?.tone == .bad)
        #expect(AvailabilityNarrative.summary(cells: clean).trailing?.tone == nil)

        let words = (summary.items + [summary.trailing].compactMap { $0 }).flatMap { [$0.label, $0.value, $0.spokenValue] }
        #expect(!words.contains { $0.contains("%") })
        #expect(AvailabilityNarrative.spokenSummary(cells: one) == "1 outage seen, 4 minutes down")
        #expect(AvailabilityNarrative.spokenSummary(cells: clean) == "No outages seen")
        #expect(AvailabilityNarrative.seenWhileOpenCaption == "Changes seen while DeviceMonitor was open")
    }

    @Test func connectionLogNewestFirstWithTheHost() {
        let deviceID = UUID()
        let events = [
            StatusEventSnapshot(id: UUID(), deviceID: deviceID, timestamp: fixedNow.addingTimeInterval(-7200), state: .offline),
            StatusEventSnapshot(id: UUID(), deviceID: deviceID, timestamp: fixedNow.addingTimeInterval(-3600), state: .online),
            StatusEventSnapshot(id: UUID(), deviceID: deviceID, timestamp: fixedNow.addingTimeInterval(-1800), state: .degraded),
        ]
        let entries = ConnectionLog.entries(events: events, host: "192.168.1.52", now: fixedNow)
        #expect(entries.map(\.title) == ["Became unstable", "Came online", "Went offline"])
        #expect(entries.allSatisfy { $0.detail.count == 2 && $0.detail[1] == "192.168.1.52" })
        #expect(entries.first?.detail.first?.hasPrefix("Today at ") == true)
    }

    @Test func onlineSeriesHasOnePointPerBucketAtItsMidpoint() {
        let density = ActivityDensity(events: [], devices: [makeDevice("NAS")], range: .day, now: fixedNow)
        let series = ActivitySeries.online(density)
        #expect(series.id == "online")
        #expect(series.tone == .good)
        #expect(series.points.count == density.buckets.count)
        for (point, bucket) in zip(series.points, density.buckets) {
            #expect(point.date == bucket.start.addingTimeInterval(bucket.end.timeIntervalSince(bucket.start) / 2))
            #expect(point.value == Double(bucket.online))
        }
        if let first = density.buckets.first, let last = density.buckets.last {
            #expect(ActivitySeries.domain(density) == first.start...last.end)
        }
    }
}
