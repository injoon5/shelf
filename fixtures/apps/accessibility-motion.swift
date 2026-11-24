// Name: Breathe
// Icon: wind
// Tint: teal
// Covers: Accessibility, Core, Drawing

import SwiftUI

enum Phase: CaseIterable {
    case inhale, hold, exhale

    var scale: Double {
        switch self {
        case .inhale: return 1.4
        case .hold: return 1.4
        case .exhale: return 0.8
        }
    }
}

struct ContentView: View {
    @State private var running = false
    @State private var rounds = 3
    @State private var expanded = false
    @AccessibilityFocusState private var announce: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var space

    var body: some View {
        VStack(spacing: 28) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(context.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Circle()
                .fill(.teal.gradient)
                .frame(width: 140, height: 140)
                .phaseAnimator(Phase.allCases, trigger: running) { content, phase in
                    content
                        .scaleEffect(reduceMotion ? 1 : phase.scale)
                        .opacity(phase == .hold ? 0.8 : 1)
                } animation: { phase in
                    switch phase {
                    case .inhale: return .easeInOut(duration: 1.2)
                    case .hold: return .linear(duration: 0.6)
                    case .exhale: return .easeOut(duration: 1.4)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Breathing circle")
                .accessibilityValue(running ? "Running" : "Paused")
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityAction(named: "Start") { running.toggle() }
                .accessibilityFocused($announce)

            HStack {
                Text("Rounds")
                Spacer()
                Text("\(rounds)")
                    .contentTransition(.numericText(value: Double(rounds)))
                    .accessibilityHidden(true)
            }
            .padding()
            .background(.thinMaterial, in: .rect(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .accessibilityValue("\(rounds) rounds")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: rounds += 1
                case .decrement: rounds = max(1, rounds - 1)
                default: break
                }
            }

            Group {
                if expanded {
                    Text("Breathe in through your nose, hold, and let it out slowly.")
                        .padding()
                        .background(.teal.opacity(0.15), in: .rect(cornerRadius: 16))
                        .matchedGeometryEffect(id: "tip", in: space)
                } else {
                    Label("Tip", systemImage: "lightbulb")
                        .padding(10)
                        .background(.teal.opacity(0.15), in: .capsule)
                        .matchedGeometryEffect(id: "tip", in: space)
                }
            }
            .onTapGesture { withAnimation(.spring(duration: 0.4)) { expanded.toggle() } }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows how to breathe")

            Button(running ? "Pause" : "Start") {
                running.toggle()
                announce = true
            }
            .buttonStyle(.borderedProminent)
            .accessibilitySortPriority(1)
            .accessibilityInputLabels(["Start", "Go", "Pause"])
        }
        .padding()
        .accessibilityRotor("Controls") {
            AccessibilityRotorEntry("Start button", id: "start")
        }
        .speechAnnouncementsQueued()
    }
}
