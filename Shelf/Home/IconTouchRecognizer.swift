import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Everything one finger does to an icon, as Springboard reads it, in one
/// recognizer so the parts can hand over to each other mid-touch:
///
/// - touch-down presses the icon at once (it darkens);
/// - let go before the hold, it is a tap;
/// - move before the hold, it is someone else's (a page swipe, a pull
///   down for search): the press lets go and this recognizer fails;
/// - hold, it begins: the icon lifts (its menu, or in edit mode the pickup),
///   and every move after that is this recognizer's, for a drag.
///
/// The pages and the search pull wait for it to fail, so a touch that
/// begins on an icon is never two things at once.
final class IconTouchRecognizer: UIGestureRecognizer {
    /// The icon at a point in the recognizer's view, if a press can start
    /// there now.
    var iconAt: (CGPoint) -> IconView? = { _ in nil }
    /// How long a still finger takes to lift an icon.
    var holdDuration: () -> TimeInterval = { Motion.menuHold }
    var onPress: (IconView, Bool) -> Void = { _, _ in }
    var onTap: (IconView, CGPoint) -> Void = { _, _ in }

    /// The icon under the finger, from touch-down until the touch ends.
    private(set) var icon: IconView?
    private var start: CGPoint = .zero
    private var touch: UITouch?
    private var hold: Timer?
    /// Recent positions in the window, for the finger's speed on release.
    private var samples: [(time: TimeInterval, point: CGPoint)] = []

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        // Taps and drags on the Home Screen's own buttons still reach them.
        cancelsTouchesInView = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touch == nil, let first = touches.first else {
            // A second finger: this is one-finger business.
            for extra in touches where extra !== touch { ignore(extra, for: event) }
            return
        }
        let point = first.location(in: view)
        guard let icon = iconAt(point) else {
            state = .failed
            return
        }
        touch = first
        self.icon = icon
        start = point
        samples = [(first.timestamp, first.location(in: nil))]
        onPress(icon, true)
        hold = Timer.scheduledTimer(withTimeInterval: holdDuration() * Motion.Spring.slowdown, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state == .possible, self.icon != nil else { return }
                self.state = .began
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch, touches.contains(touch) else { return }
        samples.append((touch.timestamp, touch.location(in: nil)))
        samples.removeAll { touch.timestamp - $0.time > 0.08 }
        switch state {
        case .possible:
            let point = touch.location(in: view)
            if hypot(point.x - start.x, point.y - start.y) > HomeMetrics.touchSlop {
                release()
                state = .failed
            }
        case .began, .changed:
            state = .changed
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch, touches.contains(touch) else { return }
        switch state {
        case .possible:
            let point = touch.location(in: view)
            if let icon {
                release()
                onTap(icon, point)
            }
            state = .failed
        case .began, .changed:
            state = .ended
        default:
            break
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch, touches.contains(touch) else { return }
        if state == .possible {
            release()
            state = .failed
        } else {
            state = .cancelled
        }
    }

    override func reset() {
        super.reset()
        hold?.invalidate()
        hold = nil
        touch = nil
        icon = nil
        samples = []
    }

    /// How fast the finger was moving over its last few points, in points
    /// per second in the window's coordinates.
    var velocity: CGPoint {
        guard let first = samples.first, let last = samples.last, last.time - first.time > 0.005 else { return .zero }
        let dt = last.time - first.time
        return CGPoint(x: (last.point.x - first.point.x) / dt, y: (last.point.y - first.point.y) / dt)
    }

    private func release() {
        if let icon { onPress(icon, false) }
    }

    /// Where the touch first came down, in `view`'s coordinates.
    func startLocation(in view: UIView?) -> CGPoint {
        guard let own = self.view else { return start }
        return own.convert(start, to: view)
    }
}
