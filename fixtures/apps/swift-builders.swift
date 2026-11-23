// Name: Recipe Card
// Icon: fork.knife
// Tint: orange

import SwiftUI

@propertyWrapper
struct Clamped {
    private var value: Int
    let range: ClosedRange<Int>

    init(wrappedValue: Int, _ range: ClosedRange<Int>) {
        self.range = range
        value = min(max(wrappedValue, range.lowerBound), range.upperBound)
    }

    var wrappedValue: Int {
        get { value }
        set { value = min(max(newValue, range.lowerBound), range.upperBound) }
    }

    var projectedValue: String { "\(value) of \(range.upperBound)" }
}

@resultBuilder
struct StepsBuilder {
    static func buildBlock(_ parts: [String]...) -> [String] { parts.flatMap { $0 } }
    static func buildExpression(_ step: String) -> [String] { [step] }
    static func buildOptional(_ part: [String]?) -> [String] { part ?? [] }
    static func buildEither(first part: [String]) -> [String] { part }
    static func buildEither(second part: [String]) -> [String] { part }
    static func buildArray(_ parts: [[String]]) -> [String] { parts.flatMap { $0 } }
}

struct Recipe {
    var name: String
    @Clamped(1...12) var servings = 4
    var vegetarian = true

    @StepsBuilder var steps: [String] {
        "Heat the pan"
        if vegetarian { "Add the beans" } else { "Add the chicken" }
        for minute in 1...2 { "Stir, minute \(minute)" }
        "Serve"
    }
}

extension EnvironmentValues {
    @Entry var cardTint: Color = .orange
}

@Observable
final class Pantry {
    var cups = 3
}

@Animatable
struct Ring: Shape {
    var progress: Double
    @AnimatableIgnored var label = "ring"

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                  startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * progress), clockwise: false)
        return p
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.cardTint) private var tint

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(tint)
            content
        }
    }
}

struct PantryRow: View {
    @Environment(Pantry.self) private var pantry
    var body: some View { Text("Flour: \(pantry.cups) cups") }
}

struct ContentView: View {
    @State private var recipe = Recipe(name: "Chili")
    @State private var showSteps = true
    @State private var pantry = Pantry()

    var body: some View {
        NavigationStack {
            List {
                Card(title: recipe.name) {
                    Text("Serves \(recipe.servings) (\(recipe.$servings))")
                    if recipe.vegetarian { Text("Vegetarian") }
                }
                Section("Steps") {
                    Toggle("Show steps", isOn: $showSteps.animation())
                    if showSteps { stepList }
                }
                Section("Progress") {
                    Ring(progress: 0.75).stroke(.orange, lineWidth: 6).frame(width: 60, height: 60)
                    status(recipe.servings)
                    PantryRow()
                }
                Section {
                    Button("More servings") { recipe.servings += 5 }
                    Button("Fewer servings") { recipe.servings -= 20 }
                    Button("Switch to chicken") { recipe.vegetarian.toggle() }
                }
            }
            .environment(\.cardTint, .orange)
            .environment(pantry)
            .navigationTitle("Recipe Card")
        }
    }

    @ViewBuilder var stepList: some View {
        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
            Text("\(i + 1). \(step)")
        }
    }

    @ViewBuilder func status(_ servings: Int) -> some View {
        switch servings {
        case 1: Label("Just me", systemImage: "person")
        case 2...4: Label("A few", systemImage: "person.2")
        default: Label("A crowd", systemImage: "person.3")
        }
    }
}
