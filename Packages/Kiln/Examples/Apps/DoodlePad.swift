import SwiftUI

// Round 1 (PLAN.md §2): gestures, Canvas and focus, compared against native in Kiln Lab.

enum Field: Hashable {
    case title, note
}

struct ContentView: View {
    @State private var strokes: [[CGPoint]] = [[CGPoint(x: 30, y: 40), CGPoint(x: 120, y: 90), CGPoint(x: 210, y: 50)]]
    @State private var current: [CGPoint] = []
    @State private var stamps: [CGPoint] = []
    @State private var offset = CGSize.zero
    @GestureState private var dragging = CGSize.zero
    @State private var title = ""
    @State private var note = ""
    @State private var saved = "Nothing saved"
    @FocusState private var field: Field?

    var body: some View {
        VStack(spacing: 14) {
            Canvas { context, size in
                context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 16), with: .color(.yellow.opacity(0.15)))
                for stroke in strokes + [current] {
                    context.stroke(line(stroke), with: .color(.indigo), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                for p in stamps {
                    var stamp = context
                    stamp.translateBy(x: p.x, y: p.y)
                    stamp.rotate(by: .degrees(45))
                    stamp.fill(Path(CGRect(x: -8, y: -8, width: 16, height: 16)), with: .color(.pink))
                }
                context.draw(Text("\(strokes.count) strokes").font(.caption.bold()), at: CGPoint(x: size.width - 8, y: 8), anchor: .topTrailing)
            }
            .frame(height: 220)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in current.append(value.location) }
                    .onEnded { _ in
                        strokes.append(current)
                        current = []
                    }
            )
            .onTapGesture(count: 2) { location in stamps.append(location) }
            .accessibilityLabel("Doodle canvas")

            Text("Drag me")
                .padding(12)
                .background(.indigo.opacity(0.2), in: .capsule)
                .offset(x: offset.width + dragging.width, y: offset.height + dragging.height)
                .gesture(
                    DragGesture()
                        .updating($dragging) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            offset.width += value.translation.width
                            offset.height += value.translation.height
                        }
                )

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($field, equals: .title)
                .submitLabel(.next)
                .onSubmit { field = .note }
            TextField("Note", text: $note)
                .textFieldStyle(.roundedBorder)
                .focused($field, equals: .note)
                .submitLabel(.done)
                .onSubmit { field = nil }

            HStack {
                Button("Clear") {
                    strokes = []
                    stamps = []
                }
                Button("Save") {
                    saved = "Saved \(title.isEmpty ? "untitled" : title), \(strokes.count) strokes"
                    field = nil
                }
                Button("Edit title") { field = .title }
            }
            .buttonStyle(.bordered)

            Text(saved)
            Text(field == nil ? "No field focused" : (field == .title ? "Title focused" : "Note focused"))
            Text("Hidden from VoiceOver").accessibilityHidden(true)
        }
        .padding()
    }

    func line(_ points: [CGPoint]) -> Path {
        Path { p in
            guard let first = points.first else { return }
            p.move(to: first)
            for point in points.dropFirst() { p.addLine(to: point) }
        }
    }
}
