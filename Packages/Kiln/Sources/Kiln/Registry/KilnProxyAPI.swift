//
//  KilnProxyAPI.swift
//  Kiln's bridge registry: protocol proxies for the host (PLAN.md §1.5)
//
//  The host declares a protocol the app's types can adopt, and calls the
//  app's value through it, `async` requirements included: they run as VM
//  tasks the host awaits. Round 4's Foundation Models `Tool` and Round 5's
//  `TimelineProvider` and `AppIntent` take the same path inside Kiln
//  (`KAppValue.callAsync`).
//
//      Kiln.registerProtocol("Greeter", requirements: ["async greet(name:)"])
//      Kiln.registerFunction("greetWith", signature: "_:any") { call in
//          guard let g = call.adopter(0, as: "Greeter") else { throw call.error("needs a Greeter") }
//          return .async { try await g.callAsync("greet(name:)", [KilnValue(string: "Ann")]) }
//      }
//

import Foundation

extension Kiln {
    /// A protocol the app's types can adopt. A type that adopts it without a
    /// required member is an error with its line. Registering it again replaces it.
    @MainActor
    public static func registerProtocol(_ name: String, requirements: [String], family: KilnFamily = .host, notes: String? = nil) {
        let r = KRegistry.shared
        r.removeClaim("protocol:" + name)
        let b = KProtocolBridge(name: name, family: family, support: .full, introduced: nil, notes: notes, source: "host")
        b.members = requirements.map(KRequirement.init(parsing:))
        b.requirements = b.members.map(\.declared)
        b.proxy = { app in KilnAdopter(app: app) }
        r.add(b)
    }
}

extension KilnCall {
    /// The app's value at `position` as an adopter of `protocolName`, or nil
    /// when its type doesn't adopt it.
    public func adopter(_ position: Int, as protocolName: String) -> KilnAdopter? {
        guard let v = c[.position(position)] else { return nil }
        return c.interp.proxy(for: v, as: protocolName) as? KilnAdopter
    }

    public func adopter(_ label: String, as protocolName: String) -> KilnAdopter? {
        guard let v = c[.label(label)] else { return nil }
        return c.interp.proxy(for: v, as: protocolName) as? KilnAdopter
    }
}

/// The app's value, through a protocol it adopts: its requirements called
/// from the host. Arguments and results are `KilnValue`s; an error the app's
/// code throws, or a runtime error with its line, is thrown to the host.
@MainActor
public final class KilnAdopter {
    var app: KAppValue

    init(app: KAppValue) { self.app = app }

    /// The app's type: `"Polite"`.
    public var typeName: String { app.type.name }

    /// Whether the app's type has this member (`"greet(name:)"`, `"title"`).
    public func implements(_ requirement: String) -> Bool { app.implements(KRequirement(parsing: requirement)) }

    /// A requirement that doesn't wait, run to the end.
    public func call(_ requirement: String, _ args: [KilnValue] = []) throws -> KilnValue {
        let r = KRequirement(parsing: requirement)
        return KilnValue(try app.call(r.name, args.map(\.kv), labels: r.labels ?? []))
    }

    /// A requirement that may wait (`async`): a VM task, awaited. Cancelling
    /// the host's task cancels the app's.
    public func callAsync(_ requirement: String, _ args: [KilnValue] = []) async throws -> KilnValue {
        let r = KRequirement(parsing: requirement)
        return KilnValue(try await app.callAsync(r.name, args.map(\.kv), labels: r.labels ?? []))
    }

    /// A property, or a static one (`static var title`).
    public func property(_ name: String) throws -> KilnValue {
        if app.implementsStatic(name), !app.implements(name) { return KilnValue(try app.getStatic(name)) }
        return KilnValue(try app.get(name))
    }
}
