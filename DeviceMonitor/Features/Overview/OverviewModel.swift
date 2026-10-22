import Foundation
import Observation

/// What Overview shows: the counters, the devices that need attention, the router's last hour of latency, the
/// network's last 24 hours and every answering device's latency. Rebuilt from the directory and the store
/// after every round, history change and device edit.
@Observable
@MainActor
final class OverviewModel {
    /// Rows the attention card shows at most; See All opens the rest in Devices.
    static let attentionLimit = 3

    private(set) var counters = NetworkCounters.zero
    /// Offline devices, most recently seen first, then unstable ones by name: Devices' "Needs attention".
    private(set) var attention: [DeviceSnapshot] = []
    /// The last hour's latency values of each listed attention device that answers, oldest first.
    private(set) var attentionSamples: [UUID: [Double]] = [:]
    /// The same news as one sentence, for VoiceOver: "Office Printer and PlayStation 5 are offline".
    private(set) var attentionSentence = ""
    private(set) var gateway: DeviceSnapshot?
    /// The router's last hour; nil without a router.
    private(set) var routerLatency: LatencySeries?
    /// The router's latest sample against its own usual latency; nil while it does not answer.
    private(set) var routerQuality: LatencyQuality?
    /// The network's last 24 hours in 48 half-hour cells.
    private(set) var availability: [UptimeCell] = []
    /// The latest latency of every answering device, ascending.
    private(set) var latencies: [Double] = []
    private(set) var medianLatency: Double?
    /// The current network's name ("Home"); nil when the network was never recorded.
    private(set) var networkName: String?

    init() {}

    func reload(environment: AppEnvironment, now: Date) {
        let directory = environment.directory
        let devices = directory.devices
        let hourAgo = now.addingTimeInterval(-3600)

        counters = NetworkCounters.make(devices: devices, now: now)
        attention = OverviewAttention.devices(devices, now: now)
        attentionSentence = HeaderStatus.make(devices: devices, isPaused: false, pauseReason: nil, now: now).title
        var samples: [UUID: [Double]] = [:]
        for device in attention.prefix(Self.attentionLimit) where device.state.isUp {
            samples[device.id] = environment.latencySamples(deviceID: device.id, since: hourAgo).map(\.milliseconds)
        }
        attentionSamples = samples

        gateway = directory.gateway
        if let gateway {
            let routerSamples = environment.latencySamples(deviceID: gateway.id, since: hourAgo)
            let gapSeconds = max(3 * environment.settings.monitor.baseIntervalSeconds, 120)
            routerLatency = LatencySeries.make(samples: routerSamples, window: .hour, now: now, gapSeconds: gapSeconds)
            routerQuality = gateway.state.isUp
                ? LatencyQuality.assess(latest: routerSamples.last?.milliseconds, samples: routerSamples.map(\.milliseconds))
                : nil
        } else {
            routerLatency = nil
            routerQuality = nil
        }

        availability = UptimeCells.network(
            count: 48,
            span: 86_400,
            events: environment.recentEvents(since: now.addingTimeInterval(-86_400)),
            devices: devices,
            gatewayID: directory.gatewayID,
            now: now
        )
        latencies = ResponseTime.latencies(devices)
        medianLatency = ResponseTime.median(devices)
        networkName = environment.currentNetworkKey.flatMap { key in
            environment.knownNetworks().first { $0.key == key }?.displayName
        }
    }
}
