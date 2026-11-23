// Workload: structs, classes, methods, closures, enums and strings.
import SwiftUI

enum Op { case add, sub, mul }

struct Vec {
    var x: Double
    var y: Double
    func plus(_ o: Vec) -> Vec { Vec(x: x + o.x, y: y + o.y) }
    func scaled(_ k: Double) -> Vec { Vec(x: x * k, y: y * k) }
    var length: Double { (x * x + y * y).squareRoot() }
}

final class Particle {
    var position: Vec
    var velocity: Vec
    init(position: Vec, velocity: Vec) {
        self.position = position
        self.velocity = velocity
    }
    func step(_ dt: Double) {
        position = position.plus(velocity.scaled(dt))
        if position.x < 0 || position.x > 100 { velocity.x = -velocity.x }
        if position.y < 0 || position.y > 100 { velocity.y = -velocity.y }
    }
}

func apply(_ op: Op, _ a: Int, _ b: Int) -> Int {
    switch op {
    case .add: return a + b
    case .sub: return a - b
    case .mul: return a * b % 1000
    }
}

func simulate() -> String {
    var particles: [Particle] = []
    for i in 0..<40 {
        particles.append(Particle(position: Vec(x: Double(i), y: Double(i * 2 % 100)),
                                  velocity: Vec(x: Double(i % 7) - 3, y: Double(i % 5) - 2)))
    }
    for _ in 0..<40 {
        for p in particles { p.step(0.5) }
    }
    let spread = particles.map { $0.position.length }.reduce(0, +)

    let ops: [Op] = [.add, .sub, .mul]
    var acc = 1
    for i in 0..<1500 { acc = apply(ops[i % 3], acc, i) }

    var words: [String] = []
    for i in 0..<300 { words.append("w\(i % 13)") }
    let joined = words.joined(separator: ",")
    let counter: (Int) -> Int = { n in n + joined.count }
    return "\(Int(spread)) \(acc) \(counter(1))"
}

struct ContentView: View {
    @State private var result = ""

    var body: some View {
        Text(result.isEmpty ? "Working" : result)
            .onAppear { result = simulate() }
    }
}
