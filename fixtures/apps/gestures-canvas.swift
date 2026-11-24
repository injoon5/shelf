// Name: Sketch Pad
// Icon: scribble.variable
// Tint: orange
// Covers: Gestures, Drawing

import SwiftUI

struct Stroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var color: Color
    var width: Double
}

struct Bounce {
    var scale = 1.0
    var lift = 0.0
}

struct ContentView: View {
    @State private var strokes: [Stroke] = []
    @State private var current: [CGPoint] = []
    @State private var color = Color.orange
    @State private var width = 6.0
    @State private var stickerOffset = CGSize.zero
    @GestureState private var stickerDrag = CGSize.zero
    @State private var stickerScale = 1.0
    @GestureState private var pinch = 1.0
    @State private var stickerAngle = Angle.zero
    @GestureState private var twist = Angle.zero
    @GestureState private var pressing = false
    @State private var stamps = 0
    @State private var lastTap = "Double-tap to stamp"
    @Namespace private var palette

    let colors: [Color] = [.orange, .pink, .blue, .green]

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Canvas { context, size in
                    context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 24), with: .color(.gray.opacity(0.12)))
                    for stroke in strokes {
                        context.stroke(path(stroke.points), with: .color(stroke.color),
                                       style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
                    }
                    context.stroke(path(current), with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                    var grid = context
                    grid.opacity = 0.25
                    for x in stride(from: 0.0, through: size.width, by: 40) {
                        grid.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                                    with: .color(.secondary), lineWidth: 0.5)
                    }
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: .black.opacity(0.2), radius: 3, y: 2))
                        layer.draw(Text("\(stamps) stamps").font(.caption.bold()), at: CGPoint(x: size.width - 12, y: 14), anchor: .topTrailing)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in current.append(value.location) }
                        .onEnded { _ in
                            strokes.append(Stroke(points: current, color: color, width: width))
                            current = []
                        }
                )
                .onTapGesture(count: 2) { location in
                    stamps += 1
                    lastTap = "Stamped at \(Int(location.x)), \(Int(location.y))"
                }

                Image(systemName: "star.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(pressing ? .yellow : color)
                    .symbolEffect(.bounce, value: stamps)
                    .scaleEffect(stickerScale * pinch)
                    .rotationEffect(stickerAngle + twist)
                    .offset(x: stickerOffset.width + stickerDrag.width, y: stickerOffset.height + stickerDrag.height)
                    .gesture(
                        DragGesture()
                            .updating($stickerDrag) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                stickerOffset.width += value.translation.width
                                stickerOffset.height += value.translation.height
                            }
                    )
                    .simultaneousGesture(
                        MagnifyGesture()
                            .updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { value in stickerScale *= value.magnification }
                            .simultaneously(with: RotateGesture()
                                .updating($twist) { value, state, _ in state = value.rotation }
                                .onEnded { value in stickerAngle += value.rotation })
                    )
                    .highPriorityGesture(
                        LongPressGesture(minimumDuration: 0.4)
                            .updating($pressing) { current, state, _ in state = current }
                            .onEnded { _ in stickerOffset = .zero; stickerScale = 1; stickerAngle = .zero }
                    )
            }
            .frame(maxHeight: .infinity)

            Text(lastTap)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(colors, id: \.self) { c in
                        Circle()
                            .fill(c)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if c == color {
                                    Circle().strokeBorder(.white, lineWidth: 3).matchedGeometryEffect(id: "ring", in: palette)
                                }
                            }
                            .onTapGesture { withAnimation(.snappy) { color = c } }
                            .accessibilityLabel("Color")
                    }
                    Button("Undo", systemImage: "arrow.uturn.backward") {
                        if !strokes.isEmpty { strokes.removeLast() }
                    }
                    .labelStyle(.iconOnly)
                    .padding(10)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .keyframeAnimator(initialValue: Bounce(), trigger: stamps) { content, value in
                content.scaleEffect(value.scale).offset(y: value.lift)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1.08, duration: 0.15)
                    SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
                }
                KeyframeTrack(\.lift) {
                    LinearKeyframe(-6, duration: 0.15)
                    CubicKeyframe(0, duration: 0.3)
                }
            }

            Slider(value: $width, in: 2...20) { Text("Width") }
        }
        .padding()
    }

    func path(_ points: [CGPoint]) -> Path {
        Path { p in
            guard let first = points.first else { return }
            p.move(to: first)
            for point in points.dropFirst() { p.addLine(to: point) }
        }
    }
}
