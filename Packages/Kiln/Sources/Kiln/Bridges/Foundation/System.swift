//
//  System.swift
//  Bridges: the system, as an app sees it (Round 2C)
//
//  `Bundle.main`, `ProcessInfo`, `UIDevice`, `UIFont`, `NotificationCenter`
//  and `Notification`, `Logger` and `os_log`, `DispatchGroup`,
//  `DispatchSemaphore`, `DispatchTime`, `DispatchQueue(label:)`, `RunLoop`
//  and `OperationQueue`. Everything runs on the main actor: a group's
//  `notify` runs when its work has left, and a semaphore never blocks (it
//  can't: the main actor would stop).
//

import SwiftUI
import os
#if canImport(UIKit)
import UIKit
#endif

/// A `Notification.Name`.
struct KNotificationName: Hashable, KDescribable {
    let raw: String
    /// One the system posts (`UIApplication.didBecomeActiveNotification`), heard from the real center too.
    var system = false
    var kv: KV { .native(.boxed(KBoxed("Notification.Name", self))) }
    func describe(_ interp: KInterpreter) -> String { "NSNotificationName(_rawValue: \(raw))" }
    static func from(_ v: KV?) -> KNotificationName? {
        if case .native(.boxed(let b))? = v { return b.value.base as? KNotificationName }
        if case .string(let s)? = v { return KNotificationName(raw: s) }
        return nil
    }
}

/// A run's own notification center: what the app posts stays in the app.
@MainActor
final class KNotifications {
    let center = NotificationCenter()
    var observers: [NSObjectProtocol] = []

    static func of(_ c: KCall) -> KNotifications {
        if let n = c.context.provided(KNotifications.self) { return n }
        let n = KNotifications()
        c.context.provide(n)
        c.context.onTearDown { [weak n] in
            guard let n else { return }
            for o in n.observers { n.center.removeObserver(o); NotificationCenter.default.removeObserver(o) }
            n.observers = []
        }
        return n
    }

    /// Observes `name` in the run's center (and the system's, for a system name).
    func observe(_ name: KNotificationName?, _ block: @escaping @MainActor (Notification) -> Void) -> [NSObjectProtocol] {
        let n = name.map { Notification.Name($0.raw) }
        var tokens = [center.addObserver(forName: n, object: nil, queue: .main) { note in MainActor.assumeIsolated { block(note) } }]
        if name?.system == true {
            tokens.append(NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { note in MainActor.assumeIsolated { block(note) } })
        }
        observers += tokens
        return tokens
    }

    static func value(_ note: Notification) -> KV {
        var info: [KV: KV] = [:]
        for (k, v) in note.userInfo ?? [:] { info[KNativeValues.kv(from: k.base)] = KNativeValues.kv(from: v) }
        return .native(.boxed(KBoxed("Notification", KNotificationValue(name: note.name.rawValue, object: KNativeValues.kv(from: note.object),
                                                                         userInfo: note.userInfo == nil ? .nilValue : .dict(info)))))
    }
}

struct KNotificationValue: Hashable {
    let name: String
    let object: KV
    let userInfo: KV
}

/// A `DispatchGroup`: how much work is in it, and what to run when it's empty.
@MainActor
final class KDispatchGroup {
    var count = 0
    var waiting: [() -> Void] = []
    func leave() {
        count = max(0, count - 1)
        if count == 0 { let w = waiting; waiting = []; w.forEach { DispatchQueue.main.async(execute: $0) } }
    }
}

extension FoundationBridges {
    static func systemMore(_ r: KRegistry) {
        r.type("Bundle", .foundation, support: .partial,
               notes: "`Bundle.main`: Shelf's bundle identifier with the app's name, its version, and `infoDictionary`; an app has no resources of its own.") { t in
            t.staticProperty("main") { _ in .native(.object("Bundle", KRef(Bundle.main))) }
            @MainActor func info(_ c: KCall) -> [String: Any] {
                var d = Bundle.main.infoDictionary ?? [:]
                d["CFBundleName"] = c.context.name
                d["CFBundleDisplayName"] = c.context.name
                return d
            }
            t.property("bundleIdentifier") { c in .string((Bundle.main.bundleIdentifier ?? "app.shelf") + "." + c.context.slug) }
            t.property("infoDictionary") { c in fromPlist(info(c)) }
            t.property("bundleURL") { c in .native(.url(c.context.files.root)) }
            t.property("bundlePath") { c in .string(c.context.files.root.path) }
            t.property("resourceURL") { c in .native(.url(c.context.files.root)) }
            t.method("object", "forInfoDictionaryKey:string") { c in info(c)[c.string("forInfoDictionaryKey") ?? ""].map(fromPlist) ?? .nilValue }
            t.method("url", "forResource:any withExtension:any?") { _ in .nilValue }
            t.method("path", "forResource:any ofType:any?") { _ in .nilValue }
            t.method("localizedString", "forKey:string value:any? table:any?") { c in .string(c.string("value") ?? c.string("forKey") ?? "") }
        }

        r.type("ProcessInfo", .foundation, support: .full,
               notes: "`ProcessInfo.processInfo`: `systemUptime`, `processorCount`, `physicalMemory`, `isLowPowerModeEnabled`, `thermalState`, `operatingSystemVersion`, `globallyUniqueString`.") { t in
            t.staticProperty("processInfo") { _ in .native(.object("ProcessInfo", KRef(ProcessInfo.processInfo))) }
            let p = ProcessInfo.processInfo
            t.property("systemUptime") { _ in .double(p.systemUptime) }
            t.property("processorCount") { _ in .int(p.processorCount) }
            t.property("activeProcessorCount") { _ in .int(p.activeProcessorCount) }
            t.property("physicalMemory") { _ in KFixedInt(.uint64, bits: p.physicalMemory).kv }
            t.property("isLowPowerModeEnabled") { _ in .bool(p.isLowPowerModeEnabled) }
            t.property("thermalState") { _ in
                let s: String
                switch p.thermalState {
                case .nominal: s = "nominal"
                case .fair: s = "fair"
                case .serious: s = "serious"
                default: s = "critical"
                }
                return .native(.implicit(s, []))
            }
            t.property("globallyUniqueString") { _ in .string(p.globallyUniqueString) }
            t.property("processName") { c in .string(c.context.name) }
            t.property("environment") { _ in .dict([:]) }
            t.property("arguments") { _ in .array([]) }
            t.property("operatingSystemVersionString") { _ in .string(p.operatingSystemVersionString) }
            t.property("operatingSystemVersion") { _ in
                let v = p.operatingSystemVersion
                return .tuple([.int(v.majorVersion), .int(v.minorVersion), .int(v.patchVersion)], ["majorVersion", "minorVersion", "patchVersion"])
            }
            t.property("isiOSAppOnMac") { _ in .bool(p.isiOSAppOnMac) }
            t.method("isOperatingSystemAtLeast", "_:any") { c in
                guard case .tuple(let v, _)? = c.first, v.count == 3 else { return .bool(true) }
                return .bool(p.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: v[0].asInt ?? 0, minorVersion: v[1].asInt ?? 0, patchVersion: v[2].asInt ?? 0)))
            }
        }
        r.type("OperatingSystemVersion", .foundation, support: .full) { t in
            t.initializer("majorVersion:number minorVersion:number patchVersion:number") { c in
                .tuple([.int(c.int("majorVersion") ?? 0), .int(c.int("minorVersion") ?? 0), .int(c.int("patchVersion") ?? 0)], ["majorVersion", "minorVersion", "patchVersion"])
            }
        }

        r.type("UIDevice", .foundation, support: .full,
               notes: "`UIDevice.current`: `systemName`, `systemVersion`, `model`, `name`, `userInterfaceIdiom`, `orientation`, `batteryLevel`, `batteryState`.") { t in
            #if canImport(UIKit)
            t.staticProperty("current") { _ in .native(.object("UIDevice", KRef(UIDevice.current))) }
            let d = UIDevice.current
            t.property("systemName") { _ in .string(d.systemName) }
            t.property("systemVersion") { _ in .string(d.systemVersion) }
            t.property("model") { _ in .string(d.model) }
            t.property("localizedModel") { _ in .string(d.localizedModel) }
            t.property("name") { _ in .string(d.name) }
            t.property("identifierForVendor") { _ in d.identifierForVendor.map { .native(.uuid($0)) } ?? .nilValue }
            t.property("userInterfaceIdiom") { _ in .native(.implicit(d.userInterfaceIdiom == .pad ? "pad" : "phone", [])) }
            t.property("orientation") { _ in
                let o: String
                switch d.orientation {
                case .portrait: o = "portrait"
                case .portraitUpsideDown: o = "portraitUpsideDown"
                case .landscapeLeft: o = "landscapeLeft"
                case .landscapeRight: o = "landscapeRight"
                case .faceUp: o = "faceUp"
                case .faceDown: o = "faceDown"
                default: o = "unknown"
                }
                return .native(.implicit(o, []))
            }
            t.property("isBatteryMonitoringEnabled", { _ in .bool(d.isBatteryMonitoringEnabled) }, set: { c in d.isBatteryMonitoringEnabled = c.first?.asBool ?? false })
            t.property("batteryLevel") { _ in .double(Double(d.batteryLevel)) }
            t.property("batteryState") { _ in
                let s: String
                switch d.batteryState {
                case .charging: s = "charging"
                case .full: s = "full"
                case .unplugged: s = "unplugged"
                default: s = "unknown"
                }
                return .native(.implicit(s, []))
            }
            #else
            // A Mac (the tests, KilnDiff): the same members, the Mac's values.
            t.staticProperty("current") { _ in .native(.object("UIDevice", KRef(NSObject()))) }
            t.property("systemName") { _ in .string("macOS") }
            t.property("systemVersion") { _ in .string(ProcessInfo.processInfo.operatingSystemVersionString) }
            t.properties(["model", "localizedModel"]) { _, _ in .string("Mac") }
            t.property("name") { _ in .string(Host.current().localizedName ?? "Mac") }
            t.property("userInterfaceIdiom") { _ in .native(.implicit("mac", [])) }
            t.property("orientation") { _ in .native(.implicit("unknown", [])) }
            t.property("batteryLevel") { _ in .double(-1) }
            t.property("batteryState") { _ in .native(.implicit("unknown", [])) }
            #endif
        }

        r.type("UIFont", .foundation, support: .full,
               notes: "`UIFont.preferredFont(forTextStyle:)`, `systemFont(ofSize:weight:)`: `pointSize`, `lineHeight`; `Font(uiFont)` shows it.") { t in
            #if canImport(UIKit)
            func style(_ s: String?) -> UIFont.TextStyle {
                let all: [String: UIFont.TextStyle] = ["largeTitle": .largeTitle, "title1": .title1, "title2": .title2, "title3": .title3,
                    "headline": .headline, "subheadline": .subheadline, "body": .body, "callout": .callout, "footnote": .footnote,
                    "caption1": .caption1, "caption2": .caption2]
                return s.flatMap { all[$0] } ?? .body
            }
            func weight(_ s: String?) -> UIFont.Weight {
                let all: [String: UIFont.Weight] = ["ultraLight": .ultraLight, "thin": .thin, "light": .light, "regular": .regular,
                    "medium": .medium, "semibold": .semibold, "bold": .bold, "heavy": .heavy, "black": .black]
                return s.flatMap { all[$0] } ?? .regular
            }
            t.staticMethod("preferredFont", "forTextStyle:any") { c in .native(.object("UIFont", KRef(UIFont.preferredFont(forTextStyle: style(c.symbol("forTextStyle")))))) }
            t.staticMethod("systemFont", "ofSize:number weight:any?") { c in
                .native(.object("UIFont", KRef(UIFont.systemFont(ofSize: c.cg("ofSize") ?? 17, weight: weight(c.symbol("weight"))))))
            }
            t.staticMethod("boldSystemFont", "ofSize:number") { c in .native(.object("UIFont", KRef(UIFont.boldSystemFont(ofSize: c.cg("ofSize") ?? 17)))) }
            t.staticMethod("italicSystemFont", "ofSize:number") { c in .native(.object("UIFont", KRef(UIFont.italicSystemFont(ofSize: c.cg("ofSize") ?? 17)))) }
            t.staticMethod("monospacedSystemFont", "ofSize:number weight:any") { c in
                .native(.object("UIFont", KRef(UIFont.monospacedSystemFont(ofSize: c.cg("ofSize") ?? 17, weight: weight(c.symbol("weight"))))))
            }
            t.staticMethod("monospacedDigitSystemFont", "ofSize:number weight:any") { c in
                .native(.object("UIFont", KRef(UIFont.monospacedDigitSystemFont(ofSize: c.cg("ofSize") ?? 17, weight: weight(c.symbol("weight"))))))
            }
            t.initializer("name:string size:number") { c in UIFont(name: c.string("name") ?? "", size: c.cg("size") ?? 17).map { .native(.object("UIFont", KRef($0))) } ?? .nilValue }
            t.staticProperty("systemFontSize") { _ in .double(UIFont.systemFontSize) }
            t.staticProperty("labelFontSize") { _ in .double(UIFont.labelFontSize) }
            t.staticProperty("familyNames") { _ in .array(UIFont.familyNames.map { .string($0) }) }
            @MainActor func f(_ c: KCall) -> UIFont { c.object(UIFont.self) ?? .preferredFont(forTextStyle: .body) }
            t.property("pointSize") { c in .double(f(c).pointSize) }
            t.property("lineHeight") { c in .double(f(c).lineHeight) }
            t.property("ascender") { c in .double(f(c).ascender) }
            t.property("descender") { c in .double(f(c).descender) }
            t.property("capHeight") { c in .double(f(c).capHeight) }
            t.property("xHeight") { c in .double(f(c).xHeight) }
            t.property("fontName") { c in .string(f(c).fontName) }
            t.property("familyName") { c in .string(f(c).familyName) }
            t.method("withSize", "_:number") { c in .native(.object("UIFont", KRef(f(c).withSize(c.cg(0) ?? f(c).pointSize)))) }
            #endif
        }

        r.extend("UIScreen") { t in
            #if canImport(UIKit)
            t.property("scale") { _ in .double(Double(UITraitCollection.current.displayScale > 0 ? UITraitCollection.current.displayScale : 3)) }
            t.property("nativeScale") { _ in .double(Double(UITraitCollection.current.displayScale > 0 ? UITraitCollection.current.displayScale : 3)) }
            #else
            t.property("scale") { _ in .double(2) }
            #endif
        }

        // MARK: Notifications

        r.type("NotificationCenter", .foundation, support: .full,
               notes: "`NotificationCenter.default`: `post`, `addObserver(forName:object:queue:using:)`, `removeObserver`, `publisher(for:)`. What an app posts stays in the app; it hears the system's (`UIApplication.didBecomeActiveNotification`).") { t in
            t.staticProperty("default") { _ in .native(.object("NotificationCenter", KRef(NSObject()))) }
            t.method("post", "name:Notification.Name object:any? userInfo:any?") { c in
                guard let n = KNotificationName.from(c["name"]) else { throw c.fail("needs a Notification.Name") }
                var info: [AnyHashable: Any]?
                if case .dict(let d)? = c["userInfo"] {
                    info = [:]
                    for (k, v) in d { if let key = KNativeValues.native(from: k) as? AnyHashable { info?[key] = KNativeValues.native(from: v) ?? NSNull() } }
                }
                KNotifications.of(c).center.post(name: Notification.Name(n.raw), object: nil, userInfo: info)
                return .void
            }
            t.method("post", "_:any") { c in
                guard case .native(.boxed(let b))? = c.first, let note = b.value.base as? KNotificationValue else { throw c.fail("needs a Notification") }
                KNotifications.of(c).center.post(name: Notification.Name(note.name), object: nil)
                return .void
            }
            t.method("addObserver", "forName:Notification.Name? object:any queue:any using:closure") { c in
                guard case .function(let f)? = c["using"] else { throw c.fail("needs a closure") }
                let interp = c.interp
                let tokens = KNotifications.of(c).observe(KNotificationName.from(c["forName"])) { note in interp.perform(f, [KNotifications.value(note)]) }
                return .native(.object("NSObjectProtocol", KRef(tokens as NSArray)))
            }
            t.method("addObserver", "_:any selector:any name:any object:any") { c in
                throw c.fail("Kiln has no selectors: use addObserver(forName:object:queue:) with a closure, or publisher(for:)")
            }
            t.method("removeObserver", "_:any") { c in
                let n = KNotifications.of(c)
                if case .native(.object(_, let ref))? = c.first, let tokens = ref.value as? [NSObjectProtocol] {
                    for o in tokens { n.center.removeObserver(o); NotificationCenter.default.removeObserver(o) }
                }
                return .void
            }
            t.method("removeObserver", "_:any name:any object:any?") { _ in .void }
            t.method("publisher", "for:Notification.Name object:any?") { c in
                let name = KNotificationName.from(c["for"])
                let notes = KNotifications.of(c)
                return KMadePub("NotificationCenter.Publisher") { s, token in
                    let tokens = notes.observe(name) { note in if !token.cancelled { try? s.onValue(KNotifications.value(note)) } }
                    token.add { for o in tokens { notes.center.removeObserver(o); NotificationCenter.default.removeObserver(o) } }
                }.kv
            }
            t.method("notifications", "named:any object:any?") { c in
                throw c.fail("Kiln has no notifications(named:) sequence yet: use publisher(for:) with .onReceive, or addObserver(forName:)")
            }
        }
        r.type("Notification", .foundation, support: .full, notes: "`name`, `object`, `userInfo`.") { t in
            t.initializer("name:any object:any? userInfo:any?") { c in
                .native(.boxed(KBoxed("Notification", KNotificationValue(name: KNotificationName.from(c["name"])?.raw ?? "", object: c["object"] ?? .nilValue, userInfo: c["userInfo"] ?? .nilValue))))
            }
            @MainActor func n(_ c: KCall) -> KNotificationValue? { if case .native(.boxed(let b)) = c.receiver { return b.value.base as? KNotificationValue }; return nil }
            t.property("name") { c in KNotificationName(raw: n(c)?.name ?? "").kv }
            t.property("object") { c in n(c)?.object ?? .nilValue }
            t.property("userInfo") { c in n(c)?.userInfo ?? .nilValue }
        }
        r.type("Notification.Name", .foundation, support: .full) { t in
            t.initializer("_:string") { c in KNotificationName(raw: c.string(0) ?? "").kv }
            t.initializer("rawValue:string") { c in KNotificationName(raw: c.string("rawValue") ?? "").kv }
            t.implicit { name, args, _ in
                if name == "init", let s = args.first?.asString { return KNotificationName(raw: s).kv }
                return nil
            }
            t.property("rawValue") { c in .string(KNotificationName.from(c.receiver)?.raw ?? "") }
            t.operator("<") { _, _, _ in nil }
        }
        r.alias("NSNotification.Name", to: "Notification.Name")
        // The system's notifications an app listens for.
        #if canImport(UIKit)
        let system: [(String, Notification.Name)] = [
            ("didBecomeActiveNotification", UIApplication.didBecomeActiveNotification),
            ("willResignActiveNotification", UIApplication.willResignActiveNotification),
            ("didEnterBackgroundNotification", UIApplication.didEnterBackgroundNotification),
            ("willEnterForegroundNotification", UIApplication.willEnterForegroundNotification),
            ("didReceiveMemoryWarningNotification", UIApplication.didReceiveMemoryWarningNotification),
            ("significantTimeChangeNotification", UIApplication.significantTimeChangeNotification),
            ("userDidTakeScreenshotNotification", UIApplication.userDidTakeScreenshotNotification),
        ]
        r.extend("UIApplication") { t in
            for (name, n) in system { t.staticProperty(name) { _ in KNotificationName(raw: n.rawValue, system: true).kv } }
        }
        r.extend("UIDevice") { t in
            t.staticProperty("orientationDidChangeNotification") { _ in KNotificationName(raw: UIDevice.orientationDidChangeNotification.rawValue, system: true).kv }
            t.staticProperty("batteryLevelDidChangeNotification") { _ in KNotificationName(raw: UIDevice.batteryLevelDidChangeNotification.rawValue, system: true).kv }
        }
        #endif
        r.extend("NotificationCenter") { t in t.staticProperty("NSCalendarDayChanged") { _ in KNotificationName(raw: Notification.Name.NSCalendarDayChanged.rawValue, system: true).kv } }

        // MARK: Logging

        r.type("Logger", .foundation, support: .full, notes: "`Logger(subsystem:category:)`: `debug`, `info`, `notice`, `error`, `fault`, `log` go to the device's log.") { t in
            t.initializer("") { _ in .native(.object("Logger", KRef(KLoggerBox(Logger())))) }
            t.initializer("subsystem:string category:string") { c in
                .native(.object("Logger", KRef(KLoggerBox(Logger(subsystem: c.string("subsystem") ?? "app", category: c.string("category") ?? "")))))
            }
            for level in ["debug", "info", "notice", "error", "fault", "warning", "critical", "trace", "log"] {
                t.method(level, "_:any") { c in
                    let text = c.interp.describe(c.first ?? .string(""))
                    if let l = c.object(KLoggerBox.self)?.logger {
                        switch level {
                        case "debug", "trace": l.debug("\(text, privacy: .public)")
                        case "info": l.info("\(text, privacy: .public)")
                        case "error", "warning": l.error("\(text, privacy: .public)")
                        case "fault", "critical": l.fault("\(text, privacy: .public)")
                        default: l.notice("\(text, privacy: .public)")
                        }
                    }
                    return .void
                }
            }
            t.method("log", "level:any _:any") { c in
                let text = c.interp.describe(c.at(1) ?? .string(""))
                c.object(KLoggerBox.self)?.logger.notice("\(text, privacy: .public)")
                return .void
            }
        }
        r.function("os_log", .foundation, "_:any _:any...", owner: "os") { c in
            let fmt = c.interp.describe(c.first ?? .string(""))
            let text = KFormatting.format(fmt, Array(c.args.dropFirst()), c.interp)
            Logger().notice("\(text, privacy: .public)")
            return .void
        }
        r.type("OSLog", .foundation, support: .full) { t in
            t.initializer("subsystem:string category:string") { _ in .native(.object("OSLog", KRef(NSObject()))) }
            t.staticProperty("default") { _ in .native(.object("OSLog", KRef(NSObject()))) }
        }

        // MARK: Dispatch

        r.type("DispatchGroup", .foundation, support: .full, notes: "`enter`, `leave`, `notify(queue:execute:)`: on the main actor; `wait()` doesn't block.") { t in
            t.initializer("") { _ in .native(.object("DispatchGroup", KRef(KDispatchGroup()))) }
            @MainActor func g(_ c: KCall) -> KDispatchGroup? { c.object(KDispatchGroup.self) }
            t.method("enter", "") { c in g(c)?.count += 1; return .void }
            t.method("leave", "") { c in g(c)?.leave(); return .void }
            t.method("notify", "queue:any execute:closure") { c in
                guard case .function(let f)? = c["execute"], let group = g(c) else { throw c.fail("needs a closure") }
                let interp = c.interp
                let run = { MainActor.assumeIsolated { interp.perform(f) } }
                if group.count == 0 { DispatchQueue.main.async(execute: run) } else { group.waiting.append(run) }
                return .void
            }
            t.method("wait", "timeout:any?") { _ in .native(.implicit("success", [])) }
        }
        r.type("DispatchSemaphore", .foundation, support: .full, notes: "`wait()` and `signal()` count, but never block: Kiln's code is on the main actor.") { t in
            t.initializer("value:number") { c in .native(.object("DispatchSemaphore", KRef(NSMutableArray(object: c.int("value") ?? 0)))) }
            t.method("wait", "timeout:any?") { _ in .native(.implicit("success", [])) }
            t.method("signal", "") { _ in .int(0) }
        }
        r.type("DispatchTime", .foundation, support: .full, notes: "`.now()` and `+ seconds`, for `asyncAfter(deadline:)`.") { t in
            t.staticMethod("now", "") { _ in .native(.date(Date())) }
            t.implicit { name, args, _ in name == "now" && args.isEmpty ? .native(.date(Date())) : nil }
            t.staticProperty("distantFuture") { _ in .native(.date(.distantFuture)) }
        }
        r.extend("DispatchQueue") { t in
            t.initializer("label:string qos:any? attributes:any?") { c in .native(.object("DispatchQueue", KRef(KQueueLabel(label: c.string("label") ?? "")))) }
            t.property("label") { c in .string(c.object(KQueueLabel.self)?.label ?? "com.apple.main-thread") }
        }
        r.type("RunLoop", .foundation, support: .full, notes: "`RunLoop.main`, as a scheduler (`debounce(for:scheduler:)`).") { t in
            t.staticProperty("main") { _ in .native(.object("RunLoop", KRef(RunLoop.main))) }
            t.staticProperty("current") { _ in .native(.object("RunLoop", KRef(RunLoop.main))) }
            t.method("add", "_:any forMode:any") { _ in .void }
        }
        r.type("OperationQueue", .foundation, support: .full, notes: "`OperationQueue.main`: `addOperation` runs on the main actor.") { t in
            t.staticProperty("main") { _ in .native(.object("OperationQueue", KRef(OperationQueue.main))) }
            t.initializer("") { _ in .native(.object("OperationQueue", KRef(OperationQueue.main))) }
            t.property("maxConcurrentOperationCount", { _ in .int(1) }, set: { _ in })
            t.method("addOperation", "_:closure") { c in
                if case .function(let f)? = c.first { let interp = c.interp; DispatchQueue.main.async { MainActor.assumeIsolated { interp.perform(f) } } }
                return .void
            }
        }
    }
}

/// A `Logger`.
final class KLoggerBox {
    let logger: Logger
    init(_ l: Logger) { logger = l }
}

/// `DispatchQueue(label:)`: work on it runs on the main actor.
final class KQueueLabel {
    let label: String
    init(label: String) { self.label = label }
}
