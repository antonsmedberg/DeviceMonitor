import Foundation
import Observation
import SwiftUI

/// Loads history for one device and runs on-demand actions.
@Observable
@MainActor
final class DeviceDetailModel {
    let deviceID: UUID
    private(set) var events: [StatusEventSnapshot] = []
    private(set) var latency: [LatencySampleSnapshot] = []
    private(set) var ports: [PortScanResult] = []
    private(set) var isScanningPorts = false
    private(set) var isChecking = false
    private(set) var isWaking = false
    private(set) var isPinging = false
    private(set) var pingSamples: [PingSample] = []
    private(set) var insight: DeviceInsight?
    private(set) var isLoadingInsight = false

    init(deviceID: UUID) {
        self.deviceID = deviceID
    }

    func load(from environment: AppEnvironment, now: Date = Date()) {
        events = environment.statusEvents(deviceID: deviceID, limit: 200)
        latency = environment.latencySamples(deviceID: deviceID, since: now.addingTimeInterval(-24 * 3600))
        if ports.isEmpty, let device = environment.directory.device(id: deviceID) {
            ports = device.openPorts.map { PortScanResult(port: $0, isOpen: true, serviceName: SecurityAssessor.serviceName(port: $0), risk: SecurityAssessor.risk(port: $0, isGateway: device.isGateway)) }
        }
    }

    func ping(environment: AppEnvironment) async {
        guard !isPinging else { return }
        isPinging = true
        pingSamples = []
        pingSamples = await environment.pingBurst(deviceID: deviceID)
        isPinging = false
        let summary = PingSummary(samples: pingSamples)
        if summary.received > 0 {
            environment.haptics.success()
            announce("Ping: \(summary.received) of \(summary.sent) answered, average \(Formatters.latency(summary.average))")
        } else {
            environment.haptics.warning()
            announce("Ping: no answer")
        }
    }

    func checkNow(environment: AppEnvironment) async {
        guard !isChecking else { return }
        isChecking = true
        await environment.checkNow(deviceID: deviceID)
        load(from: environment)
        isChecking = false
        if let device = environment.directory.device(id: deviceID) {
            announce("\(device.displayName): \(device.state.title)")
        }
    }

    func scanPorts(environment: AppEnvironment) async {
        guard !isScanningPorts else { return }
        isScanningPorts = true
        defer { isScanningPorts = false }
        do {
            ports = try await environment.scanPorts(deviceID: deviceID)
        } catch {
            // The ports found earlier stay on screen; the environment shows the error banner.
            environment.haptics.error()
            announce(error.localizedDescription)
            return
        }
        environment.haptics.success()
        let open = ports.filter(\.isOpen).count
        announce("Port scan finished: \(Formatters.count(open, singular: "open service", plural: "open services"))")
    }

    func wake(environment: AppEnvironment) async {
        guard !isWaking else { return }
        isWaking = true
        await environment.wake(deviceID: deviceID)
        isWaking = false
    }

    func loadInsight(environment: AppEnvironment, snapshot: DeviceSnapshot) async {
        guard !isLoadingInsight else { return }
        isLoadingInsight = true
        let input = InsightInput(snapshot: snapshot, now: Date(), locale: Locale.current)
        insight = await environment.insightProvider.insight(for: input)
        isLoadingInsight = false
    }

    /// Results land in cards away from the action buttons, so VoiceOver reads them out.
    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}
