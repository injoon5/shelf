// Name: Terrain
// Icon: mountain.2
// Tint: green
// Covers: Chart3D

import SwiftUI
import Charts

struct Peak: Identifiable {
    let id = UUID()
    let name: String
    let x: Double
    let height: Double
    let z: Double
    let kind: String
}

struct ContentView: View {
    @State private var ripple = 1.5
    @State private var pose: Chart3DPose = .default
    @State private var perspective = true
    @State private var showPeaks = true
    @State private var depth: Double? = nil

    let peaks = [
        Peak(name: "North", x: -1.5, height: 1.2, z: -1.0, kind: "Summit"),
        Peak(name: "Ridge", x: 0.5, height: 0.8, z: 1.5, kind: "Ridge"),
        Peak(name: "Saddle", x: 1.8, height: 0.2, z: -1.8, kind: "Pass"),
        Peak(name: "Spire", x: -0.4, height: 1.6, z: 0.3, kind: "Summit"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Chart3D {
                        SurfacePlot(x: "East", y: "Height", z: "North") { [ripple] x, z in
                            sin(ripple * x) * cos(ripple * z) * 0.8
                        }
                        .foregroundStyle(.heightBased)
                        .roughness(0.4)

                        if showPeaks {
                            ForEach(peaks) { peak in
                                PointMark(
                                    x: .value("East", peak.x),
                                    y: .value("Height", peak.height),
                                    z: .value("North", peak.z)
                                )
                                .foregroundStyle(by: .value("Kind", peak.kind))
                                .symbol(.sphere)
                                .symbolSize(0.06)
                                .metalness(0.2)
                            }
                        }
                    }
                    .chart3DPose($pose)
                    .chart3DCameraProjection(perspective ? .perspective : .orthographic)
                    .chartXScale(domain: -2...2)
                    .chartZScale(domain: -2...2)
                    .chartZAxisLabel("North")
                    .chartZSelection(value: $depth)
                    .frame(height: 320)
                }

                Section("View") {
                    HStack {
                        Text("Turned")
                        Spacer()
                        Text("\(Int(pose.azimuth.degrees))°")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Picker("Angle", selection: Binding(
                        get: { pose == .front ? 1 : pose == .top ? 2 : 0 },
                        set: { pose = $0 == 1 ? .front : $0 == 2 ? .top : .default }
                    )) {
                        Text("Default").tag(0)
                        Text("Front").tag(1)
                        Text("Top").tag(2)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Perspective", isOn: $perspective)
                    Toggle("Peaks", isOn: $showPeaks)
                }

                Section("Terrain") {
                    LabeledContent("Ripple", value: ripple, format: .number.precision(.fractionLength(1)))
                    Slider(value: $ripple, in: 0.5...3)
                    if let depth {
                        LabeledContent("Selected depth", value: depth, format: .number.precision(.fractionLength(2)))
                    }
                }
            }
            .navigationTitle("Terrain")
        }
    }
}
