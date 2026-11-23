import Foundation
import Testing
@testable import Shelf

/// Shelf's sheet, answered by the test: a queue of choices, and every ask
/// recorded. With `holds`, each sheet stays up until `answerNext` is called,
/// so a test can do things while it's showing.
@MainActor
final class ScriptedAsker: PermissionAsker {
    struct Ask: Equatable {
        var capability: Capability
        var slug: String
        var name: String
        var systemWillAsk: Bool
    }

    var choices: [PermissionChoice]
    var holds = false
    private(set) var asks: [Ask] = []
    private(set) var showing = 0
    private(set) var mostShowingAtOnce = 0
    private var waiting: [(slug: String, answer: CheckedContinuation<PermissionChoice, Never>)] = []

    init(_ choices: [PermissionChoice] = []) {
        self.choices = choices
    }

    func ask(_ capability: Capability, for app: AppMeta, systemWillAsk: Bool) async -> PermissionChoice {
        asks.append(Ask(capability: capability, slug: app.slug, name: app.name, systemWillAsk: systemWillAsk))
        showing += 1
        mostShowingAtOnce = max(mostShowingAtOnce, showing)
        defer { showing -= 1 }
        if holds {
            return await withCheckedContinuation { waiting.append((app.slug, $0)) }
        }
        await Task.yield()
        return choices.isEmpty ? .dismissed : choices.removeFirst()
    }

    /// Answers the sheet that's up with the next choice.
    func answerNext() {
        guard !waiting.isEmpty else { return }
        let sheet = waiting.removeFirst()
        sheet.answer.resume(returning: choices.isEmpty ? .dismissed : choices.removeFirst())
    }

    var isShowing: Bool { !waiting.isEmpty }

    func dismiss(for slug: String) {
        while let i = waiting.firstIndex(where: { $0.slug == slug }) {
            waiting.remove(at: i).answer.resume(returning: .dismissed)
        }
    }
}

@MainActor
struct GateHarness {
    let folder = temporaryFolder()
    let system: FixedSystemPermissions
    let asker: ScriptedAsker
    let gate: PermissionGate

    var file: URL { folder.appending(path: "permissions.json") }

    init(system: [Capability: SystemPermissionStatus] = [:], answerWhenAsked: SystemPermissionStatus = .allowed,
         choices: [PermissionChoice] = []) {
        self.system = FixedSystemPermissions(system, answerWhenAsked: answerWhenAsked)
        asker = ScriptedAsker(choices)
        gate = PermissionGate(ledger: PermissionLedger(file: folder.appending(path: "permissions.json")),
                              system: self.system, asker: asker)
    }

    /// The ledger as the next launch would read it.
    func reread() -> PermissionLedger { PermissionLedger(file: file) }

    func cleanUp() { try? FileManager.default.removeItem(at: folder) }
}

let runTracker = AppMeta(slug: "run-tracker", name: "Run Tracker", icon: "figure.run", tint: .red)
let habits = AppMeta(slug: "habits", name: "Habits", icon: "checkmark.circle.fill", tint: .green)

// MARK: - The ledger

@MainActor
@Suite struct PermissionLedgerTests {
    @Test func theLedgerLivesInApplicationSupport() {
        #expect(PermissionLedger.standardFile == URL.applicationSupportDirectory.appending(path: "permissions.json"))
    }

    @Test func answersSurviveARelaunch() {
        let h = GateHarness()
        defer { h.cleanUp() }
        h.gate.ledger.set(.allowed, .location, for: "run-tracker", name: "Run Tracker")
        h.gate.ledger.set(.denied, .camera, for: "run-tracker", name: "Run Tracker")
        h.gate.ledger.set(.allowed, .camera, for: "habits", name: "Habits")

        let again = h.reread()
        #expect(again.answer(.location, for: "run-tracker") == .allowed)
        #expect(again.answer(.camera, for: "run-tracker") == .denied)
        #expect(again.answer(.microphone, for: "run-tracker") == nil)
        #expect(again.answer(.camera, for: "habits") == .allowed)
        #expect(again.entries["run-tracker"]?.name == "Run Tracker")
    }

    /// Not asked, allowed, denied, and back to not asked: every way between them.
    @Test func everyStateMovesToEveryOther() {
        let h = GateHarness()
        defer { h.cleanUp() }
        let ledger = h.gate.ledger
        let states: [PermissionLedger.Answer?] = [nil, .allowed, .denied]
        for from in states {
            for to in states {
                ledger.set(from, .motion, for: "habits", name: "Habits")
                #expect(h.reread().answer(.motion, for: "habits") == from)
                ledger.set(to, .motion, for: "habits", name: "Habits")
                #expect(ledger.answer(.motion, for: "habits") == to)
                #expect(h.reread().answer(.motion, for: "habits") == to)
            }
        }
    }

    /// An app with no answers left isn't kept, and nor is an empty file.
    @Test func forgettingTheLastAnswerForgetsTheApp() {
        let h = GateHarness()
        defer { h.cleanUp() }
        h.gate.ledger.set(.allowed, .camera, for: "habits", name: "Habits")
        h.gate.ledger.set(nil, .camera, for: "habits", name: "Habits")
        #expect(h.gate.ledger.entries["habits"] == nil)
        #expect(!FileManager.default.fileExists(atPath: h.file.path(percentEncoded: false)))
    }

    /// A newer Shelf's capabilities and answers, and a newer version
    /// number, are kept through this build's writes.
    @Test func whatANewerBuildWroteSurvives() throws {
        let h = GateHarness()
        defer { h.cleanUp() }
        try FileManager.default.createDirectory(at: h.folder, withIntermediateDirectories: true)
        let newer = """
        {"version": 2, "future": true, "apps": {
          "habits": {"name": "Habits", "answers": {"bluetooth": "allowed", "location": "limited", "camera": "denied"}, "extra": 1}
        }}
        """
        try Data(newer.utf8).write(to: h.file)

        let ledger = h.reread()
        #expect(ledger.answer(.camera, for: "habits") == .denied)
        // An answer this build doesn't know is "not asked": the app asks again.
        #expect(ledger.answer(.location, for: "habits") == nil)

        ledger.set(.allowed, .microphone, for: "habits", name: "Habits")
        let raw = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: h.file)) as? [String: Any])
        let answers = try #require(((raw["apps"] as? [String: Any])?["habits"] as? [String: Any])?["answers"] as? [String: String])
        #expect(answers == ["bluetooth": "allowed", "location": "limited", "camera": "denied", "microphone": "allowed"])
        #expect(raw["version"] as? Int == PermissionLedger.version)
    }

    @Test(arguments: ["", "not json", "[]", #"{"apps": 3}"#, #"{"version": 1}"#])
    func anUnreadableFileIsEmpty(contents: String) throws {
        let h = GateHarness()
        defer { h.cleanUp() }
        try FileManager.default.createDirectory(at: h.folder, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: h.file)
        #expect(h.reread().entries.isEmpty)
    }

    @Test func aMissingNameIsTheSlug() throws {
        let h = GateHarness()
        defer { h.cleanUp() }
        try FileManager.default.createDirectory(at: h.folder, withIntermediateDirectories: true)
        try Data(#"{"version": 1, "apps": {"habits": {"answers": {"camera": "allowed"}}, "empty": {"name": "E"}}}"#.utf8).write(to: h.file)
        let ledger = h.reread()
        #expect(ledger.entries["habits"]?.name == "habits")
        #expect(ledger.entries["empty"] == nil)
    }

    @Test func removingIsSafeTwiceAndTouchesNoOtherApp() {
        let h = GateHarness()
        defer { h.cleanUp() }
        h.gate.ledger.set(.allowed, .camera, for: "habits", name: "Habits")
        h.gate.ledger.set(.allowed, .camera, for: "habits-2", name: "Habits 2")
        h.gate.ledger.remove("habits")
        h.gate.ledger.remove("habits")
        h.gate.ledger.remove("never-asked")
        #expect(h.reread().answer(.camera, for: "habits") == nil)
        #expect(h.reread().answer(.camera, for: "habits-2") == .allowed)
    }

    @Test func removeAllTakesTheFile() {
        let h = GateHarness()
        defer { h.cleanUp() }
        h.gate.ledger.set(.allowed, .camera, for: "habits", name: "Habits")
        h.gate.ledger.removeAll()
        #expect(h.gate.ledger.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: h.file.path(percentEncoded: false)))
    }

    /// Settings lists apps by name, and never a preview.
    @Test func appsForACapabilityAreByNameWithoutPreviews() {
        let ledger = PermissionLedger(file: nil)
        ledger.set(.allowed, .location, for: "zz", name: "Run Tracker")
        ledger.set(.denied, .location, for: "aa", name: "Walks")
        ledger.set(.allowed, .location, for: "habits", name: "habits")
        ledger.set(.allowed, .location, for: "preview:1", name: "New App")
        ledger.set(.allowed, .camera, for: "cam", name: "Camera App")
        #expect(ledger.apps(for: .location).map(\.slug) == ["habits", "zz", "aa"])
        #expect(ledger.apps(for: .location).map(\.answer) == [.allowed, .allowed, .denied])
    }

    /// A preview never outlives its sheet: one left by a quit is dropped.
    @Test func aLeftoverPreviewIsDroppedAtLaunch() {
        let h = GateHarness()
        defer { h.cleanUp() }
        h.gate.ledger.set(.allowed, .camera, for: "preview:ABC", name: "New App")
        h.gate.ledger.set(.allowed, .camera, for: "habits", name: "Habits")
        let again = h.reread()
        #expect(again.entries.keys.sorted() == ["habits"])
        #expect(h.reread().entries.keys.sorted() == ["habits"])
    }

    @Test func movingAPreviewsAnswersKeepsTheAppsOwn() {
        let ledger = PermissionLedger(file: nil)
        ledger.set(.allowed, .camera, for: "preview:1", name: "New App")
        ledger.set(.allowed, .location, for: "preview:1", name: "New App")
        ledger.set(.denied, .location, for: "run-tracker", name: "Old")
        ledger.move(from: "preview:1", to: "run-tracker", name: "Run Tracker")
        #expect(ledger.entries["preview:1"] == nil)
        #expect(ledger.answer(.camera, for: "run-tracker") == .allowed)
        #expect(ledger.answer(.location, for: "run-tracker") == .denied)
        #expect(ledger.entries["run-tracker"]?.name == "Run Tracker")
    }
}

// MARK: - The gate

@MainActor
@Suite struct PermissionGateTests {
    /// `status` for every ledger answer under every one of iOS's.
    @Test(arguments: [
        (nil, SystemPermissionStatus.notDetermined, PermissionStatus.notAsked),
        (nil, .allowed, .notAsked),
        (nil, .denied, .denied),
        (nil, .restricted, .denied),
        (PermissionLedger.Answer.allowed, .notDetermined, .notAsked),
        (.allowed, .allowed, .allowed),
        (.allowed, .denied, .denied),
        (.allowed, .restricted, .denied),
        (.denied, .notDetermined, .denied),
        (.denied, .allowed, .denied),
        (.denied, .denied, .denied),
        (.denied, .restricted, .denied),
    ] as [(PermissionLedger.Answer?, SystemPermissionStatus, PermissionStatus)])
    func status(answer: PermissionLedger.Answer?, system: SystemPermissionStatus, expected: PermissionStatus) {
        let h = GateHarness(system: [.location: system])
        defer { h.cleanUp() }
        h.gate.ledger.set(answer, .location, for: runTracker.slug, name: runTracker.name)
        #expect(h.gate.status(.location, for: runTracker) == expected)
        #expect(h.asker.asks.isEmpty)
        #expect(h.system.asked.isEmpty)
    }

    /// The first ask: Shelf's sheet, then iOS's, and the answer kept.
    @Test func allowingAsksIOSNextAndIsKept() async {
        let h = GateHarness(choices: [.allow])
        defer { h.cleanUp() }
        #expect(await h.gate.request(.location, for: runTracker))
        #expect(h.asker.asks == [.init(capability: .location, slug: "run-tracker", name: "Run Tracker", systemWillAsk: true)])
        #expect(h.system.asked == [.location])
        #expect(h.reread().answer(.location, for: "run-tracker") == .allowed)
        #expect(h.gate.status(.location, for: runTracker) == .allowed)

        // Asked once: from now on the answer comes without a sheet.
        #expect(await h.gate.request(.location, for: runTracker))
        #expect(h.asker.asks.count == 1)
        #expect(h.system.asked.count == 1)
    }

    /// iOS already said yes for Shelf: only Shelf's sheet, which says so.
    @Test func iOSAlreadyAllowingAsksOnlyShelfs() async {
        let h = GateHarness(system: [.camera: .allowed], choices: [.allow])
        defer { h.cleanUp() }
        #expect(await h.gate.request(.camera, for: runTracker))
        #expect(h.asker.asks.map(\.systemWillAsk) == [false])
        #expect(h.system.asked.isEmpty)
    }

    /// Allowed here, refused by iOS: the app gets no, and the ledger keeps
    /// the person's yes for when iOS is turned back on.
    @Test func allowingThenIOSRefusingIsNo() async {
        let h = GateHarness(answerWhenAsked: .denied, choices: [.allow])
        defer { h.cleanUp() }
        #expect(await h.gate.request(.microphone, for: runTracker) == false)
        #expect(h.gate.ledger.answer(.microphone, for: runTracker.slug) == .allowed)
        #expect(h.gate.status(.microphone, for: runTracker) == .denied)

        h.system.statuses[.microphone] = .allowed   // turned on in iOS Settings
        #expect(h.gate.status(.microphone, for: runTracker) == .allowed)
        #expect(await h.gate.request(.microphone, for: runTracker))
        #expect(h.asker.asks.count == 1)
    }

    @Test func dontAllowIsKeptAndIOSIsNeverAsked() async {
        let h = GateHarness(choices: [.deny])
        defer { h.cleanUp() }
        #expect(await h.gate.request(.camera, for: runTracker) == false)
        #expect(h.system.asked.isEmpty)
        #expect(h.reread().answer(.camera, for: runTracker.slug) == .denied)
        #expect(await h.gate.request(.camera, for: runTracker) == false)
        #expect(h.asker.asks.count == 1)
    }

    /// A sheet that went without an answer records nothing: the app asks again.
    @Test func aDismissedSheetAsksAgainNextTime() async {
        let h = GateHarness(choices: [.dismissed, .allow])
        defer { h.cleanUp() }
        #expect(await h.gate.request(.motion, for: runTracker) == false)
        #expect(h.gate.ledger.answer(.motion, for: runTracker.slug) == nil)
        #expect(h.system.asked.isEmpty)
        #expect(await h.gate.request(.motion, for: runTracker))
        #expect(h.asker.asks.count == 2)
    }

    /// iOS refusing Shelf is no for every app, without a sheet, and without
    /// recording anything: turned back on, the app asks then.
    @Test(arguments: [SystemPermissionStatus.denied, .restricted])
    func iOSRefusingShelfIsNoWithoutASheet(system: SystemPermissionStatus) async {
        let h = GateHarness(system: [.location: system], choices: [.allow])
        defer { h.cleanUp() }
        h.gate.ledger.set(.allowed, .location, for: habits.slug, name: habits.name)
        #expect(await h.gate.request(.location, for: runTracker) == false)
        #expect(await h.gate.request(.location, for: habits) == false)
        #expect(h.asker.asks.isEmpty)
        #expect(h.system.asked.isEmpty)
        #expect(h.gate.ledger.answer(.location, for: runTracker.slug) == nil)
        #expect(h.gate.ledger.answer(.location, for: habits.slug) == .allowed)
    }

    /// Allowed, but iOS has been reset since (or never asked): iOS's prompt
    /// comes again, with no sheet of Shelf's.
    @Test func allowedButIOSNotAskedAsksOnlyIOS() async {
        let h = GateHarness(choices: [.deny])
        defer { h.cleanUp() }
        h.gate.ledger.set(.allowed, .photoLibraryAdd, for: runTracker.slug, name: runTracker.name)
        #expect(h.gate.status(.photoLibraryAdd, for: runTracker) == .notAsked)
        #expect(await h.gate.request(.photoLibraryAdd, for: runTracker))
        #expect(h.asker.asks.isEmpty)
        #expect(h.system.asked == [.photoLibraryAdd])
    }

    /// Settings › Permissions' switch: off is the API's "denied", on lets it through.
    @Test func theSettingsSwitch() async {
        let h = GateHarness(system: [.camera: .allowed], choices: [.allow])
        defer { h.cleanUp() }
        #expect(await h.gate.request(.camera, for: runTracker))

        h.gate.setAllowed(false, .camera, for: runTracker.slug, name: runTracker.name)
        #expect(h.gate.status(.camera, for: runTracker) == .denied)
        #expect(await h.gate.request(.camera, for: runTracker) == false)
        #expect(h.reread().answer(.camera, for: runTracker.slug) == .denied)

        h.gate.setAllowed(true, .camera, for: runTracker.slug, name: runTracker.name)
        #expect(await h.gate.request(.camera, for: runTracker))
        #expect(h.asker.asks.count == 1)
    }

    /// Answers belong to one app and one capability.
    @Test func answersArePerAppAndPerCapability() async {
        let h = GateHarness(choices: [.allow, .deny, .deny])
        defer { h.cleanUp() }
        #expect(await h.gate.request(.location, for: runTracker))
        #expect(await h.gate.request(.location, for: habits) == false)
        #expect(await h.gate.request(.camera, for: runTracker) == false)
        #expect(h.gate.status(.location, for: runTracker) == .allowed)
        #expect(h.gate.status(.location, for: habits) == .denied)
        #expect(h.gate.status(.camera, for: runTracker) == .denied)
        #expect(h.gate.status(.camera, for: habits) == .notAsked)
    }

    /// Two requests at once for the same thing get one sheet and one answer.
    @Test func requestsAtOnceShareASheet() async {
        let h = GateHarness(choices: [.allow])
        defer { h.cleanUp() }
        h.asker.holds = true
        async let first = h.gate.request(.location, for: runTracker)
        async let second = h.gate.request(.location, for: runTracker)
        #expect(await eventually { await MainActor.run { h.asker.isShowing } })
        h.asker.answerNext()
        #expect(await first)
        #expect(await second)
        #expect(h.asker.asks.count == 1)
    }

    /// Different requests at once: one sheet at a time, in turn.
    @Test func sheetsComeOneAtATime() async {
        let h = GateHarness(choices: [.allow, .deny])
        defer { h.cleanUp() }
        h.asker.holds = true
        async let location = h.gate.request(.location, for: runTracker)
        async let camera = h.gate.request(.camera, for: habits)
        #expect(await eventually { await MainActor.run { h.asker.isShowing } })
        h.asker.answerNext()
        #expect(await eventually { await MainActor.run { h.asker.asks.count == 2 && h.asker.isShowing } })
        h.asker.answerNext()
        let answers = await [location, camera]
        #expect(answers.filter { $0 }.count == 1)
        #expect(h.asker.mostShowingAtOnce == 1)
    }

    /// The card closes while its sheet is up: the sheet goes, nothing is kept.
    @Test func closingTheAppTakesItsSheetDown() async {
        let h = GateHarness(choices: [.allow])
        defer { h.cleanUp() }
        h.asker.holds = true
        async let answer = h.gate.request(.location, for: runTracker)
        #expect(await eventually { await MainActor.run { h.asker.isShowing } })
        h.gate.forApp(runTracker).cancelRequests()
        #expect(await answer == false)
        #expect(h.gate.ledger.answer(.location, for: runTracker.slug) == nil)
        #expect(h.system.asked.isEmpty)
    }

    /// The asking task is cancelled: the same.
    @Test func aCancelledRequestIsNo() async {
        let h = GateHarness(choices: [.allow])
        defer { h.cleanUp() }
        h.asker.holds = true
        let task = Task { await h.gate.request(.camera, for: runTracker) }
        #expect(await eventually { await MainActor.run { h.asker.isShowing } })
        task.cancel()
        #expect(await task.value == false)
        #expect(h.gate.ledger.answer(.camera, for: runTracker.slug) == nil)
    }

    /// Deleting an app while its sheet is up: the sheet goes with its answers.
    @Test func forgettingAnAppTakesItsSheetAndAnswers() async {
        let h = GateHarness(choices: [.allow])
        defer { h.cleanUp() }
        h.gate.ledger.set(.allowed, .camera, for: runTracker.slug, name: runTracker.name)
        h.asker.holds = true
        async let answer = h.gate.request(.location, for: runTracker)
        #expect(await eventually { await MainActor.run { h.asker.isShowing } })
        h.gate.forget(runTracker.slug)
        #expect(await answer == false)
        #expect(h.reread().entries[runTracker.slug] == nil)
    }

    /// The bound gate a run holds asks as its app.
    @Test func aRunsPermissionsAskAsItsApp() async {
        let h = GateHarness(choices: [.allow])
        defer { h.cleanUp() }
        let run: any AppPermissions = h.gate.forApp(habits)
        #expect(run.status(.motion) == .notAsked)
        #expect(await run.request(.motion))
        #expect(run.status(.motion) == .allowed)
        #expect(h.asker.asks.map(\.slug) == ["habits"])
    }
}

// MARK: - The stub, cleanup and the preview

@MainActor
@Suite struct PermissionPlumbingTests {
    /// What Kiln's `validate` runs with: answers, no UI, no iOS, no ledger.
    @Test func theStubAnswersWithoutAsking() async {
        let stub = StubAppPermissions()
        for capability in Capability.allCases {
            #expect(stub.status(capability) == .allowed)
            #expect(await stub.request(capability))
        }
        #expect(stub.requested == Capability.allCases)

        let refusing = StubAppPermissions([.camera: .denied], answerWhenAsked: false)
        #expect(await refusing.request(.camera) == false)
        #expect(refusing.status(.location) == .notAsked)
        #expect(await refusing.request(.location) == false)
    }

    /// Delete App, and a sync that finds an app gone, both take its answers.
    @Test func cleanupTakesAnAppsAnswers() async {
        let h = GateHarness()
        defer { h.cleanUp() }
        h.gate.ledger.set(.allowed, .camera, for: "habits", name: "Habits")
        h.gate.ledger.set(.allowed, .camera, for: "notes", name: "Notes")
        let cleanup = AppCleanup.library(cache: AppCache(root: h.folder.appending(path: "apps")),
                                         appStorage: AppStorageKeys(.standard), permissions: h.gate)
        await cleanup.remove("habits")
        await cleanup.remove("habits")
        #expect(h.reread().entries.keys.sorted() == ["notes"])
    }

    /// A new app's preview asks as itself, never as an installed app, and
    /// closing the sheet without installing forgets what it was allowed.
    @Test func aNewAppsPreviewAsksAsItselfAndIsForgotten() async {
        let h = GateHarness(choices: [.allow])
        defer { h.cleanUp() }
        let library = LibraryStore(demo: [], cache: AppCache(root: h.folder.appending(path: "apps")))
        let model = CreateModel(app: nil, source: nil)
        #expect(model.permissionSlug.hasPrefix(PermissionLedger.previewPrefix))
        #expect(model.permissionIdentity.name == "New App")
        model.paste("```swift\n// Name: Run Tracker\n// Icon: figure.run\n// Tint: red\nstruct ContentView: View {}\n```", library: library)
        #expect(model.permissionIdentity.name == "Run Tracker")
        #expect(model.permissionIdentity.tint == .red)

        let preview = model.previewPermissions(h.gate)
        #expect(await preview.request(.location))
        #expect(h.asker.asks.map(\.name) == ["Run Tracker"])
        #expect(h.gate.ledger.answer(.location, for: model.permissionSlug) == .allowed)
        #expect(h.gate.ledger.apps(for: .location).isEmpty)

        model.closed(h.gate)
        #expect(h.gate.ledger.entries.isEmpty)
    }

    /// Install carries the preview's answers to the installed app.
    @Test func installingCarriesThePreviewsAnswers() async throws {
        let h = StoreHarness()
        defer { h.cleanUp() }
        await h.store.sync()
        let model = CreateModel(app: nil, source: nil)
        model.paste("```swift\n// Name: Run Tracker\nstruct ContentView: View {}\n```", library: h.store)
        h.store.permissions.ledger.set(.allowed, .location, for: model.permissionSlug, name: "Run Tracker")

        await model.installReply(library: h.store)
        #expect(model.isFinished)
        model.closed(h.store.permissions)

        let ledger = h.store.permissions.ledger
        #expect(ledger.answer(.location, for: model.slug) == .allowed)
        #expect(ledger.entries.keys.sorted() == [model.slug])
        #expect(model.slug == "run-tracker")
    }

    /// Changing an app previews the app itself: its answers are its own.
    @Test func aChangesPreviewAsksAsTheApp() async {
        let h = GateHarness(choices: [.allow])
        defer { h.cleanUp() }
        let app = CachedApp(meta: habits, cachedVersion: "1", isNew: false)
        let model = CreateModel(app: app, source: "// Name: Habits")
        #expect(model.permissionSlug == "habits")
        #expect(await model.previewPermissions(h.gate).request(.camera))
        model.closed(h.gate)
        #expect(h.gate.ledger.answer(.camera, for: "habits") == .allowed)
    }
}
