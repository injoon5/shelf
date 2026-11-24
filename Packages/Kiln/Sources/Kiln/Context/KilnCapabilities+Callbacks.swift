//
//  KilnCapabilities+Callbacks.swift
//  Kiln's run context: the capability gate, for APIs that answer by callback
//
//  Core Motion and Core Location answer through handlers and delegates, not
//  `await`: `pedometer.startUpdates(from:) { data, error in … }` hears
//  `CMErrorMotionActivityNotAuthorized` when the app isn't allowed, and a
//  location delegate hears `.denied`. Their bridges ask the gate this way.
//

import Foundation

extension KilnCapabilities {
    /// Calls `then` with whether the app may use `capability`, asking the
    /// host if nobody has. A check (`headless`, or a stub context) is
    /// answered at once, before this returns; so is an answer the gate
    /// already has. Teardown withdraws a request still waiting, which
    /// answers `false` (and the app's code no longer runs).
    func answer(_ capability: KilnCapability, headless: Bool, _ then: @escaping @MainActor (Bool) -> Void) {
        if headless || isStub {
            then(gate.answerWithoutAsking(capability))
            return
        }
        switch status(capability) {
        case .allowed: then(true)
        case .denied: then(false)
        case .notAsked: Task { @MainActor in then(await self.ask(capability)) }
        }
    }

    /// No host gate: the system's own prompt decides (Kiln Lab, `Kiln.run(_:)`).
    var isUngated: Bool { gate is KilnUngatedCapabilities }
}
