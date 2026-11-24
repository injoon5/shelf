//
//  Chart3DBridgeTests.swift
//  KilnTests
//
//  PLAN.md §3.7: Chart3D with 3D marks and SurfacePlot, the chart's pose
//  and projection, and SurfacePlot's sampler: the app's function runs on
//  a capped grid, never once per Swift Charts sample.
//

import XCTest
import SwiftUI
@testable import Kiln

@MainActor
final class Chart3DBridgeTests: XCTestCase {
    static let app = """
    import SwiftUI
    import Charts

    struct Sample: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
        let z: Double
        let kind: String
    }

    var calls = 0

    struct ContentView: View {
        @State private var pose: Chart3DPose = .front
        @State private var frequency = 2.0
        @State private var depth: Double? = nil
        let samples = (0..<20).map { i in
            Sample(x: Double(i % 5), y: Double(i) / 4, z: Double(i / 5), kind: i % 2 == 0 ? "Even" : "Odd")
        }

        var body: some View {
            VStack {
                Chart3D(samples) { s in
                    PointMark(x: .value("X", s.x), y: .value("Y", s.y), z: .value("Z", s.z))
                        .foregroundStyle(by: .value("Kind", s.kind))
                        .symbol(.cube)
                        .symbolSize(0.04)
                        .metalness(0.3)
                        .roughness(0.6)
                        .symbolRotation(Rotation3D(angle: .degrees(45), axis: .y))
                }
                .chart3DPose($pose)
                .chart3DCameraProjection(.perspective)
                .chartZAxisLabel("Depth")
                .chartZScale(domain: 0...4)
                .chartZSelection(value: $depth)

                Chart3D {
                    SurfacePlot(x: "X", y: "Height", z: "Z") { x, z in
                        calls += 1
                        return sin(frequency * x) * cos(frequency * z)
                    }
                    .foregroundStyle(.heightBased)
                    PointMark(x: .value("X", 0.0), y: .value("Y", 1.0), z: .value("Z", 0.0))
                        .foregroundStyle(.red)
                }
                .chartXScale(domain: -3...3)
                .chartZScale(domain: -3...3)
                .chart3DPose(Chart3DPose(azimuth: .degrees(30), inclination: .degrees(20)))
                .chartZAxis(.hidden)
                Text("\\(Int(pose.azimuth.degrees))")
                Button("Top") { pose = .top }
                Slider(value: $frequency, in: 1...4)
            }
        }
    }
    """

    func testTheChartAppChecksValidatesAndShows() throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { throw XCTSkip("Chart3D needs macOS 26") }
        XCTAssertEqual(BridgeTest.problems(Self.app), [])
    }

    func testTheMarksPickTheir3DForms() throws {
        let bound = try BridgeTest.bound(Self.app)
        XCTAssertTrue(bound.contains("PointMark(x:y:z:)"), "\(bound)")
        XCTAssertTrue(bound.contains("SurfacePlot(x:y:z:function:)"), "\(bound)")
    }

    /// Shown, Swift Charts asks for 2 × 256 × 256 samples; the app's
    /// function runs only on the sampler's grid.
    func testTheSurfaceFunctionRunsOnACappedGrid() throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { throw XCTSkip("Chart3D needs macOS 26") }
        let context = KilnContext.stub()
        let result = Kiln.run(Self.app, context: context)
        XCTAssertEqual(result.errors, [])
        let view = try XCTUnwrap(result.view)
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        let host = NSHostingView(rootView: view.frame(width: 390, height: 844))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 844), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<20 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        window.contentView = nil
        #endif
        let calls = try XCTUnwrap(result.interp?.globalEnv.lookup("calls")?.value.asInt)
        let side = KSurfaceSampler.side
        XCTAssertGreaterThanOrEqual(calls, side * side, "the surface was never sampled")
        XCTAssertLessThanOrEqual(calls, 3 * side * side, "the app's function ran per Swift Charts sample")
        result.tearDown()
    }

    func testTheSamplerInterpolatesAndFollowsTheDomain() throws {
        let c = try KilnEngine.compile("""
        var calls = 0
        func plane(_ x: Double, _ z: Double) -> Double { calls += 1; return 2 * x + z }
        struct ContentView: View { var body: some View { Text("x") } }
        """, headless: true)
        let f = KFunction(.user(try XCTUnwrap(c.interp.functions["plane"]?.first), c.interp.globalEnv, nil))
        var redraws = 0, appRedraws = 0
        c.interp.onGlobalChange = { appRedraws += 1 }
        let sampler = KSurfaceSampler { redraws += 1 }
        sampler.use(f, c.interp, hint: (-1, 1, -1, 1))
        let side = KSurfaceSampler.side
        XCTAssertEqual(c.interp.globalEnv.lookup("calls")?.value.asInt, side * side)
        // `calls += 1` while Swift Charts draws doesn't draw the app again.
        XCTAssertEqual(appRedraws, 0)
        XCTAssertEqual(sampler.value(0.5, 0.25), 1.25, accuracy: 1e-9)
        XCTAssertEqual(sampler.value(-1, -1), -3, accuracy: 1e-9)
        // The same function again isn't sampled again.
        sampler.use(f, c.interp, hint: (-1, 1, -1, 1))
        XCTAssertEqual(c.interp.globalEnv.lookup("calls")?.value.asInt, side * side)
        // Swift Charts asks about 0…10: the grid follows, and the chart redraws.
        for x in stride(from: 0.0, through: 10, by: 0.5) { _ = sampler.value(x, x) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(redraws, 1)
        XCTAssertEqual(c.interp.globalEnv.lookup("calls")?.value.asInt, 2 * side * side)
        XCTAssertEqual(sampler.value(8, 4), 20, accuracy: 1e-9)
    }

    /// What Swift Charts would stop the app for is an error with the chart's line.
    func testMarksSwiftChartsCantDrawAreErrorsNotCrashes() throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { throw XCTSkip("Chart3D needs macOS 26") }
        for mark in [#"RuleMark(x: .value("X", 0.0), y: .value("Y", 0.0), z: .value("Z", 1.0))"#,
                     #"RectangleMark(x: .value("X", 0.0), y: .value("Y", 0.0), z: .value("Z", 1.0))"#,
                     #"PointMark(x: .value("X", "a"), y: .value("Y", 0.0), z: .value("Z", 1.0))"#] {
            let errors = BridgeTest.shownErrors(BridgeTest.app("Chart3D {\n \(mark)\n }"))
            XCTAssertEqual(errors.count, 1, "\(mark): \(errors)")
            XCTAssertEqual(errors.first?.line, 6, "\(errors)")
            XCTAssertTrue(errors.first?.message.hasPrefix("Chart3D(content:): ") == true, "\(errors)")
        }
    }

    func testPoseValues() throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { throw XCTSkip("Chart3D needs macOS 26") }
        let c = try KilnEngine.compile("""
        import Charts
        func main() {
            let pose = Chart3DPose(azimuth: .degrees(30), inclination: .degrees(15))
            let front: Chart3DPose = .front
            print(Int(pose.azimuth.degrees.rounded()), Int(pose.inclination.degrees.rounded()), front == .front, front == pose)
            print(Angle2D(degrees: 180).radians > 3.14)
        }
        struct ContentView: View { var body: some View { Text("x") } }
        """, headless: true)
        c.interp.perform(KFunction(.user(try XCTUnwrap(c.interp.functions["main"]?.first), c.interp.globalEnv, nil)))
        XCTAssertEqual(c.interp.errors, [])
        XCTAssertEqual(c.interp.console, "30 15 true false\ntrue\n")
    }
}
