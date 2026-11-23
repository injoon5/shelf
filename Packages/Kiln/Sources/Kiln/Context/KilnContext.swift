//
//  KilnContext.swift
//  Kiln's run context (PLAN.md §1.7)
//
//  Everything one run of one app is given by its host, in one place:
//
//  - who it is (a slug and a display name, for errors and permission prompts);
//  - its defaults: the `UserDefaults` that `@AppStorage` and
//    `UserDefaults.standard` resolve to;
//  - its files: the folder `URL.documentsDirectory`, `FileManager` and the
//    rest resolve into (`KilnFiles`), which nothing leaves;
//  - the host's own values its bridges reach (`provide` / `provided`), such
//    as Shelf's `DB` store;
//  - the capability gate (`KilnCapabilities`), which the host answers per app;
//  - teardown: what stops when the app's screen closes (`onTearDown`);
//  - errors: every check and runtime error, with its line (`onError`).
//
//  A bridge reaches it from its call: `c.context` in Kiln's own bridges
//  (`KCall`), `call.context` in the host's (`KilnCall`). Docs/bridges.md,
//  "The run's context", is the guide.
//
//  One context is one run. A stub context (`KilnContext.stub`) is what
//  `Kiln.validate` runs with: a throwaway folder and defaults, and a gate
//  that answers at once, so firing every action touches no sensor, no real
//  file and no real setting.
//

import Foundation

@MainActor
public final class KilnContext {
    /// The app's identifier, stable across versions: the host's key for it.
    public let slug: String
    /// The app's name as people see it: "Run Tracker".
    public let name: String
    /// What `@AppStorage` and `UserDefaults.standard` read and write. A stub
    /// context's are in memory, made when the app first uses them.
    public var defaults: UserDefaults {
        if let made = madeDefaults { return made }
        let made = makeDefaults()
        madeDefaults = made
        return made
    }
    private var madeDefaults: UserDefaults?
    private var makeDefaults: () -> UserDefaults
    /// The app's own folder. A stub context names its throwaway one only
    /// when the app first uses it.
    public var files: KilnFiles {
        if let made = madeFiles { return made }
        let made = makeFiles()
        madeFiles = made
        return made
    }
    private var madeFiles: KilnFiles?
    private var makeFiles: () -> KilnFiles
    /// The gate every API that needs permission goes through.
    public let capabilities: KilnCapabilities
    /// A check, not a real run: bridges use their fakes (fake motion, fake
    /// location), never the real thing, and write nothing that lasts.
    public let isStub: Bool

    /// Every error of the run, check and runtime alike, with its line, on
    /// the main actor and never in the middle of a SwiftUI update (it comes
    /// on the next turn of the run loop). Errors a run had before this was
    /// set are delivered when it is set.
    public var onError: (@MainActor (KilnError) -> Void)? {
        didSet { flushErrors() }
    }

    /// The errors the run has had, in order.
    public private(set) var errors: [KilnError] = []

    /// Whether `tearDown()` has run.
    public private(set) var isTornDown = false

    private var hosted: [ObjectIdentifier: Any] = [:]
    private var stoppers: [(id: Int, stop: @MainActor () -> Void)] = []
    private var nextStopper = 0
    private var undelivered: [KilnError] = []
    private var flushScheduled = false
    /// What a stub context made for itself and removes when it's torn down.
    private var throwaway: (folder: URL?, Void) = (nil, ())
    /// While > 0, errors are a view's `body` failing.
    var bodyDepth = 0

    /// A context for one run of the app `slug`, called `name`.
    ///
    /// - Parameters:
    ///   - defaults: the app's own suite. Two apps given two suites never see
    ///     each other's settings.
    ///   - files: the app's own folder.
    ///   - capabilities: the host's answers for this app. Without one, every
    ///     capability is left to the system's own prompt (`KilnUngatedCapabilities`).
    public init(slug: String, name: String, defaults: UserDefaults, files: KilnFiles,
                capabilities: (any KilnCapabilityGate)? = nil) {
        self.slug = slug
        self.name = name
        self.madeDefaults = defaults
        self.makeDefaults = { defaults }
        self.madeFiles = files
        self.makeFiles = { files }
        self.isStub = false
        self.capabilities = KilnCapabilities(gate: capabilities ?? KilnUngatedCapabilities(), isStub: false)
    }

    private init(stubSlug slug: String, name: String, capabilities: any KilnCapabilityGate) {
        self.slug = slug
        self.name = name
        self.makeDefaults = { KilnMemoryDefaults() }
        self.makeFiles = { KilnFiles(root: FileManager.default.temporaryDirectory) }
        self.isStub = true
        self.capabilities = KilnCapabilities(gate: capabilities, isStub: true)
        // Named when first used: most checks touch neither, and a check is
        // run often enough that making them every time shows in its time.
        // In memory: a check's settings never outlive it (KilnMemoryDefaults).
        makeDefaults = { KilnMemoryDefaults() }
        makeFiles = { [unowned self] in
            let folder = FileManager.default.temporaryDirectory.appending(path: "kiln-check-\(throwawayID)", directoryHint: .isDirectory)
            throwaway.folder = folder
            return KilnFiles(root: folder)
        }
    }

    private lazy var throwawayID = UUID().uuidString

    /// A context for checking (`Kiln.validate`): throwaway defaults and a
    /// throwaway folder, both empty, removed when the check ends; and
    /// `capabilities`, which answer at once (by default, everything is
    /// allowed, so a check goes down the path where the fakes answer).
    public static func stub(slug: String = "check", name: String = "App",
                            capabilities: (any KilnCapabilityGate)? = nil) -> KilnContext {
        KilnContext(stubSlug: slug, name: name, capabilities: capabilities ?? KilnStubCapabilities())
    }

    /// What `Kiln.run(_:)` without a context uses: an app called "App",
    /// with defaults and a folder of its own under the host's (`kiln.app`,
    /// `Application Support/Kiln/app`), and no gate of its own.
    public static func standard() -> KilnContext {
        let context = KilnContext(slug: "app", name: "App", defaults: .standard, files: KilnFiles(root: URL(fileURLWithPath: "/")))
        // Made when first used, as a stub's are.
        context.madeDefaults = nil
        context.makeDefaults = { UserDefaults(suiteName: "kiln.app") ?? .standard }
        context.madeFiles = nil
        context.makeFiles = { KilnFiles(root: URL.applicationSupportDirectory.appending(path: "Kiln/app", directoryHint: .isDirectory)) }
        return context
    }

    // MARK: The host's values

    /// Gives the run's bridges a value of the host's, found by its type:
    /// Shelf's `DB` store, a fake sensor in a stub context.
    public func provide<T>(_ value: T) {
        hosted[ObjectIdentifier(T.self)] = value
    }

    /// The value of type `T` the host provided, if any.
    public func provided<T>(_ type: T.Type = T.self) -> T? {
        hosted[ObjectIdentifier(T.self)] as? T
    }

    // MARK: Teardown

    /// Registers what stops something the app started: a motion manager's
    /// updates, a location session, a player, a socket, a web page. It runs
    /// when the app's screen closes (`tearDown`), last registered first, at
    /// most once. Registered after teardown, it runs at once.
    @discardableResult
    public func onTearDown(_ stop: @escaping @MainActor () -> Void) -> KilnTeardownToken {
        if isTornDown {
            stop()
            return KilnTeardownToken(context: nil, id: -1)
        }
        nextStopper += 1
        stoppers.append((nextStopper, stop))
        return KilnTeardownToken(context: self, id: nextStopper)
    }

    fileprivate func remove(_ id: Int) {
        stoppers.removeAll { $0.id == id }
    }

    /// The app's screen has closed: cancels its tasks and timers, stops
    /// everything registered with `onTearDown`, and withdraws any permission
    /// request still waiting. None of the app's code runs after this.
    /// Safe to call more than once.
    public func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        let running = stoppers
        stoppers = []
        for s in running.reversed() { s.stop() }
        capabilities.cancelRequests()
        (madeDefaults as? KilnMemoryDefaults)?.removeAll()
        if let folder = throwaway.folder {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// A new run with this context: it can be torn down again.
    func begin() {
        isTornDown = false
    }

    // MARK: Errors

    func record(_ error: KilnError) {
        errors.append(error)
        undelivered.append(error)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard onError != nil, !flushScheduled, !undelivered.isEmpty else { return }
        flushScheduled = true
        // Never during a SwiftUI update: a body's error is found while
        // SwiftUI evaluates it, and the host will want to change what shows.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.flushErrors(now: true) }
        }
    }

    private func flushErrors(now: Bool = false) {
        guard now else { return scheduleFlush() }
        flushScheduled = false
        guard let onError else { return }
        let pending = undelivered
        undelivered = []
        for e in pending { onError(e) }
    }
}

/// Withdraws what `onTearDown` registered, when it stopped by itself.
@MainActor
public struct KilnTeardownToken {
    weak var context: KilnContext?
    let id: Int

    /// It has stopped already: teardown needn't stop it.
    public func cancel() { context?.remove(id) }
}

/// An error an app's run hit, as the host gets it.
public struct KilnError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Phase: String, Sendable {
        /// The code doesn't parse, or has no view to show: nothing runs.
        case check
        /// A view's `body` failed: what shows is broken.
        case body
        /// Anything else at run time: an action, a task, a global's value.
        case runtime
    }

    public let phase: Phase
    /// 1-based, when the error has a line.
    public let line: Int?
    public let message: String

    public init(phase: Phase, line: Int?, message: String) {
        self.phase = phase
        self.line = line
        self.message = message
    }

    /// "Line 12: message", as `KilnResult.errors` reads.
    public var description: String { line.map { "Line \($0): \(message)" } ?? message }

    /// Reads Kiln's "Line N: message" form.
    init(phase: Phase, reported text: String) {
        let first = text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? text
        if first.hasPrefix("Line "), let colon = first.firstIndex(of: ":"),
           let n = Int(first[first.index(first.startIndex, offsetBy: 5)..<colon]) {
            self.init(phase: phase, line: n, message: String(first[first.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        } else {
            self.init(phase: phase, line: nil, message: first)
        }
    }
}

// MARK: - Reaching the context from a bridge

extension KCall {
    /// The run's context: its defaults, folder, gate, teardown and host values.
    var context: KilnContext { interp.context }
}

extension KilnCall {
    /// The run's context: its defaults, folder, gate, teardown and the values
    /// the host provided (`context.provided(MyStore.self)`).
    public var context: KilnContext { c.interp.context }
}
