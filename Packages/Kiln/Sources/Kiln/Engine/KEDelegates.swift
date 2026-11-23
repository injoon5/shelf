//
//  KEDelegates.swift
//  Kiln's engine
//
//  An app class adopting a native delegate protocol (PLAN.md §1.5):
//
//      class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
//          func imagePickerController(_ picker: UIImagePickerController,
//                                     didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { … }
//      }
//      picker.delegate = context.coordinator
//
//  The bridge that takes a delegate (`UIImagePickerController.delegate`,
//  later `CLLocationManager.delegate`) asks `KDelegates.proxy(for:)` for the
//  native object: a `KilnForwardingProxy` (Sources/KilnObjC) conforming at
//  run time to every Objective-C delegate protocol the class adopts, which
//  answers `respondsToSelector:` with what the app implements and calls the
//  app's method for each message, its arguments converted (`KNativeValues`).
//  One proxy per app object, kept alive by the object it's the delegate of,
//  and emptied at teardown.
//
//  A delegate protocol that's Swift-only (`DataScannerViewControllerDelegate`)
//  can't be forwarded by the runtime: its family writes a native class that
//  calls `KAppValue` itself, and declares it as the protocol's `proxy`.
//

import Foundation
import KilnObjC
import ObjectiveC

/// What a delegate protocol's proxy needs beyond its requirements.
@MainActor
final class KDelegateSpec {
    /// The Objective-C protocol the proxy conforms to, by name: it's looked
    /// up when a proxy is made, so the declaration registers everywhere (the
    /// manifest is written on the Mac) and works where the framework exists.
    let objcName: String
    var objcProtocol: Protocol? { objc_getProtocol(objcName) }
    /// Requirement (`imagePickerController(_:didFinishPickingMediaWithInfo:)`)
    /// → converts the native arguments; the default is `KNativeValues.kv(from:)`.
    var arguments: [String: @MainActor ([Any], KInterpreter) -> [KV]] = [:]
    /// Requirement → the Objective-C selector, where Swift names it differently.
    var selectors: [String: String] = [:]

    init(_ name: String) { objcName = name }

    /// `argument("imagePickerController(_:didFinishPickingMediaWithInfo:)") { args, interp in … }`.
    func arguments(_ requirement: String, _ convert: @escaping @MainActor ([Any], KInterpreter) -> [KV]) {
        arguments[requirement] = convert
    }
}

extension KRegistry {
    /// A native delegate protocol an app's class can adopt. Its requirements
    /// are the delegate's methods, as Swift names them; all are optional
    /// unless the protocol requires them. Bridges that take the delegate call
    /// `KDelegates.proxy(for:)`.
    @discardableResult
    func delegateProtocol(_ name: String, _ family: KilnFamily, objc: String? = nil, requirements: [String], support: KilnSupport = .full,
                          introduced: String? = nil, notes: String? = nil, file: String = #fileID,
                          _ configure: (@MainActor (KDelegateSpec) -> Void)? = nil) -> KProtocolBridge {
        let b = protocolBridge(name, family, requirements: requirements, support: support, introduced: introduced, notes: notes, file: file) { app in
            KDelegates.proxy(app) as Any
        }
        let spec = KDelegateSpec(objc ?? name)
        configure?(spec)
        b.delegate = spec
        return b
    }

    /// A native class whose instances reach the app (as a delegate's
    /// argument, a property): their values are `.native(.object(name, …))`.
    func nativeClass(_ cls: AnyClass, _ name: String) {
        KNativeValues.classNames[NSStringFromClass(cls)] = name
    }
}

@MainActor
enum KDelegates {
    /// The Objective-C selector for a requirement: `locationManager(_:didUpdateLocations:)`
    /// is `locationManager:didUpdateLocations:`, `foo(bar:)` is `fooWithBar:`.
    static func selector(for r: KRequirement, spec: KDelegateSpec?) -> String {
        if let s = spec?.selectors[r.display] { return s }
        guard let labels = r.labels, !labels.isEmpty else { return r.name }
        var s = r.name
        if let first = labels[0] { s += "With" + first.prefix(1).uppercased() + first.dropFirst() }
        s += ":"
        for l in labels.dropFirst() { s += (l ?? "") + ":" }
        return s
    }

    /// The native delegate for an app object, or nil when the value isn't an
    /// app class adopting one of the registry's delegate protocols.
    static func proxy(for v: KV, _ interp: KInterpreter) -> AnyObject? {
        guard case .object = v, let app = KAppValue(v, interp) else { return nil }
        return proxy(app)
    }

    static func proxy(_ app: KAppValue) -> AnyObject? {
        guard case .object(let obj) = app.value else { return nil }
        let interp = app.interp
        let key = ObjectIdentifier(obj)
        if let cached = interp.delegateProxies[key] { return cached.proxy }

        // Every delegate protocol the class adopts, and the selectors they declare.
        var protocols: [Protocol] = []
        var bySelector: [String: (KRequirement, KDelegateSpec)] = [:]
        for name in app.type.conformances.sorted() {
            guard let b = interp.registry.protocols[name], let spec = b.delegate, let p = spec.objcProtocol else { continue }
            protocols.append(p)
            for r in b.members where r.isMethod && !r.isStatic { bySelector[selector(for: r, spec: spec)] = (r, spec) }
        }
        guard !protocols.isEmpty else { return nil }

        let holder = KDelegateTarget(app)
        let proxy = KilnForwardingProxy(protocols: protocols, responds: { sel in
            onMain {
                guard let app = holder.app, let (r, _) = bySelector[NSStringFromSelector(sel)] else { return false }
                return app.implements(r.name, labels: r.labels)
            }
        }, handler: { sel, args in
            onMain {
                guard var app = holder.app, let (r, spec) = bySelector[NSStringFromSelector(sel)] else { return nil }
                let interp = app.interp
                let values = spec.arguments[r.display]?(args, interp) ?? args.map { KNativeValues.kv(from: $0) }
                let result = app.callReporting(r.name, values, labels: r.labels ?? [], fallback: .nilValue)
                // A delegate method that waits runs as a task; the framework doesn't wait for it.
                if let s = result.asSuspension {
                    interp.startTask(s, parent: nil, reportsErrors: true)
                    return nil
                }
                return KNativeValues.native(from: result)
            }
        })
        interp.delegateProxies[key] = (obj, proxy)
        _ = interp.context.onTearDown {
            holder.app = nil
            proxy.kilnInvalidate()
        }
        return proxy
    }

    /// Keeps `delegate` alive as long as `owner` (delegates are weak).
    static func retain(_ delegate: AnyObject?, by owner: AnyObject) {
        objc_setAssociatedObject(owner, &retainKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    nonisolated(unsafe) private static var retainKey: UInt8 = 0

    /// Delegate messages arrive on the main thread from UIKit; anything else
    /// (a framework's own queue) waits for the main actor.
    nonisolated static func onMain<T>(_ body: @MainActor () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try MainActor.assumeIsolated(body) }
        return try DispatchQueue.main.sync { try MainActor.assumeIsolated(body) }
    }
}

/// What a delegate proxy calls: the app object, until teardown.
@MainActor
final class KDelegateTarget {
    var app: KAppValue?
    init(_ app: KAppValue) { self.app = app }
}

// MARK: - Native values, both ways

/// Converts what native code hands the app (a delegate's arguments, a
/// property) into Kiln's values, and back.
@MainActor
enum KNativeValues {
    /// `NSStringFromClass` → the bridge's type name (`UIImage`).
    static var classNames: [String: String] = [:]

    static func kv(from any: Any?) -> KV {
        guard let any, !(any is NSNull) else { return .nilValue }
        switch any {
        case let v as KV: return v
        case let s as String: return .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            let t = String(cString: n.objCType)
            return t == "d" || t == "f" ? .double(n.doubleValue) : .int(n.intValue)
        case let u as URL: return .native(.url(u))
        case let d as Date: return .native(.date(d))
        case let u as UUID: return .native(.uuid(u))
        case let d as Data: return .native(.object("Data", KRef(d as NSData)))
        case let a as [Any]: return .array(a.map { kv(from: $0) })
        case let d as [AnyHashable: Any]:
            var out: [KV: KV] = [:]
            for (k, v) in d { out[kv(from: k.base)] = kv(from: v) }
            return .dict(out)
        case let e as NSError:
            return .native(.object("Error", KRef(e)))
        case let v as NSValue:
            let t = String(cString: v.objCType)
            if t.hasPrefix("{CGPoint") { let p = v.pointValue; return .native(.point(p.x, p.y)) }
            if t.hasPrefix("{CGSize") { let s = v.sizeValue; return .native(.size(s.width, s.height)) }
            if t.hasPrefix("{CGRect") { let r = v.rectValue; return .native(.rect(r.minX, r.minY, r.width, r.height)) }
            return .native(.object("NSValue", KRef(v)))
        case let o as AnyObject:
            return .native(.object(typeName(of: o), KRef(o)))
        }
    }

    /// The bridge's name for a native object's class: its own, or the
    /// nearest superclass's that's registered.
    static func typeName(of o: AnyObject) -> String {
        var c: AnyClass? = object_getClass(o)
        while let cls = c {
            if let n = classNames[NSStringFromClass(cls)] { return n }
            c = class_getSuperclass(cls)
        }
        return String(describing: type(of: o))
    }

    static func native(from v: KV) -> Any? {
        switch v {
        case .void, .nilValue: return nil
        case .bool(let b): return NSNumber(value: b)
        case .int(let i): return NSNumber(value: i)
        case .double(let d): return NSNumber(value: d)
        case .string(let s): return s as NSString
        case .array(let a): return a.map { native(from: $0) ?? NSNull() } as NSArray
        case .dict(let d):
            let out = NSMutableDictionary()
            for (k, val) in d { if let nk = native(from: k) as? NSCopying { out[nk] = native(from: val) ?? NSNull() } }
            return out
        case .native(.url(let u)): return u as NSURL
        case .native(.date(let d)): return d as NSDate
        case .native(.uuid(let u)): return u as NSUUID
        case .native(.point(let x, let y)): return NSValue(point: CGPoint(x: x, y: y))
        case .native(.size(let w, let h)): return NSValue(size: CGSize(width: w, height: h))
        case .native(.rect(let x, let y, let w, let h)): return NSValue(rect: CGRect(x: x, y: y, width: w, height: h))
        case .native(.object(_, let ref)): return ref.value
        case .native(.boxed(let b)): return b.value.base
        default: return nil
        }
    }
}

#if canImport(UIKit)
import UIKit
extension NSValue {
    convenience init(point: CGPoint) { self.init(cgPoint: point) }
    convenience init(size: CGSize) { self.init(cgSize: size) }
    convenience init(rect: CGRect) { self.init(cgRect: rect) }
    var pointValue: CGPoint { cgPointValue }
    var sizeValue: CGSize { cgSizeValue }
    var rectValue: CGRect { cgRectValue }
}
#endif

// MARK: - Swift-only delegate protocols

/// The base of a hand-written proxy for a delegate protocol the Objective-C
/// runtime can't forward (a Swift-only one, like VisionKit's
/// `DataScannerViewControllerDelegate`). Subclass it, conform to the
/// protocol, and forward each method:
///
///     final class KDataScannerDelegate: KAppDelegateObject, DataScannerViewControllerDelegate {
///         func dataScanner(_ s: DataScannerViewController, didTapOn item: RecognizedItem) {
///             forward("dataScanner(_:didTapOn:)", [KNativeValues.kv(from: s), item.kv])
///         }
///     }
///
/// and declare it as the protocol's proxy:
/// `r.protocolBridge("DataScannerViewControllerDelegate", .vision, requirements: […]) { KDataScannerDelegate($0) }`.
/// A method the app doesn't write isn't called; after teardown nothing is.
@MainActor
class KAppDelegateObject: NSObject {
    private(set) var app: KAppValue?

    init(_ app: KAppValue) {
        self.app = app
        super.init()
        _ = app.interp.context.onTearDown { [weak self] in self?.app = nil }
    }

    /// Calls the app's method for `requirement` (`"dataScanner(_:didTapOn:)"`)
    /// if it has one; its result, or nil.
    @discardableResult
    func forward(_ requirement: String, _ args: [KV]) -> KV? {
        let r = KRequirement(parsing: requirement)
        guard var a = app, a.implements(r.name, labels: r.labels) else { return nil }
        let result = a.callReporting(r.name, args, labels: r.labels ?? [], fallback: .nilValue)
        if let s = result.asSuspension { a.interp.startTask(s, parent: nil, reportsErrors: true); return nil }
        return result
    }
}
