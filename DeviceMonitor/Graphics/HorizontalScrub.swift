import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass   // the settable `state` and the touch overrides

/// A sideways scrub that leaves vertical drags to the enclosing scroll view: it fails as soon as the finger
/// moves a few points more vertically than horizontally, so a page scrolls even when the drag starts on a
/// chart. While it runs it reports the touch's x in the view it is attached to, then its end.
struct HorizontalScrub: UIGestureRecognizerRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    init(onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping () -> Void) {
        self.onChanged = onChanged
        self.onEnded = onEnded
    }

    func makeUIGestureRecognizer(context: Context) -> Recognizer {
        Recognizer(target: nil, action: nil)
    }

    func handleUIGestureRecognizerAction(_ recognizer: Recognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(context.converter.localLocation.x)
        case .ended, .cancelled:
            onEnded()
        default:
            break
        }
    }

    /// A pan that fails before it begins once the touch has moved `slop` points or more, more vertically than
    /// horizontally.
    final class Recognizer: UIPanGestureRecognizer {
        private static let slop: CGFloat = 4
        private var start: CGPoint?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            if start == nil {
                start = touches.first?.location(in: view)
            }
            super.touchesBegan(touches, with: event)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            if state == .possible, let start, let point = touches.first?.location(in: view) {
                let dx = abs(point.x - start.x)
                let dy = abs(point.y - start.y)
                if max(dx, dy) >= Self.slop, dy > dx {
                    state = .failed
                    return
                }
            }
            super.touchesMoved(touches, with: event)
        }

        /// The navigation controller's swipe back from anywhere in the content waits for this to fail, so a
        /// rightward scrub on a pushed page scrubs; the swipe from the edge still goes back.
        override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            let navigation = otherGestureRecognizer.view?.next as? UINavigationController
            if otherGestureRecognizer === navigation?.interactiveContentPopGestureRecognizer {
                return true
            }
            return super.shouldBeRequiredToFail(by: otherGestureRecognizer)
        }

        override func reset() {
            super.reset()
            start = nil
        }
    }
}
