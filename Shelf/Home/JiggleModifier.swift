/// The edit-mode wobble: a small rotation and a smaller vertical shift. Each
/// icon starts at its own moment, so they never move in step.
struct Jiggle: ViewModifier {
    @Environment(ShelfSettings.self) private var settings
    var isOn: Bool
    @State private var swing = false
    @State private var phase = Double.random(in: 0..<Motion.jigglePeriod)

    func body(content: Content) -> some View {
        content
            .modifier(Tilt(angle: isOn ? (swing ? HomeMetrics.jiggleAngle : -HomeMetrics.jiggleAngle) : 0,
                           shift: isOn ? (swing ? HomeMetrics.jiggleShift : -HomeMetrics.jiggleShift) : 0,
                           turnsGlass: settings.iconStyle == .clear))
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

/// The jiggle at one moment. Glass turned as a whole view smears and
/// shimmers, so under a Clear icon the glass is never turned: its shape is,
/// and the pieces over it turn themselves by `jiggleTurn`.
private struct Tilt: ViewModifier, Animatable {
    var angle: Double
    var shift: CGFloat
    var turnsGlass: Bool

    var animatableData: AnimatablePair<Double, CGFloat> {
        get { AnimatablePair(angle, shift) }
        set { (angle, shift) = (newValue.first, newValue.second) }
    }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(turnsGlass ? 0 : angle))
            .environment(\.jiggleTurn, .degrees(turnsGlass ? angle : 0))
            .offset(y: shift)
    }
}

extension EnvironmentValues {
    /// How far a jiggling Clear icon's parts turn on their own.
    @Entry var jiggleTurn = Angle.zero
}

/// Turns a part of a jiggling Clear icon that isn't glass.
struct JiggleTurn: ViewModifier {
    @Environment(\.jiggleTurn) private var turn

    func body(content: Content) -> some View {
        content.rotationEffect(turn)
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
