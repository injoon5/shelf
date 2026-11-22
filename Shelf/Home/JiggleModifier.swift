import SwiftUI

/// The edit-mode wobble: a small rotation and a smaller vertical shift. Each
/// icon starts at its own moment, so they never move in step.
struct Jiggle: ViewModifier {
    var isOn: Bool
    @State private var swing = false
    @State private var phase = Double.random(in: 0..<Motion.jigglePeriod)

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isOn ? (swing ? HomeMetrics.jiggleAngle : -HomeMetrics.jiggleAngle) : 0))
            .offset(y: isOn ? (swing ? HomeMetrics.jiggleShift : -HomeMetrics.jiggleShift) : 0)
            .animation(swing ? Motion.jiggle : Motion.quick, value: swing)
            .animation(Motion.quick, value: isOn)
            .task(id: isOn) {
                guard isOn else { swing = false; return }
                // Lean one way first, then swing between the two sides for good.
                try? await Task.sleep(for: .seconds(phase))
                if !Task.isCancelled { swing = true }
            }
    }
}

/// A quick side-to-side shake: this icon can't open right now.
struct Shake: ViewModifier {
    var trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            let step = Motion.shakeSteps
            SpringKeyframe(HomeMetrics.shakeDistance, duration: step[0], spring: Motion.shakeStep)
            SpringKeyframe(-HomeMetrics.shakeDistance, duration: step[1], spring: Motion.shakeStep)
            SpringKeyframe(HomeMetrics.shakeDistance / 2, duration: step[2], spring: Motion.shakeStep)
            SpringKeyframe(0, duration: step[3], spring: Motion.shakeHome)
        }
    }
}
