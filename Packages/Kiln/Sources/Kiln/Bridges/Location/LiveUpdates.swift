//
//  LiveUpdates.swift
//  Bridges: Core Location's Swift API (PLAN.md §4.6)
//
//      .task {
//          let session = CLServiceSession(authorization: .whenInUse)
//          for try await update in CLLocationUpdate.liveUpdates() {
//              if update.authorizationDenied { denied = true; continue }
//              if let location = update.location { here = location }
//          }
//      }
//
//  `liveUpdates()` asks the capability gate when the loop starts. While the
//  host's sheet (or iOS's prompt) is up, the loop gets an update with
//  `authorizationRequestInProgress`; a refused app gets one with
//  `authorizationDenied` and no location, and the stream stays open, as the
//  device's does. The loop ends with the app's task, and with its screen.
//
//  And SwiftUI's `LocationButton`, which asks the same gate when tapped.
//

import SwiftUI
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(CoreLocationUI) && os(iOS)
import CoreLocationUI
#endif

/// One `CLLocationUpdate`, or one `CLServiceSession.Diagnostic`: flags and a location.
@MainActor
final class KLocationUpdate {
    let type: String
    var location: KV = .nilValue
    var flags: Set<String> = []

    init(_ type: String) { self.type = type }

    var kv: KV { .native(.object(type, KRef(self))) }

    static let updateFlags = ["isStationary", "stationary", "authorizationDenied", "authorizationDeniedGlobally", "authorizationRestricted",
                              "insufficientlyInUse", "locationUnavailable", "accuracyLimited", "serviceSessionRequired",
                              "authorizationRequestInProgress"]
    static let diagnosticFlags = ["authorizationDenied", "authorizationDeniedGlobally", "authorizationRestricted", "insufficientlyInUse",
                                  "fullAccuracyDenied", "alwaysAuthorizationDenied", "serviceSessionRequired", "authorizationRequestInProgress"]
}

extension LocationBridges {
    static func liveUpdates(_ r: KRegistry) {
        r.type("CLLocationUpdate", .location, support: .full,
               notes: "`for try await update in CLLocationUpdate.liveUpdates()`: `update.location`, `authorizationDenied`, `accuracyLimited`, `stationary`.") { t in
            t.staticMethod("liveUpdates", "_:CLLocationUpdate.LiveConfiguration?") { c in
                let configuration = KNativeEnum.name(c[0]) ?? "default"
                let interp = c.interp
                let seq = KAsyncSequence(name: "CLLocationUpdate.Updates") { [weak interp] in
                    let channel = KAsyncChannel(interp: interp)
                    if let interp { KLiveUpdates.feed(channel, configuration: configuration, interp) }
                    return channel.iterator()
                }
                return .native(.object("AsyncSequence", KRef(seq)))
            }
            for flag in KLocationUpdate.updateFlags {
                t.property(flag) { c in .bool(c.object(KLocationUpdate.self)?.flags.contains(flag) ?? false) }
            }
            t.property("location") { c in c.object(KLocationUpdate.self)?.location ?? .nilValue }
            t.staticProperty("LiveConfiguration") { _ in .type(.builtin("CLLocationUpdate.LiveConfiguration")) }
        }
        r.type("CLLocationUpdate.LiveConfiguration", .location, support: .full) { t in
            t.staticProperties(Dictionary(uniqueKeysWithValues: ["default", "automotiveNavigation", "otherNavigation", "fitness", "airborne", "maritime"]
                .map { ($0, KV.native(.implicit($0, []))) }))
        }

        r.type("CLServiceSession", .location, support: .full,
               notes: "`CLServiceSession(authorization: .whenInUse)`: asks first, and keeps location on while you hold it; `diagnostics` for `for try await`.") { t in
            t.initializer("authorization:CLServiceSession.AuthorizationRequirement") { c in
                KServiceSession.make(c, requirement: KNativeEnum.name(c["authorization"]) ?? "whenInUse")
            }
            t.initializer("authorization:CLServiceSession.AuthorizationRequirement fullAccuracyPurposeKey:string") { c in
                KServiceSession.make(c, requirement: KNativeEnum.name(c["authorization"]) ?? "whenInUse")
            }
            t.method("invalidate", "") { c in c.object(KServiceSession.self)?.invalidate(); return .void }
            t.property("diagnostics") { c in
                guard let s = c.object(KServiceSession.self) else { return .nilValue }
                let seq = KAsyncSequence(name: "CLServiceSession.Diagnostics") { [weak s] in
                    let channel = KAsyncChannel(interp: s?.interp)
                    s?.listen(channel)
                    return channel.iterator()
                }
                return .native(.object("AsyncSequence", KRef(seq)))
            }
            t.staticProperty("AuthorizationRequirement") { _ in .type(.builtin("CLServiceSession.AuthorizationRequirement")) }
        }
        r.type("CLServiceSession.AuthorizationRequirement", .location, support: .full) { t in
            t.staticProperties(Dictionary(uniqueKeysWithValues: ["none", "whenInUse", "always"].map { ($0, KV.native(.implicit($0, []))) }))
        }
        r.type("CLServiceSession.Diagnostic", .location, support: .full) { t in
            for flag in KLocationUpdate.diagnosticFlags {
                t.property(flag) { c in .bool(c.object(KLocationUpdate.self)?.flags.contains(flag) ?? false) }
            }
        }
    }
}

@MainActor
enum KLiveUpdates {
    /// Starts what feeds one loop over `liveUpdates()`: the gate first, then
    /// the device or the fake. Stops when the loop does, or the screen closes.
    static func feed(_ channel: KAsyncChannel, configuration: String, _ interp: KInterpreter) {
        let caps = interp.context.capabilities
        let fake = LocationBridges.fake(interp)
        var stoppers: [@MainActor () -> Void] = []
        let token = interp.context.onTearDown { channel.cancel() }
        channel.onStop = {
            token.cancel()
            for s in stoppers { s() }
        }
        if let fake, !fake.servicesEnabled {
            let u = KLocationUpdate("CLLocationUpdate")
            u.flags = ["authorizationDeniedGlobally", "authorizationDenied"]
            channel.yield(u.kv)
            return
        }
        // With no host gate and the device, the device asks and reports itself.
        #if canImport(CoreLocation)
        if caps.isUngated, fake == nil {
            stoppers.append(device(channel, configuration))
            return
        }
        #endif
        if !interp.headless, !caps.isStub, caps.status(.location) == .notAsked {
            let u = KLocationUpdate("CLLocationUpdate")
            u.flags = ["authorizationRequestInProgress"]
            channel.yield(u.kv)
        }
        caps.answer(.location, headless: interp.headless) { allowed in
            guard !channel.finished else { return }
            guard allowed else {
                let u = KLocationUpdate("CLLocationUpdate")
                u.flags = ["authorizationDenied"]
                channel.yield(u.kv)
                return
            }
            if let fake {
                let start = Date()
                var last: (Double, Double)?
                @MainActor func tick() {
                    let t = Date().timeIntervalSince(start)
                    let f = fake.seen(t)
                    let u = KLocationUpdate("CLLocationUpdate")
                    u.location = KLocationManager.location(fake, at: t)
                    if fake.approximate { u.flags.insert("accuracyLimited") }
                    if let last, last == (f.latitude, f.longitude) { u.flags.formUnion(["stationary", "isStationary"]) }
                    last = (f.latitude, f.longitude)
                    channel.yield(u.kv)
                }
                tick()
                if interp.headless { return }
                let timer = Timer.scheduledTimer(withTimeInterval: fake.interval, repeats: true) { _ in
                    MainActor.assumeIsolated { if !channel.finished { tick() } }
                }
                stoppers.append { timer.invalidate() }
                return
            }
            #if canImport(CoreLocation)
            stoppers.append(device(channel, configuration))
            #endif
        }
    }

    #if canImport(CoreLocation)
    /// The device's own `liveUpdates`, read by a Swift task.
    static func device(_ channel: KAsyncChannel, _ configuration: String) -> @MainActor () -> Void {
        let reader = Task { @MainActor in
            do {
                for try await update in CLLocationUpdate.liveUpdates(Self.configuration(configuration)) {
                    if channel.finished { break }
                    channel.yield(convert(update))
                }
            } catch {
                channel.finish(throwing: error)
            }
        }
        return { reader.cancel() }
    }

    static func configuration(_ name: String) -> CLLocationUpdate.LiveConfiguration {
        switch name {
        case "automotiveNavigation": return .automotiveNavigation
        case "otherNavigation": return .otherNavigation
        case "fitness": return .fitness
        case "airborne": return .airborne
        default: return .default
        }
    }

    static func convert(_ update: CLLocationUpdate) -> KV {
        let u = KLocationUpdate("CLLocationUpdate")
        u.location = update.location.map { LocationBridges.location($0) } ?? .nilValue
        if #available(iOS 18.0, macOS 15.0, *) {
            let pairs: [(String, Bool)] = [("stationary", update.stationary), ("isStationary", update.stationary),
                                           ("authorizationDenied", update.authorizationDenied),
                                           ("authorizationDeniedGlobally", update.authorizationDeniedGlobally),
                                           ("authorizationRestricted", update.authorizationRestricted),
                                           ("insufficientlyInUse", update.insufficientlyInUse),
                                           ("locationUnavailable", update.locationUnavailable),
                                           ("accuracyLimited", update.accuracyLimited),
                                           ("serviceSessionRequired", update.serviceSessionRequired),
                                           ("authorizationRequestInProgress", update.authorizationRequestInProgress)]
            u.flags = Set(pairs.filter(\.1).map(\.0))
        }
        return u.kv
    }
    #endif
}

/// The app's `CLServiceSession`: asks the gate, then holds the device's
/// session while the app holds it, or until the screen closes.
@MainActor
final class KServiceSession {
    weak var interp: KInterpreter?
    let requirement: String
    private(set) var answer: Bool?
    private var listeners: [KAsyncChannel] = []
    private var invalidated = false
    #if os(iOS) || os(watchOS) || os(visionOS)
    private var device: AnyObject?
    #endif

    init(_ interp: KInterpreter, requirement: String) {
        self.interp = interp
        self.requirement = requirement
    }

    static func make(_ c: KCall, requirement: String) -> KV {
        let s = KServiceSession(c.interp, requirement: requirement)
        c.context.onTearDown { [weak s] in s?.invalidate() }
        s.start()
        return .native(.object("CLServiceSession", KRef(s)))
    }

    private func start() {
        guard let interp, requirement != "none" else { answer = true; return }
        let fake = LocationBridges.fake(interp)
        let caps = interp.context.capabilities
        if caps.isUngated, fake == nil {
            holdDevice()
            return
        }
        caps.answer(.location, headless: interp.headless) { [weak self] allowed in
            guard let self, !self.invalidated else { return }
            self.answer = allowed
            if allowed, fake == nil { self.holdDevice() }
            for l in self.listeners { l.yield(self.diagnostic()) }
        }
    }

    private func holdDevice() {
        #if os(iOS) || os(watchOS) || os(visionOS)
        if #available(iOS 18.0, watchOS 11.0, visionOS 2.0, *) {
            device = CLServiceSession(authorization: requirement == "always" ? .always : .whenInUse)
        }
        #endif
    }

    func diagnostic() -> KV {
        let d = KLocationUpdate("CLServiceSession.Diagnostic")
        switch answer {
        case false?: d.flags = ["authorizationDenied"]
        case nil: d.flags = ["authorizationRequestInProgress"]
        default: break
        }
        if requirement == "always" { d.flags.insert("alwaysAuthorizationDenied") }
        if let interp, LocationBridges.fake(interp)?.approximate == true { d.flags.insert("fullAccuracyDenied") }
        return d.kv
    }

    func listen(_ channel: KAsyncChannel) {
        guard !invalidated else { channel.finish(); return }
        listeners.append(channel)
        channel.onStop = { [weak self, weak channel] in self?.listeners.removeAll { $0 === channel } }
        channel.yield(diagnostic())
    }

    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        #if os(iOS) || os(watchOS) || os(visionOS)
        if #available(iOS 18.0, watchOS 11.0, visionOS 2.0, *) { (device as? CLServiceSession)?.invalidate() }
        device = nil
        #endif
        let open = listeners
        listeners = []
        for l in open { l.finish() }
    }
}

// MARK: - LocationButton

extension LocationBridges {
    static let buttonTitles = ["currentLocation", "sendCurrentLocation", "sendMyCurrentLocation", "shareCurrentLocation", "shareMyCurrentLocation"]

    static func button(_ r: KRegistry) {
        r.view("LocationButton", .location,
               notes: "Asks for location when tapped (the host's sheet the first time), then runs the action if allowed.") { v in
            v.form("action:action") { c in KLocationButton(title: "currentLocation", c: c) }
            v.form("_:LocationButton.Title? action:action") { c in KLocationButton(title: KNativeEnum.name(c[0]) ?? "currentLocation", c: c) }
        }
        r.type("LocationButton.Title", .location, support: .full) { t in
            t.staticProperties(Dictionary(uniqueKeysWithValues: buttonTitles.map { ($0, KV.native(.implicit($0, []))) }))
        }
    }
}

struct KLocationButton: View {
    let title: String
    let c: KCall

    var body: some View {
        let action = c.function("action")
        let interp = c.interp
        let tap = {
            interp.context.capabilities.answer(.location, headless: interp.headless) { allowed in
                if allowed { interp.perform(action) }
            }
        }
        #if canImport(CoreLocationUI) && os(iOS)
        LocationButton(Self.title(title), action: tap)
        #else
        Button(action: tap) { Label(Self.text(title), systemImage: "location.fill") }
        #endif
    }

    #if canImport(CoreLocationUI) && os(iOS)
    static func title(_ name: String) -> LocationButton.Title {
        switch name {
        case "sendCurrentLocation": return .sendCurrentLocation
        case "sendMyCurrentLocation": return .sendMyCurrentLocation
        case "shareCurrentLocation": return .shareCurrentLocation
        case "shareMyCurrentLocation": return .shareMyCurrentLocation
        default: return .currentLocation
        }
    }
    #endif

    static func text(_ name: String) -> String {
        switch name {
        case "sendCurrentLocation": return "Send Current Location"
        case "sendMyCurrentLocation": return "Send My Current Location"
        case "shareCurrentLocation": return "Share Current Location"
        case "shareMyCurrentLocation": return "Share My Current Location"
        default: return "Current Location"
        }
    }
}
