import UIKit
import UIKit.UIGestureRecognizerSubclass

// Interruptible motion in UIKit. Every animation here starts from what is on
// screen now, read from the layer's presentation, never from the model value
// (which already holds the previous animation's target). So a spring that is
// retargeted mid-flight, or a view grabbed by a finger, carries on from
// exactly where it is, with no jump and nothing queued behind it.

@MainActor
extension CALayer {
    /// Moves `keyPath` to `value` on `spring`, starting from the presentation.
    /// `velocity` is in spring lengths per second, as `CASpringAnimation` wants.
    func spring(_ keyPath: String, to value: Any, _ spring: Motion.Spring, velocity: CGFloat = 0) {
        let from = presentation()?.value(forKeyPath: keyPath) ?? self.value(forKeyPath: keyPath)
        removeAnimation(forKey: keyPath)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setValue(value, forKeyPath: keyPath)
        CATransaction.commit()
        let animation = CASpringAnimation(perceptualDuration: spring.playedDuration, bounce: spring.bounce)
        animation.keyPath = keyPath
        animation.fromValue = from
        animation.toValue = value
        animation.initialVelocity = spring.played(velocity: velocity)
        animation.duration = animation.settlingDuration
        add(animation, forKey: keyPath)
    }

    /// Stops every animation on this layer and the ones inside it.
    func removeAllAnimationsDeeply() {
        removeAllAnimations()
        sublayers?.forEach { $0.removeAllAnimationsDeeply() }
    }

    var isAnimating: Bool { !(animationKeys()?.isEmpty ?? true) }
}

/// Sets layer properties at once, with no implicit animation.
func withoutActions(_ changes: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    changes()
    CATransaction.commit()
}

extension UIView {
    /// Stops the view where it is on screen: its model takes the
    /// presentation's frame, transform and alpha, and its own animations are
    /// removed. Called before any retarget, so the new animation's
    /// from-value is the on-screen one.
    ///
    /// Only the view's own layer: what UIKit and SwiftUI animate inside a
    /// view (a glass effect's press, say) is theirs to finish.
    func freezeOnScreen() {
        guard let shown = layer.presentation() else { return }
        let bounds = shown.bounds
        let position = shown.position
        let transform = shown.transform
        let opacity = shown.opacity
        layer.removeAllAnimations()
        UIView.performWithoutAnimation {
            layer.bounds = bounds
            layer.position = position
            layer.transform = transform
            layer.opacity = opacity
            layoutIfNeeded()
        }
    }

    /// Stops the view's fade where it is on screen, and nothing else: for
    /// views whose frames belong to someone else (a hosting controller's).
    func freezeOpacityOnScreen() {
        guard let shown = layer.presentation() else { return }
        let opacity = shown.opacity
        layer.removeAnimation(forKey: "opacity")
        layer.opacity = opacity
    }

    /// Animates `changes` on `spring` from wherever `views` are on screen.
    /// `velocity` is in spring lengths per second.
    /// Of `fading`, only the opacity is stopped and animated.
    static func retarget(_ views: [UIView], fading: [UIView] = [], _ spring: Motion.Spring, velocity: CGFloat = 0,
                         changes: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        views.forEach { $0.freezeOnScreen() }
        fading.forEach { $0.freezeOpacityOnScreen() }
        UIView.animate(springDuration: spring.playedDuration, bounce: spring.bounce, initialSpringVelocity: spring.played(velocity: velocity),
                       delay: 0, options: [.allowUserInteraction], animations: changes, completion: completion)
    }
}

/// A pan that begins the moment a finger lands, so a moving thing can be
/// caught before the finger has moved at all.
final class ImmediatePanGestureRecognizer: UIPanGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if state == .possible { state = .began }
    }
}
