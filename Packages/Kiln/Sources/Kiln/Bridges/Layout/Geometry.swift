//
//  Geometry.swift
//  Bridges: GeometryProxy, coordinate spaces, alignment guides, frames
//  relative to the container, safe-area padding, content margins and grid
//  cells
//
//  `GeometryReader { proxy in … }` gets a real `GeometryProxy`: `size`,
//  `safeAreaInsets`, `frame(in:)` and `bounds(of:)`, read when SwiftUI lays
//  the view out.
//

import SwiftUI

/// SwiftUI's proxy, or (when the app is only checked) a stand-in of a phone's size.
final class KGeometry {
    let size: CGSize
    let safeArea: EdgeInsets
    let frame: @MainActor (KV?) -> CGRect
    let bounds: @MainActor (KV?) -> CGRect?
    init(size: CGSize, safeArea: EdgeInsets = EdgeInsets(), frame: @escaping @MainActor (KV?) -> CGRect, bounds: @escaping @MainActor (KV?) -> CGRect? = { _ in nil }) {
        self.size = size
        self.safeArea = safeArea
        self.frame = frame
        self.bounds = bounds
    }

    @MainActor static func of(_ proxy: GeometryProxy) -> KGeometry {
        KGeometry(size: proxy.size, safeArea: proxy.safeAreaInsets,
                  frame: { space in
                      if let named = KLayout.namedSpace(space) { return proxy.frame(in: named) }
                      return proxy.frame(in: KLayout.coordinateSpace(space))
                  },
                  bounds: { space in KLayout.namedSpace(space).flatMap { proxy.bounds(of: $0) } })
    }

    /// What `Kiln.validate` hands a `GeometryReader`'s closure.
    @MainActor static let sample = KGeometry(size: CGSize(width: 393, height: 852), frame: { _ in CGRect(x: 0, y: 0, width: 393, height: 852) })

    var kv: KV { .native(.object("GeometryProxy", KRef(self))) }
}

@MainActor
enum KLayout {
    static func rect(_ r: CGRect) -> KV { .native(.rect(r.minX, r.minY, r.width, r.height)) }
    static func insets(_ e: EdgeInsets) -> KV {
        .tuple([.double(e.top), .double(e.leading), .double(e.bottom), .double(e.trailing)], ["top", "leading", "bottom", "trailing"])
    }
    static func edgeInsets(_ v: KV?) -> EdgeInsets? {
        guard case .tuple(let vals, let labels)? = v else { return nil }
        let inset: (String) -> Double = { l in labels.firstIndex(of: l).flatMap { vals[$0].asDouble } ?? 0 }
        return EdgeInsets(top: inset("top"), leading: inset("leading"), bottom: inset("bottom"), trailing: inset("trailing"))
    }

    /// `.global`, `.local`, `.named("list")`, `.scrollView`.
    static func coordinateSpace(_ v: KV?) -> CoordinateSpace {
        guard case .native(.implicit(let n, let args))? = v else { return .local }
        switch n {
        case "global": return .global
        case "named": return .named(args.first.map(spaceName) ?? "")
        default: return .local
        }
    }

    static func namedSpace(_ v: KV?) -> NamedCoordinateSpace? {
        guard case .native(.implicit(let n, let args))? = v else { return nil }
        switch n {
        case "named": return .named(args.first.map(spaceName) ?? "")
        case "scrollView": return .scrollView
        default: return nil
        }
    }

    static func spaceName(_ v: KV) -> String { v.asString ?? "\(v.hashValue)" }

    static func axes(_ v: KV?) -> Axis.Set {
        switch v {
        case .native(.implicit("horizontal", _))?: return .horizontal
        case .native(.implicit("vertical", _))?: return .vertical
        case .native(.implicit("all", _))?: return [.horizontal, .vertical]
        case .array(let items)?:
            var out: Axis.Set = []
            for i in items { out.formUnion(axes(i)) }
            return out
        case .set(let items)?:
            var out: Axis.Set = []
            for i in items { out.formUnion(axes(i)) }
            return out
        default: return []
        }
    }

    static func axis(_ v: KV?) -> Axis? {
        switch v {
        case .native(.implicit("horizontal", _))?: return .horizontal
        case .native(.implicit("vertical", _))?: return .vertical
        default: return nil
        }
    }
}


extension LayoutBridges {
    static func geometryBridges(_ r: KRegistry) {
        r.type("GeometryProxy", .layout, support: .full, notes: "`size`, `safeAreaInsets`, `frame(in: .local / .global / .named(…) / .scrollView)` and `bounds(of:)`.") { t in
            @MainActor func g(_ c: KCall) -> KGeometry? {
                if case .native(.object(_, let ref)) = c.receiver { return ref.value as? KGeometry }
                return nil
            }
            t.property("size") { c in let s = g(c)?.size ?? .zero; return .native(.size(s.width, s.height)) }
            t.property("safeAreaInsets") { c in KLayout.insets(g(c)?.safeArea ?? EdgeInsets()) }
            t.method("frame", "in:any") { c in KLayout.rect(g(c)?.frame(c["in"]) ?? .zero) }
            t.method("bounds", "of:any") { c in g(c)?.bounds(c["of"]).map(KLayout.rect) ?? .nilValue }
        }
        // `ViewDimensions` in an alignment guide: `d.width`, `d[.top]`, `d[VerticalAlignment.center]`.
        r.type("ViewDimensions", .layout, support: .full) { t in
            t.internal()
            @MainActor func dims(_ c: KCall) -> ViewDimensions? {
                if case .native(.object(_, let ref)) = c.receiver { return (ref.value as? KDimensionsBox)?.d }
                return nil
            }
            t.property("width") { c in .double(Double(dims(c)?.width ?? 100)) }
            t.property("height") { c in .double(Double(dims(c)?.height ?? 100)) }
            t.method("subscript", "_:any") { c in
                guard let d = dims(c), case .native(.implicit(let n, _))? = c[0] else { return .double(0) }
                switch n {
                case "leading": return .double(d[HorizontalAlignment.leading])
                case "trailing": return .double(d[HorizontalAlignment.trailing])
                case "top": return .double(d[VerticalAlignment.top])
                case "bottom": return .double(d[VerticalAlignment.bottom])
                case "firstTextBaseline": return .double(d[VerticalAlignment.firstTextBaseline])
                case "lastTextBaseline": return .double(d[VerticalAlignment.lastTextBaseline])
                default: return .double(d[HorizontalAlignment.center])
                }
            }
        }

        r.modifier("coordinateSpace", .layout, notes: "`.coordinateSpace(.named(\"list\"))` or `name:`, read by `proxy.frame(in: .named(\"list\"))`.") { m in
            m.form("_:any") { c, view in view.coordinateSpace(KLayout.namedSpace(c[0]) ?? .named("")) }
            m.form("name:any") { c, view in view.coordinateSpace(name: c["name"].map(KLayout.spaceName) ?? "") }
        }
        r.modifier("alignmentGuide", .layout, support: .partial,
                   notes: "The closure gets the view's dimensions: `d.width`, `d.height`, `d[.top]`. A `.center` guide is set for both axes, and `d[.center]` is the horizontal center.") { m in
            m.form("_:any computeValue:closure") { c, view in alignmentGuide(c, view) }
            m.probe { _, _ in [.native(.object("ViewDimensions", KRef(KDimensionsBox(nil))))] }
        }
        r.modifier("containerRelativeFrame", .layout) { m in
            m.form("_:Axis.Set alignment:Alignment?") { c, view in view.containerRelativeFrame(KLayout.axes(c[0]), alignment: c.alignment("alignment")) }
            m.form("_:Axis.Set count:number span:number? spacing:number alignment:Alignment?") { c, view in
                view.containerRelativeFrame(KLayout.axes(c[0]), count: c.int("count") ?? 1, span: c.int("span") ?? 1,
                                            spacing: c.cg("spacing") ?? 0, alignment: c.alignment("alignment"))
            }
            m.form("_:Axis.Set alignment:Alignment? _:closure") { c, view in
                if case .function(let f)? = c.last {
                    let interp = c.interp
                    view.containerRelativeFrame(KLayout.axes(c[0]), alignment: c.alignment("alignment")) { length, axis in
                        let v = try? interp.entry { try interp.call(f, [.double(length), .native(.implicit(axis == .horizontal ? "horizontal" : "vertical", []))], [nil, nil]) }
                        return v?.cg ?? length
                    }
                } else { view }
            }
            m.probe { _, _ in [.double(393), .native(.implicit("horizontal", []))] }
        }
        r.modifier("containerShape", .layout, notes: "A built-in shape (`RoundedRectangle(cornerRadius: 20)`, `Capsule()`) for `ContainerRelativeShape` inside.") { m in
            m.form("_:any") { c, view in
                containerShape(c, view)
            }
        }
        r.modifier("containerCornerOffset", .layout, introduced: "26.0") { m in
            m.form("_:Edge.Set sizeToFit:bool?") { c, view in
                if #available(iOS 26.0, macOS 26.0, *) {
                    AnyView(view.containerCornerOffset(c.edges(0), sizeToFit: c.bool("sizeToFit", default: false)))
                } else { view }
            }
        }
        r.modifier("safeAreaPadding", .layout) { m in
            m.form("_:any?") { c, view in
                if let n = c.cg(0) { AnyView(view.safeAreaPadding(n)) }
                else if let e = KLayout.edgeInsets(c[0]) { AnyView(view.safeAreaPadding(e)) }
                else if c[0] != nil { AnyView(view.safeAreaPadding(c.edges(0))) }
                else { AnyView(view.safeAreaPadding()) }
            }
            m.form("_:Edge.Set _:number?") { c, view in view.safeAreaPadding(c.edges(0), c.cg(1).map { CGFloat($0) }) }
        }
        r.modifier("contentMargins", .layout, notes: "Edges and a length or `EdgeInsets`, `for: .scrollContent` or `.scrollIndicators`.") { m in
            m.form("_:any for:ContentMarginPlacement?") { c, view in
                if let n = c.cg(0) { AnyView(view.contentMargins(n, for: marginPlacement(c))) }
                else if let e = KLayout.edgeInsets(c[0]) { AnyView(view.contentMargins(.all, e, for: marginPlacement(c))) }
                else { view }
            }
            m.form("_:Edge.Set _:any for:ContentMarginPlacement?") { c, view in
                if let e = KLayout.edgeInsets(c[1]) { AnyView(view.contentMargins(c.edges(0), e, for: marginPlacement(c))) }
                else { AnyView(view.contentMargins(c.edges(0), c.cg(1), for: marginPlacement(c))) }
            }
        }
        r.modifier("layoutDirectionBehavior", .layout) { m in
            m.form("_:LayoutDirectionBehavior") { c, view in
                if c.symbol(0) == "fixed" { view.layoutDirectionBehavior(.fixed) } else { view.layoutDirectionBehavior(.mirrors) }
            }
        }
        r.modifier("geometryGroup", .layout) { m in m.form("") { _, view in view.geometryGroup() } }
        r.modifier("gridCellColumns", .layout) { m in m.form("_:number") { c, view in view.gridCellColumns(c.int(0) ?? 1) } }
        r.modifier("gridCellAnchor", .layout) { m in
            m.form("_:UnitPoint") { c, view in view.gridCellAnchor(c.unitPoint(0) ?? .center) }
        }
        r.modifier("gridCellUnsizedAxes", .layout) { m in m.form("_:Axis.Set") { c, view in view.gridCellUnsizedAxes(KLayout.axes(c[0])) } }
        r.modifier("gridColumnAlignment", .layout) { m in
            m.form("_:HorizontalAlignment") { c, view in view.gridColumnAlignment(c.horizontalAlignment(0)) }
        }
        r.modifier("onGeometryChange", .layout, notes: "`of:` turns the view's `GeometryProxy` into a value; `action:` runs when it changes.") { m in
            m.forms(["for:any of:closure action:closure", "for:any of:closure _:closure"]) { c, view in onGeometryChange(c, view) }
            m.probe { label, _ in label == "action" ? [.nilValue, .nilValue] : [KGeometry.sample.kv] }
        }
        r.modifier("size", .layout, notes: "On a built-in shape: draws it at that size, anchored at the top leading corner or `anchor:`.") { m in
            m.formOnBase("width:number height:number anchor:UnitPoint?", receiver: "Shape") { c in shapeSize(c, CGSize(width: c.cg("width") ?? 0, height: c.cg("height") ?? 0)) }
            m.formOnBase("_:CGSize anchor:UnitPoint?", receiver: "Shape") { c in
                if case .native(.size(let w, let h))? = c[0] { shapeSize(c, CGSize(width: w, height: h)) } else { c.view }
            }
        }
        r.wrapper("ScaledMetric", .layout, support: .partial,
                  notes: "Scaled for the text size when the view first appears; it doesn't follow a later change of Dynamic Type.")
    }

    /// The built-in insettable shapes, by their description.
    @MainActor static func containerShape(_ c: KCall, _ view: AnyView) -> AnyView {
        guard case .view(let v)? = c[0], case .primitive(let n, let args, let labels, _)? = c.r.rootPrimitive(v) else { return view }
        let a = KArgs(args: args, labels: labels)
        switch n {
        case "RoundedRectangle": return AnyView(view.containerShape(RoundedRectangle(cornerRadius: a["cornerRadius"]?.cg ?? 0, style: a["style"].flatMap { if case .native(.implicit("circular", _)) = $0 { return .circular }; return nil } ?? .continuous)))
        case "Capsule": return AnyView(view.containerShape(Capsule()))
        case "Circle": return AnyView(view.containerShape(Circle()))
        case "Ellipse": return AnyView(view.containerShape(Ellipse()))
        case "Rectangle": return AnyView(view.containerShape(Rectangle()))
        case "ContainerRelativeShape": return AnyView(view.containerShape(ContainerRelativeShape()))
        default: return view
        }
    }

    @MainActor static func shapeSize(_ c: KCall, _ size: CGSize) -> AnyView {
        guard let base = c.base, let chain = c.r.shapeChain(base) else { return c.view }
        if #available(iOS 18.0, macOS 15.0, *), let anchor = c.unitPoint("anchor") { return AnyView(chain.kind.anyShape.size(size, anchor: anchor)) }
        return AnyView(chain.kind.anyShape.size(size))
    }

    /// `@ScaledMetric var size = 20`: the value for the current text size.
    @MainActor static func scaled(_ v: KV, relativeTo style: String?) -> KV {
        guard let d = v.asDouble else { return v }
        #if os(iOS) || os(visionOS)
        let styles: [String: UIFont.TextStyle] = ["largeTitle": .largeTitle, "title": .title1, "title2": .title2, "title3": .title3, "headline": .headline,
                                                  "subheadline": .subheadline, "callout": .callout, "footnote": .footnote, "caption": .caption1, "caption2": .caption2]
        let out = UIFontMetrics(forTextStyle: style.flatMap { styles[$0] } ?? .body).scaledValue(for: d)
        if case .int = v { return .int(Int(out.rounded())) }
        return .double(out)
        #else
        return v
        #endif
    }

    @MainActor static func marginPlacement(_ c: KCall) -> ContentMarginPlacement {
        switch c.symbol("for") {
        case "scrollContent": return .scrollContent
        case "scrollIndicators": return .scrollIndicators
        default: return .automatic
        }
    }

    @MainActor static func alignmentGuide(_ c: KCall, _ view: AnyView) -> AnyView {
        guard case .function(let f)? = c["computeValue"] else { return view }
        let interp = c.interp
        let compute: @Sendable (ViewDimensions) -> CGFloat = { d in
            MainActor.assumeIsolated {
                let v = try? interp.entry { try interp.call(f, [.native(.object("ViewDimensions", KRef(KDimensionsBox(d))))], [nil]) }
                return v?.cg ?? 0
            }
        }
        guard case .native(.implicit(let n, _))? = c[0] else { return view }
        switch n {
        case "leading": return AnyView(view.alignmentGuide(HorizontalAlignment.leading, computeValue: compute))
        case "trailing": return AnyView(view.alignmentGuide(HorizontalAlignment.trailing, computeValue: compute))
        case "top": return AnyView(view.alignmentGuide(VerticalAlignment.top, computeValue: compute))
        case "bottom": return AnyView(view.alignmentGuide(VerticalAlignment.bottom, computeValue: compute))
        case "firstTextBaseline": return AnyView(view.alignmentGuide(VerticalAlignment.firstTextBaseline, computeValue: compute))
        case "lastTextBaseline": return AnyView(view.alignmentGuide(VerticalAlignment.lastTextBaseline, computeValue: compute))
        // `.center` doesn't say which: both guides, as either stack reads its own.
        default: return AnyView(view.alignmentGuide(HorizontalAlignment.center, computeValue: compute).alignmentGuide(VerticalAlignment.center, computeValue: compute))
        }
    }

    @MainActor static func onGeometryChange(_ c: KCall, _ view: AnyView) -> AnyView {
        guard case .function(let transform)? = c["of"], case .function(let action)? = c.last else { return view }
        let interp = c.interp
        let n = c.r.closureParamCount(.function(action))
        guard #available(iOS 18.0, macOS 15.0, *) else { return view }
        return AnyView(view.onGeometryChange(for: KEquatable.self, of: { proxy in
            MainActor.assumeIsolated {
                KEquatable((try? interp.entry { try interp.call(transform, [KGeometry.of(proxy).kv], [nil]) }) ?? .nilValue)
            }
        }, action: { old, new in
            interp.perform(action, n >= 2 ? [old.value, new.value] : [new.value])
        }))
    }
}

/// A value SwiftUI compares across updates (`onGeometryChange`, `onScrollGeometryChange`).
struct KEquatable: Equatable, @unchecked Sendable {
    let value: KV
    init(_ value: KV) { self.value = value }
}

final class KDimensionsBox {
    /// nil when the app is only checked: a 100-point square.
    let d: ViewDimensions?
    init(_ d: ViewDimensions?) { self.d = d }
}
