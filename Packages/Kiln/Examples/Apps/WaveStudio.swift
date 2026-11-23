import SwiftUI

// Custom shapes that animate (PLAN.md §1.5): a wave whose amplitude and
// frequency interpolate through an AnimatablePair, a ring drawn by its
// animatableData, a counter view that is itself Animatable, and a badge with
// its own Transition.

struct Wave: Shape {
    var amplitude: Double
    var frequency: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(amplitude, frequency) }
        set {
            amplitude = newValue.first
            frequency = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        var x = 0.0
        while x <= rect.width {
            let angle = x / rect.width * frequency * 2 * Double.pi
            path.addLine(to: CGPoint(x: rect.minX + x, y: rect.midY + sin(angle) * amplitude))
            x += 4
        }
        return path
    }
}

struct Ring: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * progress), clockwise: false)
        return path
    }
}

struct CountingLabel: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))%")
            .font(.title2.bold())
    }
}

struct Pop: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : 0.3)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

struct ContentView: View {
    @State private var stormy = false
    @State private var progress = 0.25

    var body: some View {
        VStack(spacing: 24) {
            Text(stormy ? "Stormy" : "Calm")
                .font(.title.bold())
            Wave(amplitude: stormy ? 40 : 8, frequency: stormy ? 4 : 1.5)
                .stroke(Color.blue, lineWidth: 3)
                .frame(height: 120)
            ZStack {
                Ring(progress: 1)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 14)
                Ring(progress: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                CountingLabel(value: progress * 100)
            }
            .frame(width: 160, height: 160)
            if progress >= 1 {
                Text("Done!")
                    .padding(8)
                    .background(Capsule().fill(Color.green.opacity(0.2)))
                    .transition(Pop())
            }
            HStack {
                Button("Toggle Weather") {
                    withAnimation(.easeInOut(duration: 0.3)) { stormy.toggle() }
                }
                Button("Fill Ring") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        progress = progress >= 1 ? 0.25 : progress + 0.25
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
