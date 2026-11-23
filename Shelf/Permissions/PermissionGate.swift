import Foundation
import Observation

/// What the person chose in Shelf's own sheet.
enum PermissionChoice: Sendable, Equatable {
    case allow
    case deny
    /// The sheet went without an answer: the app's card closed, or there
    /// was nowhere to show it. Nothing is recorded, so the app asks again.
    case dismissed
}

/// Shows Shelf's sheet, "Run Tracker wants to use your location", and
/// returns once it has gone. Tests answer for the person.
@MainActor
protocol PermissionAsker: AnyObject {
    /// `systemWillAsk`: iOS's own prompt follows an Allow, and the sheet says so.
    func ask(_ capability: Capability, for app: AppMeta, systemWillAsk: Bool) async -> PermissionChoice
    /// Takes down a sheet still up for `slug`, which then answers `.dismissed`.
    func dismiss(for slug: String)
}

/// The capabilities gate (plan §4.0, §1.7). iOS asks once for Shelf; this
/// asks once for each app, keeps the answer in the `ledger`, and gives
/// every app the answer it was given, with iOS's answer for Shelf on top.
///
/// Main actor, like everything that shows UI. Kiln's run context reaches it
/// through `AppPermissions`, one per run, which knows which app is asking.
@MainActor
@Observable
final class PermissionGate {
    let ledger: PermissionLedger
    @ObservationIgnored let system: any SystemPermissions
    @ObservationIgnored let asker: any PermissionAsker

    /// Bumped whenever iOS's answers may have changed (a prompt was
    /// answered, Shelf came back from iOS Settings), so Settings re-reads them.
    private(set) var systemChanges = 0

    private struct Key: Hashable {
        var slug: String
        var capability: Capability
    }

    /// Requests being answered: a second one for the same app and
    /// capability waits for the first instead of asking twice.
    @ObservationIgnored private var inFlight: [Key: Task<Bool, Never>] = [:]
    /// One sheet at a time. Requests for other apps or capabilities wait here.
    @ObservationIgnored private var sheetIsUp = false
    @ObservationIgnored private var sheetQueue: [CheckedContinuation<Void, Never>] = []

    init(ledger: PermissionLedger, system: any SystemPermissions, asker: any PermissionAsker) {
        self.ledger = ledger
        self.system = system
        self.asker = asker
    }

    // MARK: Checking

    /// What `app` would get for `capability` without asking anyone: for the
    /// APIs that only check (`authorizationStatus`, `recordPermission`).
    ///
    /// iOS refusing Shelf is `.denied`, whatever the ledger says. An app
    /// allowed here whose capability iOS hasn't been asked about yet is
    /// `.notAsked`, so it asks, and iOS's prompt follows.
    func status(_ capability: Capability, for app: AppMeta) -> PermissionStatus {
        status(capability, slug: app.slug)
    }

    func status(_ capability: Capability, slug: String) -> PermissionStatus {
        let system = system.status(capability)
        if system.isRefused { return .denied }
        switch ledger.answer(capability, for: slug) {
        case .denied: return .denied
        case .allowed: return system == .allowed ? .allowed : .notAsked
        case nil: return .notAsked
        }
    }

    /// iOS's answer for Shelf, for Settings.
    func systemStatus(_ capability: Capability) -> SystemPermissionStatus {
        _ = systemChanges   // Settings re-reads when it changes
        return system.status(capability)
    }

    /// Shelf is back in front: iOS Settings may have changed something.
    func systemMayHaveChanged() {
        systemChanges += 1
    }

    // MARK: Asking

    /// Whether `app` may use `capability`, asking if nobody has yet. The
    /// one call every API that prompts goes through:
    ///
    /// 1. iOS has refused Shelf: no, without asking.
    /// 2. The ledger has an answer: that answer. An allowed app whose
    ///    capability iOS hasn't asked Shelf about yet gets iOS's prompt now.
    /// 3. Otherwise Shelf's sheet asks. Allow or Don't Allow is stored for
    ///    the app; on Allow, iOS's prompt follows if iOS hasn't asked yet.
    ///
    /// A request cancelled while its sheet is up (the app's task, or the
    /// card closing: `cancelRequests(for:)`) takes the sheet down, records
    /// nothing and returns false.
    func request(_ capability: Capability, for app: AppMeta) async -> Bool {
        let key = Key(slug: app.slug, capability: capability)
        let task: Task<Bool, Never>
        if let running = inFlight[key] {
            task = running
        } else {
            task = Task { await self.resolve(capability, for: app) }
            inFlight[key] = task
        }
        let answer = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor in self.cancelRequests(for: app.slug) }
        }
        if inFlight[key] == task { inFlight[key] = nil }
        return answer
    }

    /// Takes down a sheet up for `slug`, and drops its waiting requests:
    /// the app's card has closed (§1.7's teardown).
    func cancelRequests(for slug: String) {
        asker.dismiss(for: slug)
        for (key, task) in inFlight where key.slug == slug {
            task.cancel()
            // A request made from now on starts afresh, not on the cancelled one.
            inFlight[key] = nil
        }
    }

    private func resolve(_ capability: Capability, for app: AppMeta) async -> Bool {
        if system.status(capability).isRefused { return false }
        switch ledger.answer(capability, for: app.slug) {
        case .denied:
            return false
        case .allowed:
            return await systemAllows(capability)
        case nil:
            break
        }

        await waitForSheet()
        defer { releaseSheet() }
        // Answered meanwhile, by a request that held the sheet before this
        // one, or in Settings, or the request was cancelled while it waited.
        if Task.isCancelled || system.status(capability).isRefused { return false }
        if let answer = ledger.answer(capability, for: app.slug) {
            return answer == .allowed ? await systemAllows(capability) : false
        }

        let systemWillAsk = system.status(capability) == .notDetermined
        switch await asker.ask(capability, for: app, systemWillAsk: systemWillAsk) {
        case .dismissed:
            return false
        case .deny:
            ledger.set(.denied, capability, for: app.slug, name: app.name)
            return false
        case .allow:
            ledger.set(.allowed, capability, for: app.slug, name: app.name)
            return await systemAllows(capability)
        }
    }

    /// iOS's answer for Shelf, asking it first if it hasn't been asked.
    private func systemAllows(_ capability: Capability) async -> Bool {
        switch system.status(capability) {
        case .allowed:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            if Task.isCancelled { return false }
            let answer = await system.request(capability)
            systemChanges += 1
            return answer == .allowed
        }
    }

    private func waitForSheet() async {
        if !sheetIsUp {
            sheetIsUp = true
            return
        }
        await withCheckedContinuation { sheetQueue.append($0) }
    }

    private func releaseSheet() {
        if sheetQueue.isEmpty {
            sheetIsUp = false
        } else {
            sheetQueue.removeFirst().resume()
        }
    }

    // MARK: Settings

    /// Settings › Permissions' switch. Off is the "denied" answer the API
    /// gives; on is allowed, and iOS's prompt follows the next request if
    /// iOS hasn't asked yet.
    func setAllowed(_ allowed: Bool, _ capability: Capability, for slug: String, name: String) {
        ledger.set(allowed ? .allowed : .denied, capability, for: slug, name: name)
    }

    /// Delete App and a sync that finds the app gone run this too
    /// (`AppCleanup`): any sheet up for it goes with its answers.
    func forget(_ slug: String) {
        cancelRequests(for: slug)
        ledger.remove(slug)
    }

    /// Sign Out: every app's answers, and any sheet that's up.
    func forgetAll() {
        for slug in Set(inFlight.keys.map(\.slug)) { cancelRequests(for: slug) }
        ledger.removeAll()
    }
}

// MARK: - One app's view of the gate

/// The gate as one run of one app sees it: what §1.7's run context holds,
/// and what each Round 3 bridge calls. Kiln never names the app; the host
/// bound it when the run began.
@MainActor
protocol AppPermissions: AnyObject {
    /// Asks if nobody has, and says whether the app may go ahead.
    func request(_ capability: Capability) async -> Bool
    /// The answer without asking: for `authorizationStatus`-style checks.
    func status(_ capability: Capability) -> PermissionStatus
    /// The run is over: a sheet still up for it goes, answering nothing.
    func cancelRequests()
}

/// A real run's permissions: the gate, for one app.
@MainActor
final class GatedAppPermissions: AppPermissions {
    let gate: PermissionGate
    /// Read at each request, not once: the New App preview's name can
    /// change while the preview runs.
    private let identity: () -> AppMeta

    init(gate: PermissionGate, identity: @escaping () -> AppMeta) {
        self.gate = gate
        self.identity = identity
    }

    convenience init(gate: PermissionGate, app: AppMeta) {
        self.init(gate: gate) { app }
    }

    func request(_ capability: Capability) async -> Bool {
        await gate.request(capability, for: identity())
    }

    func status(_ capability: Capability) -> PermissionStatus {
        gate.status(capability, for: identity())
    }

    func cancelRequests() {
        gate.cancelRequests(for: identity().slug)
    }
}

/// Fixed answers and no UI: for Kiln's `validate` (§1.7, §1.8), which fires
/// every action headless, and for tests. It never shows a sheet, never asks
/// iOS and never writes the ledger. By default every capability is allowed,
/// so validate goes down the path where the context's fake sensors answer.
@MainActor
final class StubAppPermissions: AppPermissions {
    var statuses: [Capability: PermissionStatus]
    /// What a request for a capability not yet asked returns.
    var answerWhenAsked: Bool
    /// Every request, in order: what validate saw the app ask for.
    private(set) var requested: [Capability] = []

    init(_ statuses: [Capability: PermissionStatus]? = nil, answerWhenAsked: Bool = true) {
        self.statuses = statuses ?? Dictionary(uniqueKeysWithValues: Capability.allCases.map { ($0, .allowed) })
        self.answerWhenAsked = answerWhenAsked
    }

    func request(_ capability: Capability) async -> Bool {
        requested.append(capability)
        switch statuses[capability] ?? .notAsked {
        case .allowed: return true
        case .denied: return false
        case .notAsked: return answerWhenAsked
        }
    }

    func status(_ capability: Capability) -> PermissionStatus {
        statuses[capability] ?? .notAsked
    }

    func cancelRequests() {}
}

extension PermissionGate {
    /// The gate bound to one installed app, for its run.
    func forApp(_ app: AppMeta) -> GatedAppPermissions {
        GatedAppPermissions(gate: self, app: app)
    }

    /// A gate with nothing behind it: in memory, iOS allowing everything,
    /// and nobody to ask (every sheet answers `.dismissed`). For libraries
    /// that never show UI.
    static func inMemory(system: any SystemPermissions = FixedSystemPermissions.allowingEverything()) -> PermissionGate {
        PermissionGate(ledger: PermissionLedger(file: nil), system: system, asker: SilentAsker())
    }
}

/// Answers every sheet without showing one.
@MainActor
final class SilentAsker: PermissionAsker {
    var choice: PermissionChoice

    init(_ choice: PermissionChoice = .dismissed) {
        self.choice = choice
    }

    func ask(_ capability: Capability, for app: AppMeta, systemWillAsk: Bool) async -> PermissionChoice {
        choice
    }

    func dismiss(for slug: String) {}
}
