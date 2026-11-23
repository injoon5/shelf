//
//  KilnCapabilities.swift
//  Kiln's run context: the capability gate
//
//  The system asks once for the host; the host decides per app (PLAN.md
//  §4.0). A bridge for an API that needs permission asks the gate first,
//  and the gate's answer is what the app sees: "denied" is the answer the
//  API would give.
//
//  From a Kiln bridge, asking is something `await` waits on:
//
//      t.staticMethod("requestWhenInUseAuthorization") { c in
//          .suspension(c.context.capabilities.request(.location))   // resumes with a Bool
//      }
//
//  A host bridge gets the same as a `KilnValue` (`call.context.capabilities.request(.location)`).
//  In a check (`Kiln.validate`) nothing waits and nobody is asked: the gate
//  answers at once (`answerWithoutAsking`).
//

import Foundation

/// What an app has to be allowed before it can use it. The raw values are
/// the host's too (Shelf's `Capability`).
public enum KilnCapability: String, CaseIterable, Sendable {
    case camera
    case microphone
    /// Motion & Fitness: the pedometer, activity, the altimeter, headphone motion.
    case motion
    /// Location while the app is open.
    case location
    /// Saving to the photo library.
    case photoLibraryAdd
}

/// The answer so far, without asking.
public enum KilnPermissionStatus: String, Sendable {
    case notAsked
    case allowed
    case denied
}

/// The host's answers for one app: Shelf's `AppPermissions`.
@MainActor
public protocol KilnCapabilityGate: AnyObject {
    /// Asks if nobody has, and says whether the app may go ahead.
    func request(_ capability: KilnCapability) async -> Bool
    /// The answer without asking: for `authorizationStatus`-style checks.
    func status(_ capability: KilnCapability) -> KilnPermissionStatus
    /// The run is over: a request still waiting goes, answering nothing.
    func cancelRequests()
    /// What a check (`Kiln.validate`) gets, at once and without asking anyone.
    /// By default: allowed only if already allowed.
    func answerWithoutAsking(_ capability: KilnCapability) -> Bool
}

extension KilnCapabilityGate {
    public func answerWithoutAsking(_ capability: KilnCapability) -> Bool {
        status(capability) == .allowed
    }
}

/// No gate of the host's: every request is allowed here, and the system's
/// own prompt (if any) decides. What `Kiln.run(_:)` without a context gets.
@MainActor
public final class KilnUngatedCapabilities: KilnCapabilityGate {
    public init() {}
    public func request(_ capability: KilnCapability) async -> Bool { true }
    public func status(_ capability: KilnCapability) -> KilnPermissionStatus { .allowed }
    public func cancelRequests() {}
}

/// Fixed answers and no UI, for checks and tests. Every request is
/// recorded, so a check can say what the app asked for.
@MainActor
public final class KilnStubCapabilities: KilnCapabilityGate {
    public var statuses: [KilnCapability: KilnPermissionStatus]
    /// What a capability not yet asked answers.
    public var answerWhenAsked: Bool
    /// Every request, in order.
    public private(set) var requested: [KilnCapability] = []

    /// By default everything is allowed, so a check goes down the path where
    /// the context's fakes answer.
    public init(_ statuses: [KilnCapability: KilnPermissionStatus]? = nil, answerWhenAsked: Bool = true) {
        self.statuses = statuses ?? Dictionary(uniqueKeysWithValues: KilnCapability.allCases.map { ($0, .allowed) })
        self.answerWhenAsked = answerWhenAsked
    }

    public func request(_ capability: KilnCapability) async -> Bool {
        answerWithoutAsking(capability)
    }

    public func status(_ capability: KilnCapability) -> KilnPermissionStatus {
        statuses[capability] ?? .notAsked
    }

    public func cancelRequests() {}

    public func answerWithoutAsking(_ capability: KilnCapability) -> Bool {
        requested.append(capability)
        switch status(capability) {
        case .allowed: return true
        case .denied: return false
        case .notAsked: return answerWhenAsked
        }
    }
}

/// The run's gate, as bridges use it.
@MainActor
public final class KilnCapabilities {
    /// The host's answers for this app.
    public let gate: any KilnCapabilityGate
    /// A check: requests are answered at once (`answerWithoutAsking`).
    public let isStub: Bool
    private var waiting: [Int: @MainActor (Bool) -> Void] = [:]
    private var nextWaiter = 0

    init(gate: any KilnCapabilityGate, isStub: Bool) {
        self.gate = gate
        self.isStub = isStub
    }

    /// The answer so far, without asking.
    public func status(_ capability: KilnCapability) -> KilnPermissionStatus {
        gate.status(capability)
    }

    /// Asks, and says whether the app may go ahead. A stub gate answers at once.
    public func ask(_ capability: KilnCapability) async -> Bool {
        if isStub { return gate.answerWithoutAsking(capability) }
        return await gate.request(capability)
    }

    /// For Kiln's bridges: what `await` waits on, resuming with `.bool`.
    /// Headless (a check) it resumes at once with `answerWithoutAsking`;
    /// cancelling the app's task, or tearing the run down, resumes it with
    /// `false` and withdraws the request.
    func request(_ capability: KilnCapability) -> KSuspension {
        KSuspension.callback { [weak self] ctx, resume in
            guard let self else { resume(.success(.bool(false))); return nil }
            if ctx.interp.headless || self.isStub {
                resume(.success(.bool(self.gate.answerWithoutAsking(capability))))
                return nil
            }
            self.nextWaiter += 1
            let id = self.nextWaiter
            var done = false
            let finish: @MainActor (Bool) -> Void = { allowed in
                guard !done else { return }
                done = true
                self.waiting[id] = nil
                resume(.success(.bool(allowed)))
            }
            self.waiting[id] = finish
            let work = Task { @MainActor in
                let allowed = await self.gate.request(capability)
                finish(allowed)
            }
            return {
                work.cancel()
                finish(false)
            }
        }
    }

    /// For the host's bridges: the same, as a value `await` waits on.
    public func request(_ capability: KilnCapability) -> KilnValue {
        KilnValue(.suspension(request(capability)))
    }

    /// The run is over: every request still waiting answers `false`, and the
    /// host's sheet for it goes.
    func cancelRequests() {
        let pending = waiting.values
        waiting = [:]
        for finish in pending { finish(false) }
        gate.cancelRequests()
    }
}
