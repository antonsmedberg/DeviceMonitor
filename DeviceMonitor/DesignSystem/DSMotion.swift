import SwiftUI

/// Animation presets with Reduce Motion fallbacks.
enum DSMotion {
    static let springFast: Animation = .spring(response: 0.28, dampingFraction: 0.86)
    static let springSoft: Animation = .spring(response: 0.45, dampingFraction: 0.9)
    static let fade: Animation = .easeOut(duration: 0.15)

    static func animation(_ base: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : base
    }

    static func rowTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)
    }

    static func bannerTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }
}

/// Reads the accessibility switches every animated view needs, plus the in-app
/// "Reduce visual effects" setting, which the root view injects.
struct DSMotionPreferences {
    let reduceMotion: Bool
    let reduceTransparency: Bool
}

nonisolated struct DSReduceEffectsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    nonisolated var dsReduceEffects: Bool {
        get { self[DSReduceEffectsKey.self] }
        set { self[DSReduceEffectsKey.self] = newValue }
    }

    var dsMotion: DSMotionPreferences {
        DSMotionPreferences(
            reduceMotion: accessibilityReduceMotion || dsReduceEffects,
            reduceTransparency: accessibilityReduceTransparency
        )
    }
}
