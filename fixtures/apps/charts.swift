// Name: Step Charts
// Icon: chart.xyaxis.line
// Tint: green
// Covers: Charts

import SwiftUI
import Charts

struct Day: Identifiable {
    let id = UUID()
    let name: String
    let steps: Int
    let goal: Int
    let kind: String
}

struct ContentView: View {
    @State private var selectedDay: String?
    @State private var selectedAngle: Int?
    @State private var amplitude = 1.0

    let days = [
        Day(name: "Mon", steps: 6200, goal: 8000, kind: "Walk"), Day(name: "Tue", steps: 9100, goal: 8000, kind: "Run"),
        Day(name: "Wed", steps: 4300, goal: 8000, kind: "Walk"), Day(name: "Thu", steps: 10400, goal: 8000, kind: "Run"),
        Day(name: "Fri", steps: 7800, goal: 8000, kind: "Walk"), Day(name: "Sat", steps: 12000, goal: 8000, kind: "Hike"),
        Day(name: "Sun", steps: 3100, goal: 8000, kind: "Walk"),
    ]

    var selected: Day? { days.first { $0.name == selectedDay } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(selected.map { "\($0.name): \($0.steps) steps" } ?? "Tap a bar")
                    .font(.headline)
                Chart(days) { day in
                    BarMark(x: .value("Day", day.name), y: .value("Steps", day.steps))
                        .foregroundStyle(by: .value("Kind", day.kind))
                        .cornerRadius(6)
                        .opacity(selectedDay == nil || selectedDay == day.name ? 1 : 0.4)
                        .annotation(position: .top, spacing: 2) {
                            if day.name == selectedDay {
                                Text("\(day.steps)").font(.caption2.bold())
                            }
                        }
                    RuleMark(y: .value("Goal", day.goal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(.secondary)
                }
                .chartXSelection(value: $selectedDay)
                .chartForegroundStyleScale(domain: ["Walk", "Run", "Hike"], range: [Color.green, Color.orange, Color.purple])
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartXAxisLabel("Day", position: .bottom)
                .chartLegend(position: .bottom, alignment: .center)
                .frame(height: 220)

                Chart {
                    LinePlot(x: "x", y: "y", domain: 0...12) { x in amplitude * sin(x) }
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                    AreaPlot(x: "x", y: "y", domain: 0...12) { x in amplitude * sin(x) * 0.5 }
                        .foregroundStyle(.blue.opacity(0.2))
                    PointMark(x: .value("x", 1.57), y: .value("y", amplitude))
                        .symbol(.diamond)
                        .symbolSize(80)
                }
                .chartXScale(domain: 0...12)
                .chartYScale(domain: -2...2)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: 6)
                .frame(height: 180)
                Slider(value: $amplitude, in: 0.2...2) { Text("Amplitude") }

                Chart(days) { day in
                    SectorMark(angle: .value("Steps", day.steps), innerRadius: .ratio(0.6), angularInset: 2)
                        .foregroundStyle(by: .value("Day", day.name))
                        .opacity(selectedAngle == nil ? 1 : 0.8)
                }
                .chartAngleSelection(value: $selectedAngle)
                .chartLegend(.hidden)
                .frame(height: 200)

                Chart {
                    ForEach(days) { day in
                        LineMark(x: .value("Day", day.name), y: .value("Steps", day.steps))
                        PointMark(x: .value("Day", day.name), y: .value("Steps", day.steps))
                            .symbolSize(30)
                    }
                    .foregroundStyle(.green)
                    RectangleMark(xStart: .value("From", "Mon"), xEnd: .value("To", "Wed"), yStart: .value("Low", 0), yEnd: .value("High", 13000))
                        .foregroundStyle(.gray.opacity(0.1))
                }
                .chartPlotStyle { plot in
                    plot.background(.green.opacity(0.05))
                }
                .frame(height: 160)
            }
            .padding()
        }
    }
}
