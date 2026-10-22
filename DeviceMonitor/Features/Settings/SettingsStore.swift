import Foundation
import SwiftUI
import UIKit
import Observation

/// The app's accent. There is no purple choice, because violet is the jitter series, and no teal, because
/// teal sits too close to the online mint. `blue` keeps its raw value for storage and is titled "Cobalt"; a
/// stored "teal" falls back to it.
nonisolated enum AccentChoice: String, Sendable, Codable, Hashable, CaseIterable {
    case blue, graphite

    var title: String {
        switch self {
        case .blue: return "Cobalt"
        case .graphite: return "Graphite"
        }
    }

    /// Light-mode variants are dark enough for 4.5:1 small text on white; dark-mode ones are lifted.
    /// The Increase Contrast variants (graphite #414853 / #C3CBD8) reach 7:1 on cards.
    var color: Color {
        switch self {
        case .blue: return .accentColor
        case .graphite: return Self.dynamic(light: (0.33, 0.36, 0.42), dark: (0.64, 0.67, 0.74), hcLight: (0.255, 0.282, 0.325), hcDark: (0.765, 0.796, 0.847))
        }
    }

    private static func dynamic(
        light: (Double, Double, Double),
        dark: (Double, Double, Double),
        hcLight: (Double, Double, Double),
        hcDark: (Double, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let rgb = traits.accessibilityContrast == .high ? (isDark ? hcDark : hcLight) : (isDark ? dark : light)
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

nonisolated enum DashboardSortOption: String, Sendable, Codable, Hashable, CaseIterable {
    case status, name, lastSeen, latency

    var title: String {
        switch self {
        case .status: return "Status"
        case .name: return "Name"
        case .lastSeen: return "Last seen"
        case .latency: return "Latency"
        }
    }
}

/// User preferences persisted in `UserDefaults`.
@Observable
@MainActor
final class SettingsStore {
    private enum Keys {
        static let monitor = "settings.monitor"
        static let policy = "settings.policy"
        static let accent = "settings.accent"
        static let haptics = "settings.haptics"
        static let reduceEffects = "settings.reduceEffects"
        static let onboarding = "settings.hasCompletedOnboarding"
        static let sort = "settings.dashboardSort"
        static let pendingScan = "intent.pendingScanRequested"
        static let useDemoData = "settings.useDemoData"
    }

    /// Lets App Review (or anyone without a home network at hand) see the app with sample data.
    /// Stored in the standard defaults on purpose: the demo environment uses its own suite.
    static var usesDemoDataOnLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.useDemoData) }
        set {
            let wasOn = UserDefaults.standard.bool(forKey: Keys.useDemoData)
            UserDefaults.standard.set(newValue, forKey: Keys.useDemoData)
            // Older builds saved demo rounds for Siri. Drop that summary when demo data is turned
            // off so Siri never reports the sample network; the next real round saves a fresh one.
            if wasOn && !newValue {
                UserDefaults.standard.removeObject(forKey: NetworkStatusSummary.defaultsKey)
            }
        }
    }

    private let defaults: UserDefaults

    var monitor: MonitorSettings {
        didSet { persist(monitor, key: Keys.monitor) }
    }

    var policy: ReachabilityPolicy {
        didSet { persist(policy, key: Keys.policy) }
    }

    var accent: AccentChoice {
        didSet { defaults.set(accent.rawValue, forKey: Keys.accent) }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }

    var reduceEffects: Bool {
        didSet { defaults.set(reduceEffects, forKey: Keys.reduceEffects) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }

    var dashboardSort: DashboardSortOption {
        didSet { defaults.set(dashboardSort.rawValue, forKey: Keys.sort) }
    }

    var pendingScanRequested: Bool {
        didSet { defaults.set(pendingScanRequested, forKey: Keys.pendingScan) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        monitor = Self.load(MonitorSettings.self, key: Keys.monitor, defaults: defaults)?.clamped() ?? .standard
        policy = Self.load(ReachabilityPolicy.self, key: Keys.policy, defaults: defaults)?.clamped() ?? .standard
        accent = AccentChoice(rawValue: defaults.string(forKey: Keys.accent) ?? "") ?? .blue
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        reduceEffects = defaults.bool(forKey: Keys.reduceEffects)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        dashboardSort = DashboardSortOption(rawValue: defaults.string(forKey: Keys.sort) ?? "") ?? .status
        pendingScanRequested = defaults.bool(forKey: Keys.pendingScan)
    }

    func resetToDefaults() {
        monitor = .standard
        policy = .standard
        accent = .blue
        hapticsEnabled = true
        reduceEffects = false
        dashboardSort = .status
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
