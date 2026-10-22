import SwiftUI
import UIKit
import QuartzCore

/// One-shot expanding rings (`CAReplicatorLayer`) fired when a device changes state.
struct PulseRingView: UIViewRepresentable {
    let trigger: Int
    let tint: UIColor
    let isEnabled: Bool

    init(trigger: Int, tint: UIColor, isEnabled: Bool) {
        self.trigger = trigger
        self.tint = tint
        self.isEnabled = isEnabled
    }

    func makeUIView(context: Context) -> PulseRingUIView {
        PulseRingUIView()
    }

    func updateUIView(_ uiView: PulseRingUIView, context: Context) {
        uiView.tint = tint
        if uiView.lastTrigger != trigger {
            uiView.lastTrigger = trigger
            if isEnabled && trigger > 0 {
                uiView.pulse()
            }
        }
    }
}

final class PulseRingUIView: UIView {
    var tint: UIColor = .systemBlue
    var lastTrigger = 0
    private let replicator = CAReplicatorLayer()
    private let ring = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        replicator.instanceCount = 3
        replicator.instanceDelay = 0.22
        ring.fillColor = nil
        ring.lineWidth = 2
        ring.opacity = 0
        replicator.addSublayer(ring)
        layer.addSublayer(replicator)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        replicator.frame = bounds
        ring.frame = bounds
        let inset = bounds.width * 0.2
        ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset)).cgPath
    }

    func pulse() {
        ring.strokeColor = tint.cgColor
        let ringDuration = 1.1
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 1.9
        scale.duration = ringDuration
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.7
        opacity.toValue = 0
        opacity.duration = ringDuration
        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        // Outlive the last delayed replicator instance so every ring fades out completely.
        group.duration = ringDuration + Double(replicator.instanceCount - 1) * replicator.instanceDelay
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = true
        ring.removeAllAnimations()
        ring.add(group, forKey: "pulse")
    }
}
