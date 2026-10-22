import Foundation
import AppIntents

extension Notification.Name {
    static let deviceMonitorScanRequested = Notification.Name("eu.smedberg.DeviceMonitor.scanRequested")
}

/// Counts from the last completed monitoring round, kept for Siri and Shortcuts so they can
/// answer without touching the network.
nonisolated struct NetworkStatusSummary: Codable, Sendable, Hashable {
    let online: Int
    let unstable: Int
    let offline: Int
    let total: Int
    let checkedAt: Date

    init(online: Int, unstable: Int, offline: Int, total: Int, checkedAt: Date) {
        self.online = online
        self.unstable = unstable
        self.offline = offline
        self.total = total
        self.checkedAt = checkedAt
    }

    static let defaultsKey = "intent.networkStatusSummary"

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> NetworkStatusSummary? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(NetworkStatusSummary.self, from: data)
    }

    func sentence(now: Date) -> String {
        guard total > 0 else { return "DeviceMonitor is not tracking any devices yet. Open the app and scan your network." }
        var parts = ["\(online + unstable) of \(total) devices are online"]
        if unstable > 0 { parts.append("\(unstable) unstable") }
        if offline > 0 { parts.append("\(offline) offline") }
        let checked = Formatters.relative(checkedAt, now: now).lowercased()
        return parts.joined(separator: ", ") + ". Last checked \(checked)."
    }
}

/// Opens the app and starts a network scan. Local-network work never runs inside the intent itself.
struct StartNetworkScanIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan Network"
    static let description = IntentDescription("Opens DeviceMonitor and scans your Wi‑Fi for devices.")
    static var supportedModes: IntentModes { .foreground }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "intent.pendingScanRequested")
        NotificationCenter.default.post(name: .deviceMonitorScanRequested, object: nil)
        return .result()
    }
}

/// Answers "How is my network?" from the last completed round, without opening the app.
struct NetworkStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Network Status"
    static let description = IntentDescription("Says how many of your devices are online, based on the last check.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let summary = NetworkStatusSummary.load() else {
            return .result(dialog: "Open DeviceMonitor once so it can check your network.")
        }
        return .result(dialog: "\(summary.sentence(now: Date()))")
    }
}

struct OpenDeviceMonitorIntent: AppIntent {
    static let title: LocalizedStringResource = "Open DeviceMonitor"
    static let description = IntentDescription("Opens DeviceMonitor on your network overview.")
    static var supportedModes: IntentModes { .foreground }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct DeviceMonitorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartNetworkScanIntent(),
            phrases: [
                "Scan my network with \(.applicationName)",
                "Find devices with \(.applicationName)",
            ],
            shortTitle: "Scan Network",
            systemImageName: "dot.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: NetworkStatusIntent(),
            phrases: [
                "How is my network in \(.applicationName)",
                "Check my network with \(.applicationName)",
            ],
            shortTitle: "Network Status",
            systemImageName: "waveform.path.ecg"
        )
        AppShortcut(
            intent: OpenDeviceMonitorIntent(),
            phrases: [
                "Open \(.applicationName)",
            ],
            shortTitle: "Open DeviceMonitor",
            systemImageName: "gauge.with.needle"
        )
    }
}
