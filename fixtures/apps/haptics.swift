// Name: Haptic Pad
// Icon: hand.tap
// Tint: orange
// Covers: Haptics

import SwiftUI
import UIKit

struct Pad: Identifiable {
    let id: String
    let feedback: SensoryFeedback
    let symbol: String
}

struct ContentView: View {
    @State private var taps = 0
    @State private var last: String = "Tap a pad"
    @State private var level = 5
    @State private var armed = false
    @State private var played: [String: Int] = [:]

    let pads = [
        Pad(id: "Success", feedback: .success, symbol: "checkmark.circle"),
        Pad(id: "Warning", feedback: .warning, symbol: "exclamationmark.triangle"),
        Pad(id: "Error", feedback: .error, symbol: "xmark.octagon"),
        Pad(id: "Selection", feedback: .selection, symbol: "hand.point.up"),
        Pad(id: "Heavy", feedback: .impact(weight: .heavy, intensity: 1), symbol: "hammer"),
        Pad(id: "Soft", feedback: .impact(flexibility: .soft, intensity: 0.6), symbol: "cloud"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("SwiftUI") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 12) {
                        ForEach(pads) { pad in
                            PadButton(pad: pad, count: played[pad.id] ?? 0) {
                                played[pad.id, default: 0] += 1
                                last = pad.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    Stepper("Level \(level)", value: $level, in: 0...10)
                        .sensoryFeedback(trigger: level) { old, new in new > old ? .increase : .decrease }
                    Toggle("Armed", isOn: $armed)
                        .sensoryFeedback(.start, trigger: armed) { _, new in new }
                        .sensoryFeedback(.stop, trigger: armed) { old, _ in old }
                }
                Section("UIKit generators") {
                    Button("Impact (rigid)") {
                        let generator = UIImpactFeedbackGenerator(style: .rigid)
                        generator.prepare()
                        generator.impactOccurred(intensity: 0.8)
                        last = "UIImpact"
                    }
                    Button("Notification (success)") {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        last = "UINotification"
                    }
                    Button("Selection changed") {
                        UISelectionFeedbackGenerator().selectionChanged()
                        taps += 1
                        last = "UISelection \(taps)"
                    }
                }
                Section {
                    LabeledContent("Last", value: last)
                }
            }
            .navigationTitle("Haptic Pad")
        }
    }
}

struct PadButton: View {
    let pad: Pad
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: pad.symbol).font(.title2)
                Text(pad.id).font(.caption)
                Text("\(count)").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.bordered)
        .sensoryFeedback(pad.feedback, trigger: count)
    }
}
