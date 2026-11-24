import Foundation
@testable import Kiln
import SwiftUI
import Testing
import UIKit
@testable import Shelf

/// Round 3B (plan §4.0, §4.5, §4.6): Shelf's ledger answering Kiln's motion
/// and location bridges, end to end. An app switched off in Settings ›
/// Permissions gets what iOS gives a refused app; the first request shows
/// Shelf's sheet, then iOS's prompt, and is remembered; closing the card
/// takes a sheet still up down. The sensors are Kiln's fakes.
@MainActor
@Suite(.serialized)
struct SensorPermissionTests {
    /// What the app checks, then does: its answers, joined.
    static let probe = """
    import SwiftUI
    import CoreMotion
    import CoreLocation

    func main() async -> String {
        var out: [String] = []
        out.append("location \\(CLLocationManager().authorizationStatus == .authorizedWhenInUse ? "allowed" : CLLocationManager().authorizationStatus == .denied ? "denied" : "not asked")")
        out.append("motion \\(CMPedometer.authorizationStatus() == .authorized ? "allowed" : CMPedometer.authorizationStatus() == .denied ? "denied" : "not asked")")
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationRequestInProgress { continue }
                out.append(update.authorizationDenied ? "update denied" : update.location != nil ? "update located" : "update empty")
                break
            }
        } catch { out.append("threw") }
        var pedometer = ""
        CMPedometer().queryPedometerData(from: Date().addingTimeInterval(-3600), to: Date()) { data, error in
            if let error = error as NSError? { pedometer = "pedometer \\(error.code)" } else { pedometer = "pedometer \\(data?.numberOfSteps.intValue ?? -1)" }
        }
        var n = 0
        while pedometer.isEmpty && n < 100 { try? await Task.sleep(for: .milliseconds(20)); n += 1 }
        out.append(pedometer)
        return out.joined(separator: ", ")
    }

    struct ContentView: View { var body: some View { Text("x") } }
    """

    /// Runs the probe as an installed app's real run, with fakes for sensors.
    static func run(_ app: AppMeta, _ permissions: any AppPermissions) async throws -> (String?, AppRun) {
        let host = AppHost(data: AppData(root: temporaryFolder(), api: { nil }),
                           defaults: AppDefaults(legacy: .standard, prefix: "shelf-tests.\(UUID().uuidString)."),
                           files: AppFiles(root: temporaryFolder()))
        defer { host.defaults.removeAll() }
        let context = RunContext.installed(app, session: DBSession(slug: app.slug), permissions: permissions, host: host)
        context.provide(KilnFakeMotion.walking())
        context.provide(KilnFakeLocation.applePark())
        let run = AppRun(context: context, permissions: permissions)
        let compiled = try KilnEngine.compile(probe, headless: false, context: context)
        let main = try #require(compiled.interp.functions["main"]?.first)
        let task = compiled.interp.startTask(KFunction(.user(main, compiled.interp.globalEnv, nil)), [], parent: nil, reportsErrors: true)
        let result = await task.completion()
        #expect(compiled.interp.errors.isEmpty, "\(compiled.interp.errors)")
        if case .value(let v) = result { return (v.asString, run) }
        return (nil, run)
    }

    @Test func anAppSwitchedOffGetsWhatIOSGivesARefusedApp() async throws {
        let h = GateHarness(system: [.location: .allowed, .motion: .allowed])
        defer { h.cleanUp() }
        h.gate.setAllowed(false, .location, for: runTracker.slug, name: runTracker.name)
        h.gate.setAllowed(false, .motion, for: runTracker.slug, name: runTracker.name)
        let (out, run) = try await Self.run(runTracker, h.gate.forApp(runTracker))
        defer { run.tearDown() }
        #expect(out == "location denied, motion denied, update denied, pedometer 105")
        #expect(h.asker.asks.isEmpty, "a switched-off app is never asked")
        #expect(h.system.asked.isEmpty)
    }

    @Test func theFirstRequestShowsShelfsSheetThenIOSsAndIsRemembered() async throws {
        let h = GateHarness(system: [:], answerWhenAsked: .allowed, choices: [.allow, .allow])
        defer { h.cleanUp() }
        let (out, run) = try await Self.run(runTracker, h.gate.forApp(runTracker))
        run.tearDown()
        #expect(out == "location not asked, motion not asked, update located, pedometer 450")
        #expect(h.asker.asks.map(\.capability) == [.location, .motion])
        #expect(h.asker.asks.allSatisfy { $0.systemWillAsk && $0.name == "Run Tracker" })
        #expect(h.system.asked == [.location, .motion])
        #expect(h.reread().answer(.location, for: runTracker.slug) == .allowed)
        #expect(h.reread().answer(.motion, for: runTracker.slug) == .allowed)

        // The next open: allowed, with no sheet and no prompt.
        let (again, second) = try await Self.run(runTracker, h.gate.forApp(runTracker))
        second.tearDown()
        #expect(again == "location allowed, motion allowed, update located, pedometer 450")
        #expect(h.asker.asks.count == 2)
    }

    @Test func dontAllowIsRememberedAndOnlyForThatApp() async throws {
        let h = GateHarness(system: [.location: .allowed, .motion: .allowed], choices: [.deny, .deny])
        defer { h.cleanUp() }
        let (out, run) = try await Self.run(runTracker, h.gate.forApp(runTracker))
        run.tearDown()
        #expect(out == "location not asked, motion not asked, update denied, pedometer 105")
        #expect(h.reread().answer(.location, for: runTracker.slug) == .denied)
        // Another app hasn't been asked: its first request shows the sheet.
        h.asker.choices = [.allow, .allow]
        let (other, second) = try await Self.run(habits, h.gate.forApp(habits))
        second.tearDown()
        #expect(other == "location not asked, motion not asked, update located, pedometer 450")
        #expect(h.asker.asks.map(\.slug) == [runTracker.slug, runTracker.slug, habits.slug, habits.slug])
    }

    @Test func switchingAnAppBackOnInSettingsAllowsIt() async throws {
        let h = GateHarness(system: [.location: .allowed, .motion: .allowed])
        defer { h.cleanUp() }
        h.gate.setAllowed(false, .location, for: runTracker.slug, name: runTracker.name)
        h.gate.setAllowed(true, .location, for: runTracker.slug, name: runTracker.name)
        h.gate.setAllowed(true, .motion, for: runTracker.slug, name: runTracker.name)
        let (out, run) = try await Self.run(runTracker, h.gate.forApp(runTracker))
        run.tearDown()
        #expect(out == "location allowed, motion allowed, update located, pedometer 450")
    }

    @Test func iOSRefusingShelfRefusesEveryApp() async throws {
        let h = GateHarness(system: [.location: .denied, .motion: .restricted])
        defer { h.cleanUp() }
        h.gate.setAllowed(true, .location, for: runTracker.slug, name: runTracker.name)
        h.gate.setAllowed(true, .motion, for: runTracker.slug, name: runTracker.name)
        let (out, run) = try await Self.run(runTracker, h.gate.forApp(runTracker))
        run.tearDown()
        #expect(out == "location denied, motion denied, update denied, pedometer 105")
    }

    /// Closing the card while Shelf's sheet is up takes it down, records
    /// nothing, and the app's waiting loop ends.
    @Test func closingTheCardTakesASheetStillUpDown() async throws {
        let h = GateHarness(system: [.location: .allowed], choices: [.allow])
        defer { h.cleanUp() }
        h.asker.holds = true
        let permissions = h.gate.forApp(runTracker)
        let host = AppHost(data: AppData(root: temporaryFolder(), api: { nil }),
                           defaults: AppDefaults(legacy: .standard, prefix: "shelf-tests.\(UUID().uuidString)."),
                           files: AppFiles(root: temporaryFolder()))
        defer { host.defaults.removeAll() }
        let context = RunContext.installed(runTracker, session: DBSession(slug: "t"), permissions: permissions, host: host)
        context.provide(KilnFakeLocation.applePark())
        let run = AppRun(context: context, permissions: permissions)
        run.result = Kiln.run("""
        import SwiftUI
        import CoreLocation
        struct ContentView: View {
            @State private var seen = 0
            var body: some View {
                Text("\\(seen)").task {
                    do { for try await _ in CLLocationUpdate.liveUpdates() { seen += 1 } } catch {}
                }
            }
        }
        """, context: context)
        let view = try #require(run.result?.view)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        defer { window.isHidden = true }
        let deadline = ContinuousClock.now + .seconds(3)
        while !h.asker.isShowing, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(h.asker.isShowing, "the sheet should be up")
        run.tearDown()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!h.asker.isShowing)
        #expect(h.reread().answer(.location, for: runTracker.slug) == nil)
        #expect(run.result?.activeTaskCount == 0)
    }

    /// The simulator has no motion sensors: Shelf gives its apps Kiln's fake,
    /// and Motion & Fitness counts as allowed for Shelf there.
    @Test func theSimulatorGetsFakeMotion() throws {
        #if targetEnvironment(simulator)
        let host = AppHost(data: AppData(root: temporaryFolder(), api: { nil }),
                           defaults: AppDefaults(legacy: .standard, prefix: "shelf-tests.\(UUID().uuidString)."),
                           files: AppFiles(root: temporaryFolder()))
        defer { host.defaults.removeAll() }
        let context = RunContext.installed(runTracker, session: DBSession(slug: "t"), permissions: StubAppPermissions(), host: host)
        defer { context.tearDown() }
        #expect(context.provided(KilnFakeMotion.self) != nil)
        #expect(DeviceSystemPermissions().status(.motion) == .allowed)
        #endif
    }
}
