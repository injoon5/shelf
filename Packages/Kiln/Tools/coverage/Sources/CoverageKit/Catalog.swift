// Turns parsed interfaces into the list of symbols an app author can write:
// views, modifiers, styles, other content (toolbar, tab, chart, table, scene),
// gestures, the static members of the types models reach for (`.spring`,
// `.ultraThinMaterial`), environment values, property wrappers, protocols an
// app adopts, a few key non-view types, and macros.
//
// Anything unavailable on iOS is dropped. Names starting with `_` are dropped.

import Foundation

public enum SymbolKind: String, Codable, CaseIterable, Sendable {
    case view, modifier, style, content, gesture, member, environment, wrapper, `protocol`, type, macro

    /// Order and wording used in reports.
    public var plural: String {
        switch self {
        case .view: "Views"
        case .modifier: "Modifiers"
        case .style: "Styles"
        case .content: "Toolbar, tab, chart, table and scene content"
        case .gesture: "Gestures"
        case .member: "Static members (colors, fonts, animations, transitions, shape styles)"
        case .environment: "Environment values"
        case .wrapper: "Property wrappers"
        case .protocol: "Protocols an app adopts"
        case .type: "Other types"
        case .macro: "Macros"
        }
    }
}

public struct SymbolOverload: Codable, Equatable, Sendable {
    /// Argument labels, `_` for an unlabelled one. Empty for a property.
    public var labels: [String]
    /// What a modifier is called on (`View`, `Shape`, `Text`, `ToolbarContent`…).
    public var receiver: String?
    public var module: String
    public var introduced: String?
    public var deprecated: Bool
    public var signature: String
}

public struct SDKSymbol: Codable, Equatable, Sendable {
    /// `view:DatePicker`, `modifier:padding`, `modifier:ToolbarContent.visibilityPriority`,
    /// `style:ButtonStyle.borderedProminent`, `member:Animation.spring`, `environment:dismiss`.
    public var id: String
    public var kind: SymbolKind
    public var name: String
    /// The style protocol or type a style or member belongs to.
    public var owner: String?
    public var module: String
    public var introduced: String?
    public var deprecated: Bool
    public var deprecationMessage: String?
    /// For `content`, the protocol it conforms to (`ChartContent`, `ToolbarContent`…).
    public var conformsTo: String?
    public var overloads: [SymbolOverload]

    public static func makeID(kind: SymbolKind, name: String, owner: String?) -> String {
        if let o = owner { return "\(kind.rawValue):\(o).\(name)" }
        return "\(kind.rawValue):\(name)"
    }
}

public struct Catalog: Sendable {
    public var symbols: [SDKSymbol]
    public var modules: [String]

    public func symbol(_ id: String) -> SDKSymbol? { symbols.first { $0.id == id } }

    // MARK: - Configuration

    /// Protocols whose instance methods are modifiers, and the class they report under.
    /// `View` covers `Shape`, `Text`, `Image` and the rest, so their ids are bare (`modifier:fill`).
    static let receiverClasses: [String: String] = [
        "View": "View", "Shape": "View", "InsettableShape": "View", "DynamicViewContent": "View",
        "Text": "View", "Image": "View", "ModifiedContent": "View",
        "ToolbarContent": "ToolbarContent", "CustomizableToolbarContent": "ToolbarContent",
        "TabContent": "TabContent", "ChartContent": "ChartContent", "Chart3DContent": "Chart3DContent",
        "Gesture": "Gesture", "Scene": "Scene", "Commands": "Scene",
        "TableColumnContent": "TableColumnContent", "TableRowContent": "TableRowContent",
    ]

    /// Non-view content protocols, in priority order.
    static let contentProtocols = [
        "ToolbarContent", "CustomizableToolbarContent", "TabContent", "ChartContent", "Chart3DContent",
        "TableColumnContent", "TableRowContent", "AxisContent", "KeyframeTrackContent", "SliderTickContent",
        "AccessibilityRotorContent", "SceneAccessoryContent", "HoverEffectContent", "Commands", "Scene",
    ]

    /// Types whose static members are listed (`.red`, `.title`, `.spring`, `.slide`).
    static let memberOwners: Set<String> = [
        "ShapeStyle", "Color", "Font", "Animation", "AnyTransition", "Transition", "ContentTransition",
        "ScrollTargetBehavior", "NavigationTransition", "PresentationSizing", "PresentationDetent",
        "ToolbarItemPlacement", "SensoryFeedback", "Glass",
    ]

    /// Protocols an app's own types adopt (bridged through §1.5's proxies).
    static let authorProtocols: Set<String> = [
        "App", "View", "Shape", "InsettableShape", "Layout", "ViewModifier", "Animatable", "Transition",
        "EnvironmentKey", "PreferenceKey", "DynamicProperty", "VectorArithmetic", "AnimatableModifier",
        "CustomAnimation", "TextRenderer", "VisualEffect", "ContainerValueKey", "FocusedValueKey", "Gesture",
    ]

    /// Non-view types listed as `type:` because models write them by name.
    static let keyTypes: Set<String> = [
        "Animation", "AnyTransition", "Font", "Gradient", "Angle", "UnitPoint", "Spring", "UnitCurve",
        "ContentTransition", "KeyframeTimeline", "GraphicsContext", "Shader", "ShaderLibrary", "Namespace",
        "EdgeInsets", "GridItem", "ScrollViewProxy", "GeometryProxy", "NavigationPath", "PresentationDetent",
        "Glass", "Binding", "AttributedString", "LocalizedStringKey", "AnyShape", "AnyGradient", "Material",
        "StrokeStyle", "FillStyle", "ProposedViewSize", "ScrollPosition", "PlottableValue", "ChartProxy",
        "SymbolEffect", "ToolbarItemPlacement", "SearchFieldPlacement", "TextSelection", "SensoryFeedback",
    ]

    // MARK: - Building

    struct TypeInfo {
        var name: String
        var module: String
        var kind: Decl.Kind
        var inherits: Set<String>
        var availability: Availability
        var nested: Bool
        var isPropertyWrapper: Bool
        var declared: Bool
    }

    struct Member {
        var decl: Decl
        var receiver: String
        var whereClause: String
        var module: String
        var availability: Availability
    }

    public static func build(_ files: [InterfaceFile]) -> Catalog {
        var types: [String: TypeInfo] = [:]
        var members: [Member] = []
        var macros: [(Decl, String, Availability)] = []

        func registerType(_ d: Decl, prefix: String, module: String, ctx: Availability) {
            let name = prefix.isEmpty ? d.name : "\(prefix).\(d.name)"
            let avail = ctx.refined(by: Availability.iOS(d.attributes))
            var info = types[name] ?? TypeInfo(name: name, module: module, kind: d.kind, inherits: [], availability: avail,
                                               nested: !prefix.isEmpty, isPropertyWrapper: false, declared: true)
            info.declared = true
            info.module = module
            info.kind = d.kind
            info.availability = avail
            info.nested = !prefix.isEmpty
            info.inherits.formUnion(d.inherits)
            info.isPropertyWrapper = info.isPropertyWrapper || d.has("propertyWrapper")
            types[name] = info
            for c in d.children {
                if c.isTypeDecl { registerType(c, prefix: name, module: module, ctx: avail) }
                else { members.append(Member(decl: c, receiver: name, whereClause: "", module: module, availability: avail)) }
            }
        }

        // Pass 1: types, wherever they're declared.
        for f in files {
            for d in f.decls {
                if d.isTypeDecl { registerType(d, prefix: "", module: f.module, ctx: Availability()) }
                if d.kind == .macro { macros.append((d, f.module, Availability.iOS(d.attributes))) }
            }
        }
        // Pass 2: extensions add conformances and members.
        for f in files {
            for d in f.decls where d.kind == .extension {
                if types[d.name] == nil {
                    types[d.name] = TypeInfo(name: d.name, module: f.module, kind: .struct, inherits: [], availability: Availability(),
                                             nested: d.name.contains("."), isPropertyWrapper: false, declared: false)
                }
                types[d.name]!.inherits.formUnion(d.inherits)
                let ctx = types[d.name]!.availability.refined(by: Availability.iOS(d.attributes))
                for c in d.children {
                    if c.isTypeDecl { registerType(c, prefix: d.name, module: f.module, ctx: ctx); continue }
                    members.append(Member(decl: c, receiver: d.name, whereClause: d.whereClause, module: f.module, availability: ctx))
                }
            }
        }

        var memo: [String: Set<String>] = [:]
        func ancestors(_ t: String) -> Set<String> {
            if let m = memo[t] { return m }
            memo[t] = []
            var out: Set<String> = []
            for p in types[t]?.inherits ?? [] {
                out.insert(p)
                out.formUnion(ancestors(p))
            }
            memo[t] = out
            return out
        }
        func conforms(_ t: String, _ p: String) -> Bool { t == p || ancestors(t).contains(p) }

        let inputModules = Set(files.map(\.module))
        var byID: [String: SDKSymbol] = [:]

        func add(kind: SymbolKind, name: String, owner: String?, module: String, availability: Availability,
                 conformsTo: String? = nil, overload: SymbolOverload?) {
            let id = SDKSymbol.makeID(kind: kind, name: name, owner: owner)
            var s = byID[id] ?? SDKSymbol(id: id, kind: kind, name: name, owner: owner, module: module,
                                          introduced: availability.introduced?.description, deprecated: availability.isDeprecated,
                                          deprecationMessage: availability.isDeprecated ? availability.message : nil,
                                          conformsTo: conformsTo, overloads: [])
            if let o = overload {
                if !s.overloads.contains(where: { $0.signature == o.signature && $0.receiver == o.receiver }) {
                    s.overloads.append(o)
                }
            }
            byID[id] = s
        }

        func overload(_ m: Member, receiver: String?, availability a: Availability) -> SymbolOverload {
            var sig = m.decl.signature
            if !m.whereClause.isEmpty && !sig.contains(" where ") { sig += "  /* extension where \(m.whereClause) */" }
            return SymbolOverload(labels: m.decl.labels, receiver: receiver, module: m.module,
                                  introduced: a.introduced?.description, deprecated: a.isDeprecated, signature: sig)
        }

        func isPublicName(_ n: String) -> Bool { !n.isEmpty && !n.hasPrefix("_") && (n.first!.isLetter) }

        // Types.
        for (name, t) in types where t.declared && !t.nested && inputModules.contains(t.module) && isPublicName(name) {
            guard !t.availability.unavailable else { continue }
            if t.kind == .protocol {
                let isStyle = name.hasSuffix("Style") && name != "ShapeStyle"
                if isStyle || authorProtocols.contains(name) {
                    add(kind: .protocol, name: name, owner: nil, module: t.module, availability: t.availability, overload: nil)
                }
                continue
            }
            var kind: SymbolKind? = nil
            var proto: String? = nil
            if t.isPropertyWrapper { kind = .wrapper }
            else if conforms(name, "View") { kind = .view }
            else if conforms(name, "Gesture") { kind = .gesture }
            else if let p = contentProtocols.first(where: { conforms(name, $0) }) {
                kind = .content
                proto = p == "CustomizableToolbarContent" ? "ToolbarContent" : p
            } else if conforms(name, "ShapeStyle") || conforms(name, "Transition") || conforms(name, "Tool") || keyTypes.contains(name) {
                kind = .type
            }
            if let k = kind {
                add(kind: k, name: name, owner: nil, module: t.module, availability: t.availability, conformsTo: proto, overload: nil)
            }
        }

        // Members: initializers, modifiers, styles, static members, environment values.
        for m in members {
            let d = m.decl
            let a = m.availability.refined(by: Availability.iOS(d.attributes))
            guard !a.unavailable else { continue }
            let receiver = m.receiver
            let rt = types[receiver]

            if d.kind == .initializer {
                for k in [SymbolKind.view, .gesture, .content, .type, .wrapper] {
                    let sid = SDKSymbol.makeID(kind: k, name: receiver, owner: nil)
                    if byID[sid] != nil {
                        add(kind: k, name: receiver, owner: nil, module: m.module, availability: a, overload: overload(m, receiver: nil, availability: a))
                        break
                    }
                }
                continue
            }
            guard isPublicName(d.name) else { continue }

            if d.kind == .func, !d.isStatic, let cls = receiverClass(receiver, rt, conforms), qualifiesAsModifier(d, receiver: receiver, cls: cls) {
                let owner = cls == "View" ? nil : cls
                add(kind: .modifier, name: d.name, owner: owner, module: m.module, availability: a,
                    overload: overload(m, receiver: receiver, availability: a))
                continue
            }
            if d.isStatic, d.kind == .var || d.kind == .let || d.kind == .func,
               rt?.kind == .protocol, receiver.hasSuffix("Style"), receiver != "ShapeStyle" {
                let owner = receiver.hasPrefix("Primitive") ? String(receiver.dropFirst("Primitive".count)) : receiver
                add(kind: .style, name: d.name, owner: owner, module: m.module, availability: a,
                    overload: overload(m, receiver: receiver, availability: a))
                continue
            }
            if d.isStatic, d.kind == .var || d.kind == .let || d.kind == .func, memberOwners.contains(receiver) {
                add(kind: .member, name: d.name, owner: receiver, module: m.module, availability: a,
                    overload: overload(m, receiver: receiver, availability: a))
                continue
            }
            if receiver == "EnvironmentValues", d.kind == .var, !d.isStatic {
                add(kind: .environment, name: d.name, owner: nil, module: m.module, availability: a,
                    overload: overload(m, receiver: nil, availability: a))
            }
        }

        for (d, module, a) in macros where !a.unavailable && isPublicName(d.name) {
            add(kind: .macro, name: d.name, owner: nil, module: module, availability: a,
                overload: SymbolOverload(labels: d.labels, receiver: nil, module: module, introduced: a.introduced?.description,
                                         deprecated: a.isDeprecated, signature: d.signature))
        }

        // A symbol's availability is its earliest overload's; it's deprecated only if every overload is.
        var symbols = Array(byID.values)
        for k in symbols.indices {
            var s = symbols[k]
            s.overloads.sort { ($0.receiver ?? "", $0.signature) < ($1.receiver ?? "", $1.signature) }
            if [.modifier, .style, .member, .environment].contains(s.kind), !s.overloads.isEmpty {
                let versions = s.overloads.compactMap { $0.introduced.map(Version.init) }
                s.introduced = versions.min()?.description
                s.deprecated = s.overloads.allSatisfy(\.deprecated)
                if !s.deprecated { s.deprecationMessage = nil }
                let mods = s.overloads.map(\.module)
                s.module = mods.first { $0 == "SwiftUICore" || $0 == "SwiftUI" } ?? mods.sorted().first ?? s.module
            }
            symbols[k] = s
        }
        symbols.sort { $0.id < $1.id }
        return Catalog(symbols: symbols, modules: files.map(\.module).sorted())
    }

    static func receiverClass(_ receiver: String, _ t: TypeInfo?, _ conforms: (String, String) -> Bool) -> String? {
        if let c = receiverClasses[receiver] { return c }
        // Extensions on a concrete gesture or chart mark (`DragGesture`, `BarMark`) are rare
        // but count with their protocol. Concrete views other than Text and Image don't
        // add modifiers (their methods are things like `Color.mix(with:by:)`).
        if conforms(receiver, "Gesture") { return "Gesture" }
        if conforms(receiver, "ChartContent") { return "ChartContent" }
        return nil
    }

    static func qualifiesAsModifier(_ d: Decl, receiver: String, cls: String) -> Bool {
        guard let rt = d.returnType?.trimmingCharacters(in: .whitespaces), !rt.isEmpty else { return false }
        if rt.hasPrefix("some ") || rt == "Self" || rt.hasPrefix("ModifiedContent<") { return true }
        if rt == receiver || rt.hasPrefix(receiver + "<") { return true }
        if cls == "Gesture" && rt.contains("Gesture") { return true }
        // Shape modifiers return concrete shapes: `RotatedShape<Self>`, `OffsetShape<Self>`, `Self.InsetShape`.
        if (receiver == "Shape" || receiver == "InsettableShape") && rt.contains("Shape") { return true }
        if cls == "View" && (rt == "Text" || rt == "Image") && (receiver == "Text" || receiver == "Image") { return true }
        return false
    }
}
