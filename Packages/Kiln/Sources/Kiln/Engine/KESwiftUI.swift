//
//  KESwiftUI.swift
//  Kiln engine 2
//
//  The SwiftUI side of the value model: native values (colors, fonts, dates,
//  format styles, timers) and view descriptions — the tree a view body
//  evaluates to, which KERenderer turns into real SwiftUI views.
//

import SwiftUI

/// Wraps a reference (or a non-Hashable value) with identity equality.
final class KRef<T>: Hashable {
    let value: T
    init(_ value: T) { self.value = value }
    static func == (a: KRef<T>, b: KRef<T>) -> Bool {
        if a === b { return true }
        // `Data` is held as an `NSData`: two compare by their bytes, as Swift's do.
        if let x = a.value as? NSData, let y = b.value as? NSData { return x.isEqual(to: y as Data) }
        return false
    }
    func hash(into h: inout Hasher) {
        if let d = value as? NSData { h.combine(d.length); return }
        h.combine(ObjectIdentifier(self))
    }
}

/// A grid column or row: GridItem(.flexible(), spacing: 12).
struct KGridItem: Hashable {
    enum Size: Hashable { case flexible(Double, Double), fixed(Double), adaptive(Double, Double) }
    var size: Size
    var spacing: Double?
    var alignment: String?
}

/// A format style: .currency(code:), .number, .percent, .dateTime …
struct KFormat: Hashable {
    /// `named`: a format style by its name (`byteCount`, `list`, `iso8601`, `interval`…), Bridges/Foundation/FormatStyles.swift.
    enum Kind: Hashable { case currency(String), number, percent, dateTime, date(String, String), relative, list, named(String) }
    var kind: Kind
    var fraction: ClosedRange<Int>?
    var components: [String] = []      // dateTime.hour().minute()
    var grouping = true
    /// Every call made on the style, in order (`.precision(…)`, `.notation(.compactName)`),
    /// replayed onto Foundation's own format style when a value is formatted.
    var steps: [KFormatStep] = []
}

/// One call on a format style: `.notation(.compactName)`, `.rounded(rule: .up)`.
struct KFormatStep: Hashable {
    var name: String
    var args: [KV]
    var labels: [String?]
    func arg(_ label: String) -> KV? { labels.firstIndex(of: label).map { args[$0] } }
}

struct KStrokeStyle: Hashable {
    var lineWidth: Double = 1
    var lineCap: String = "butt"
    var lineJoin: String = "miter"
    var dash: [Double] = []
}

enum KNative: Hashable {
    case color(Color)
    case font(Font)
    case date(Date)
    case uuid(UUID)
    case angle(Double)                     // degrees
    case implicit(String, [KV])            // `.segmented`, `.title`, `.degrees(90)` before interpretation
    case keyPath([String])
    case indexSet(IndexSet)
    case url(URL)
    case gridItem(KGridItem)
    case format(KFormat)
    case strokeStyle(KStrokeStyle)
    case animation(KRef<Animation?>)
    case timer(KRef<KTimerBox>)
    case publisher(Double)                 // Timer.publish(every:)
    case dismiss(KRef<() -> Void>)         // @SwiftUI.Environment(\.dismiss)
    case asyncPhase(String, KRef<Image?>)  // AsyncImage phase: empty / success / failure
    case object(String, KRef<AnyObject>)   // DateFormatter, NumberFormatter, Calendar, UserDefaults, DispatchQueue …
    case size(Double, Double)              // CGSize
    case point(Double, Double)             // CGPoint
    case transition(String, [KV])
    case shape(KRef<AnyShape>)
    case path(KRef<KPathBox>)
    case rect(Double, Double, Double, Double)  // CGRect x, y, width, height
    case suspension(KSuspension)           // what `await` waits on (KEAsync)
    case boxed(KBoxed)                     // a native value type compared by value (`ProposedViewSize`, `TransitionPhase`)

    var kindName: String {
        switch self {
        case .color: return "Color"
        case .font: return "Font"
        case .date: return "Date"
        case .uuid: return "UUID"
        case .angle: return "Angle"
        case .implicit(let n, _): return "." + n
        case .keyPath: return "KeyPath"
        case .indexSet: return "IndexSet"
        case .url: return "URL"
        case .gridItem: return "GridItem"
        case .format: return "FormatStyle"
        case .strokeStyle: return "StrokeStyle"
        case .animation: return "Animation"
        case .timer: return "Timer"
        case .publisher: return "Publisher"
        case .dismiss: return "DismissAction"
        case .asyncPhase: return "AsyncImagePhase"
        case .object(let n, _): return n
        case .size: return "CGSize"
        case .point: return "CGPoint"
        case .transition: return "AnyTransition"
        case .shape: return "Shape"
        case .path: return "Path"
        case .rect: return "CGRect"
        case .suspension: return "Task"
        case .boxed(let b): return b.type
        }
    }

    /// For `switch phase { case .success(let image): … }`.
    var caseName: String? {
        if case .asyncPhase(let n, _) = self { return n }
        if case .boxed(let b) = self { return b.caseName }
        return nil
    }

    var payload: KV? {
        if case .asyncPhase("success", let img) = self, let image = img.value { return .view(.image(image)) }
        return nil
    }

    @MainActor func describe(_ interp: KInterpreter) -> String {
        switch self {
        case .date(let d): return d.description      // `print(date)`: "2026-03-14 19:09:26 +0000", as Swift prints it
        case .uuid(let u): return u.uuidString
        case .url(let u): return u.absoluteString
        case .implicit(let n, let a): return "." + n + (a.isEmpty ? "" : "(" + a.map { interp.describe($0) }.joined(separator: ", ") + ")")
        case .size(let w, let h): return "(\(w), \(h))"
        case .point(let x, let y): return "(\(x), \(y))"
        case .angle(let d): return "\(d)°"
        case .object("Error", let ref): return (ref.value as? NSError)?.localizedDescription ?? "Error"
        case .object("NSNumber", let ref): return (ref.value as? NSNumber)?.stringValue ?? "0"
        case .object(_, let ref) where ref.value is KDescribable: return (ref.value as! KDescribable).describe(interp)
        case .boxed(let b) where b.value.base is KDescribable: return (b.value.base as! KDescribable).describe(interp)
        default: return kindName
        }
    }
}

/// A native value that prints as Swift prints it (`"\(distance)"` is "5.0 km").
protocol KDescribable {
    @MainActor func describe(_ interp: KInterpreter) -> String
}

/// A native value type that compares by value, with the name of the type its
/// bridge is registered as. Enum-like ones have a case name, so `case .identity:`
/// and `phase == .identity` work (the type's `implicit` makes `.identity`).
final class KBoxed: Hashable {
    let type: String
    let value: AnyHashable
    let caseName: String?
    /// Where an ordered value sorts (`DynamicTypeSize`): `<` compares these.
    let order: Int?
    init(_ type: String, _ value: AnyHashable, caseName: String? = nil, order: Int? = nil) {
        self.type = type
        self.value = value
        self.caseName = caseName
        self.order = order
    }
    static func == (a: KBoxed, b: KBoxed) -> Bool { a.type == b.type && a.value == b.value }
    func hash(into h: inout Hasher) { h.combine(type); h.combine(value) }
    func get<T>(_: T.Type) -> T? { value.base as? T }
}

/// A SwiftUI Path built by interpreted code (`var p = Path(); p.move(to:)`).
final class KPathBox {
    var path = Path()
}

/// A Foundation Timer whose block runs interpreted code.
final class KTimerBox {
    var timer: Timer?
    func invalidate() { timer?.invalidate(); timer = nil }
}

struct KModifier {
    var name: String
    var args: [KV]
    var labels: [String?]
    var line: Int
    /// The overload its bridge picked when the code ran.
    var bound: KBound? = nil

    func arg(_ label: String?) -> KV? {
        if let i = labels.firstIndex(where: { $0 == label }) { return args[i] }
        return nil
    }
    var first: KV? { args.first }
    func unlabeled(_ n: Int) -> KV? {
        let u = zip(labels, args).filter { $0.0 == nil }.map(\.1)
        return n < u.count ? u[n] : nil
    }
}

/// What a view body evaluates to.
final class KView {
    enum Kind {
        case primitive(String, [KV], [String?], line: Int)
        case custom(KStructValue)
        case modified(KView, KModifier)
        case group([KView])
        case conditional(Bool, [KView])
        case switchBranch(Int, [KView])
        case textConcat(KView, KView)
        case image(Image)
        case empty
        case error(String)
    }
    let kind: Kind
    /// For a primitive: the overload its bridge picked when the code ran.
    let bound: KBound?
    init(_ kind: Kind, bound: KBound? = nil) {
        self.kind = kind
        self.bound = bound
    }

    static func primitive(_ name: String, _ args: [KV], _ labels: [String?], line: Int) -> KView { KView(.primitive(name, args, labels, line: line)) }
    static func custom(_ s: KStructValue) -> KView { KView(.custom(s)) }
    static func modified(_ v: KView, _ m: KModifier) -> KView { KView(.modified(v, m)) }
    static func group(_ v: [KView]) -> KView { v.count == 1 ? v[0] : KView(.group(v)) }
    static func conditional(_ b: Bool, _ v: [KView]) -> KView { KView(.conditional(b, v)) }
    static func switchBranch(_ i: Int, _ v: [KView]) -> KView { KView(.switchBranch(i, v)) }
    static func textConcat(_ a: KView, _ b: KView) -> KView { KView(.textConcat(a, b)) }
    static func image(_ i: Image) -> KView { KView(.image(i)) }
    static let empty = KView(.empty)
    static func error(_ m: String) -> KView { KView(.error(m)) }

    var primitiveName: String? {
        switch kind {
        case .primitive(let n, _, _, _): return n
        case .modified(let base, _): return base.primitiveName
        default: return nil
        }
    }

    /// The args of the underlying primitive.
    func primitiveArg(_ label: String?) -> KV? {
        switch kind {
        case .primitive(_, let args, let labels, _):
            if let i = labels.firstIndex(where: { $0 == label }) { return args[i] }
            return nil
        case .modified(let base, _): return base.primitiveArg(label)
        default: return nil
        }
    }

    /// Flatten groups and conditionals (Picker rows, toolbar items, chart marks).
    var flattened: [KView] {
        switch kind {
        case .group(let vs), .conditional(_, let vs), .switchBranch(_, let vs): return vs.flatMap(\.flattened)
        case .empty: return []
        default: return [self]
        }
    }

    /// A modifier applied anywhere in this view's own modifier chain.
    func modifier(_ name: String) -> KModifier? {
        if case .modified(let base, let m) = kind { return m.name == name ? m : base.modifier(name) }
        return nil
    }

    /// The view with `name` modifiers removed (e.g. `.tag` handled by a Picker).
    func removing(_ name: String) -> KView {
        if case .modified(let base, let m) = kind {
            let b = base.removing(name)
            return m.name == name ? b : .modified(b, m)
        }
        return self
    }
}
