// Name: Flashcards
// Icon: rectangle.on.rectangle.angled
// Tint: indigo
// Covers: Gestures, Focus & Keyboard, Accessibility

import SwiftUI

struct Flashcard: Identifiable {
    let id = UUID()
    var front: String
    var back: String
}

struct ContentView: View {
    @State private var cards = [
        Flashcard(front: "Hola", back: "Hello"),
        Flashcard(front: "Gracias", back: "Thank you"),
    ]
    @State private var index = 0
    @State private var showsBack = false
    @State private var starred: Set<String> = []
    @State private var front = ""
    @State private var back = ""
    @State private var reps = 3
    @FocusState private var editing: Bool

    private var card: Flashcard { cards[index % cards.count] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                    Text(showsBack ? card.back : card.front)
                        .font(.largeTitle.bold())
                        .allowsHitTesting(false)
                    if starred.contains(card.front) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding()
                    }
                }
                .frame(height: 220)
                .contentShape(.rect)
                .onTapGesture { showsBack.toggle() }
                .onLongPressGesture { toggleStar() }
                .accessibilityLabel(showsBack ? card.back : card.front)
                .accessibilityHint("Tap to turn the card over")
                .accessibilityIdentifier("card")

                Button("Next Card") {
                    index += 1
                    showsBack = false
                }
                .buttonStyle(.borderedProminent)

                Form {
                    TextField("Front", text: $front)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                    TextField("Back", text: $back)
                        .submitLabel(.done)
                        .onSubmit(add)
                    TextField("Repetitions", value: $reps, format: .number)
                        .keyboardType(.numberPad)
                    Button("Add Card", action: add)
                        .disabled(front.isEmpty || back.isEmpty)
                }
            }
            .padding()
            .navigationTitle("Flashcards")
            .onAppear { editing = false }
        }
    }

    private func toggleStar() {
        if starred.contains(card.front) { starred.remove(card.front) } else { starred.insert(card.front) }
    }

    private func add() {
        cards.append(Flashcard(front: front, back: back))
        front = ""
        back = ""
        editing = false
    }
}
