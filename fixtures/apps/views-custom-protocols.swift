// Name: Tide Board
// Icon: water.waves
// Tint: teal
// Covers: Layout, Drawing, Core

import SwiftUI

// Your own types where SwiftUI takes its protocols: a Shape that animates,
// a Layout, ViewModifiers (one with state, one called from a View
// extension), a Transition, and AnyTransition built from modifiers.

struct Tide: Shape {
    var level: Double
    var swell: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(level, swell) }
        set {
            level = newValue.first
            swell = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = rect.maxY - rect.height * level
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var x = 0.0
        while x <= rect.width {
            let y = top + sin(x / rect.width * Double.pi * 2) * swell
            path.addLine(to: CGPoint(x: rect.minX + x, y: y))
            x += 6
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct Columns: Layout {
    var count = 3
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let column = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        var heights = Array(repeating: CGFloat(0), count: count)
        for (i, subview) in subviews.enumerated() {
            heights[i % count] += subview.sizeThatFits(ProposedViewSize(width: column, height: nil)).height + spacing
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let column = (bounds.width - spacing * CGFloat(count - 1)) / CGFloat(count)
        var y = Array(repeating: bounds.minY, count: count)
        for (i, subview) in subviews.enumerated() {
            let c = i % count
            let size = subview.sizeThatFits(ProposedViewSize(width: column, height: nil))
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(c) * (column + spacing), y: y[c]),
                          proposal: ProposedViewSize(width: column, height: size.height))
            y[c] += size.height + spacing
        }
    }
}

struct Tile: ViewModifier {
    var tint: Color
    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.15)))
    }
}

struct Pinned: ViewModifier {
    @State private var pinned = false
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                Image(systemName: pinned ? "pin.fill" : "pin")
            }
            .onTapGesture { pinned.toggle() }
    }
}

extension View {
    func tile(_ tint: Color = .teal) -> some View { modifier(Tile(tint: tint)) }
}

struct Rise: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .offset(y: phase.isIdentity ? 0 : 30)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

struct Fade: ViewModifier {
    var amount: Double
    func body(content: Content) -> some View { content.opacity(1 - amount) }
}

struct ContentView: View {
    @State private var high = false
    @State private var showTip = true
    private let places = ["Harbor", "Point", "Cove", "Reef", "Bay", "Inlet"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Tide(level: high ? 0.8 : 0.3, swell: high ? 12 : 4)
                        .fill(Color.teal.gradient)
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Columns(count: 3) {
                        ForEach(places, id: \.self) { place in
                            Text(place).tile()
                        }
                    }
                    Text("Tap to pin").modifier(Pinned()).tile(.orange)
                    if showTip {
                        Text("High tide at 6:40")
                            .tile(.blue)
                            .transition(Rise())
                    }
                    if high {
                        Text("Swell rising")
                            .transition(.modifier(active: Fade(amount: 1), identity: Fade(amount: 0)))
                    }
                    Button(high ? "Low Tide" : "High Tide") {
                        withAnimation(.easeInOut(duration: 0.6)) { high.toggle() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Tide Board")
        }
    }
}
