import UIKit
import Observation

/// Prepared feedback generators, gated by the user's haptics setting.
@MainActor
final class HapticsController {
    private let settings: SettingsStore
    private lazy var selectionGenerator = UISelectionFeedbackGenerator()
    private lazy var notificationGenerator = UINotificationFeedbackGenerator()
    private lazy var impactGenerator = UIImpactFeedbackGenerator(style: .light)

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func prepare() {
        guard settings.hapticsEnabled else { return }
        selectionGenerator.prepare()
        notificationGenerator.prepare()
        impactGenerator.prepare()
    }

    func selection() {
        guard settings.hapticsEnabled else { return }
        selectionGenerator.selectionChanged()
    }

    func success() {
        guard settings.hapticsEnabled else { return }
        notificationGenerator.notificationOccurred(.success)
    }

    func warning() {
        guard settings.hapticsEnabled else { return }
        notificationGenerator.notificationOccurred(.warning)
    }

    func error() {
        guard settings.hapticsEnabled else { return }
        notificationGenerator.notificationOccurred(.error)
    }

    func impact() {
        guard settings.hapticsEnabled else { return }
        impactGenerator.impactOccurred()
    }
}
