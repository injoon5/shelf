import SwiftUI

// Custom ViewModifiers (PLAN.md §1.5): a card style, one with its own @State,
// an Animatable one that shakes, and a transition built from modifiers.

struct Card: ViewModifier {
    var title: String

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.1)))
    }
}

struct TapCounter: ViewModifier {
    @State private var taps = 0

    func body(content: Content) -> some View {
        HStack {
            content
            Spacer()
            Text("Taps: \(taps)")
            Button("Tap") { taps += 1 }
        }
    }
}

struct Shake: ViewModifier, Animatable {
    var amount: Double

    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(x: sin(amount * Double.pi * 4) * 10)
    }
}

struct Dim: ViewModifier {
    var amount: Double

    func body(content: Content) -> some View {
        content
            .opacity(1 - amount)
            .scaleEffect(1 - amount * 0.2)
    }
}

struct ContentView: View {
    @State private var shakes = 0.0
    @State private var showNote = true

    var body: some View {
        VStack(spacing: 16) {
            Text("Hello from a card")
                .modifier(Card(title: "Greeting"))
            Text("Counter")
                .modifier(TapCounter())
                .modifier(Card(title: "State"))
            Text("Shaky text")
                .modifier(Shake(amount: shakes))
            if showNote {
                Text("This note fades and shrinks away.")
                    .modifier(Card(title: "Note"))
                    .transition(.modifier(active: Dim(amount: 1), identity: Dim(amount: 0)))
            }
            HStack {
                Button("Shake") {
                    withAnimation(.linear(duration: 0.4)) { shakes += 1 }
                }
                Button("Toggle Note") {
                    withAnimation(.easeInOut(duration: 0.3)) { showNote.toggle() }
                }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }
}
