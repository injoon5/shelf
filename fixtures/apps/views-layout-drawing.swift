// Name: Steps
// Icon: chart.bar.fill
// Tint: mint
// Covers: Layout, Drawing, Charts

import SwiftUI
import Charts

struct Day: Identifiable {
    let id = UUID()
    var name: String
    var steps: Int
}

struct Ring: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * progress),
                    clockwise: false)
        return path
    }
}

struct Peak: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.midY))
            p.closeSubpath()
        }
    }
}

struct ContentView: View {
    @State private var days = [
        Day(name: "Mon", steps: 6200),
        Day(name: "Tue", steps: 8100),
        Day(name: "Wed", steps: 4300),
        Day(name: "Thu", steps: 10400),
        Day(name: "Fri", steps: 7600),
    ]
    @State private var goal = 8000
    @State private var showDetails = false
    @State private var useLine = false

    var best: Day? { days.max { $0.steps < $1.steps } }
    var progress: Double { min(Double(days.last?.steps ?? 0) / Double(goal), 1) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        Ring(progress: 1)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 14)
                        Ring(progress: progress)
                            .stroke(Color.mint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        VStack {
                            Text("\(Int(progress * 100))%").font(.title.bold())
                            Text("of goal").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 160, height: 160)
                    .animation(.easeInOut, value: progress)

                    Chart {
                        ForEach(days) { day in
                            if useLine {
                                LineMark(x: .value("Day", day.name), y: .value("Steps", day.steps))
                                PointMark(x: .value("Day", day.name), y: .value("Steps", day.steps))
                            } else {
                                BarMark(x: .value("Day", day.name), y: .value("Steps", day.steps))
                                    .foregroundStyle(day.steps >= goal ? Color.mint : Color.gray)
                            }
                        }
                        RuleMark(y: .value("Goal", goal))
                            .foregroundStyle(.red)
                    }
                    .frame(height: 200)
                    .animation(.default, value: useLine)

                    Toggle("Line chart", isOn: $useLine)

                    HStack {
                        Chart {
                            ForEach(days) { day in
                                SectorMark(angle: .value("Steps", day.steps), innerRadius: .ratio(0.6))
                                    .foregroundStyle(by: .value("Day", day.name))
                            }
                        }
                        Chart {
                            ForEach(days) { day in
                                AreaMark(x: .value("Day", day.name), y: .value("Steps", day.steps))
                                RectangleMark(x: .value("Day", day.name), y: .value("Steps", day.steps), height: 4)
                            }
                        }
                    }
                    .frame(height: 120)

                    HStack(spacing: 24) {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.mint, lineWidth: 6)
                            .rotationEffect(.degrees(-90))
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.mint.opacity(0.3))
                        Capsule()
                            .stroke(Color.secondary, lineWidth: 2)
                    }
                    .frame(height: 44)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Text("Best").foregroundStyle(.secondary)
                            Text(best?.name ?? "—")
                        }
                        GridRow {
                            Text("Total").foregroundStyle(.secondary)
                            Text("\(days.reduce(0) { $0 + $1.steps })")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 12) {
                        ForEach(days) { day in
                            VStack {
                                Peak()
                                    .fill(day.steps >= goal ? Color.mint : Color.orange)
                                    .frame(width: 30, height: 20)
                                Text(day.name).font(.caption)
                            }
                            .padding(8)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(days) { day in
                                Capsule()
                                    .fill(Color.mint.opacity(0.6))
                                    .frame(width: (geo.size.width - 8) / CGFloat(days.count),
                                           height: 40 * Double(day.steps) / 10400)
                            }
                        }
                    }
                    .frame(height: 40)

                    Button(showDetails ? "Hide Details" : "Show Details") {
                        withAnimation(.spring) { showDetails.toggle() }
                    }
                    if showDetails {
                        Text("Walk \(max(goal - (days.last?.steps ?? 0), 0)) more steps today.")
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Button("Add Walk") {
                        withAnimation {
                            days[days.count - 1].steps += 1000
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Steps")
        }
    }
}
