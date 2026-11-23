//
//  Layout.swift
//  Bridges: stacks, grids, scroll views, frames and padding
//

import SwiftUI

@objc(KilnBridges_Layout)
final class LayoutBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        stacks(r)
        containers(r)
        modifiers(r)
        geometry(r)
        geometryBridges(r)
        scrolling(r)
        subviews(r)
        arrangements(r)
    }

    // MARK: Stacks and grids

    static func stacks(_ r: KRegistry) {
        r.view("VStack", .layout) { v in
            v.form("alignment:HorizontalAlignment? spacing:number? content:content") { c in
                VStack(alignment: c.horizontalAlignment("alignment"), spacing: c.cg("spacing")) { c.content() }
            }
        }
        r.view("LazyVStack", .layout) { v in
            v.form("alignment:HorizontalAlignment? spacing:number? pinnedViews:any? content:content") { c in
                LazyVStack(alignment: c.horizontalAlignment("alignment"), spacing: c.cg("spacing")) { c.content() }
            }
        }
        r.view("HStack", .layout) { v in
            v.form("alignment:VerticalAlignment? spacing:number? content:content") { c in
                HStack(alignment: c.verticalAlignment("alignment"), spacing: c.cg("spacing")) { c.content() }
            }
        }
        r.view("LazyHStack", .layout) { v in
            v.form("alignment:VerticalAlignment? spacing:number? pinnedViews:any? content:content") { c in
                LazyHStack(alignment: c.verticalAlignment("alignment"), spacing: c.cg("spacing")) { c.content() }
            }
        }
        r.view("ZStack", .layout) { v in
            v.form("alignment:Alignment? content:content") { c in ZStack(alignment: c.alignment("alignment")) { c.content() } }
        }
        r.view("LazyVGrid", .layout) { v in
            v.form("columns:any alignment:HorizontalAlignment? spacing:number? pinnedViews:any? content:content") { c in
                LazyVGrid(columns: gridItems(c["columns"]), alignment: c.horizontalAlignment("alignment"), spacing: c.cg("spacing")) { c.content() }
            }
        }
        r.view("LazyHGrid", .layout) { v in
            v.form("rows:any alignment:VerticalAlignment? spacing:number? pinnedViews:any? content:content") { c in
                LazyHGrid(rows: gridItems(c["rows"]), alignment: c.verticalAlignment("alignment"), spacing: c.cg("spacing")) { c.content() }
            }
        }
        r.view("Grid", .layout, support: .partial) { v in
            v.form("alignment:Alignment? horizontalSpacing:number? verticalSpacing:number? content:content") { c in
                Grid(alignment: c.alignment("alignment"), horizontalSpacing: c.cg("horizontalSpacing"), verticalSpacing: c.cg("verticalSpacing")) { c.content() }
            }
        }
        r.view("GridRow", .layout) { v in
            v.form("alignment:VerticalAlignment? content:content") { c in GridRow(alignment: c.verticalAlignment("alignment")) { c.content() } }
        }
        r.view("Spacer", .layout) { v in
            v.form("minLength:number?") { c in Spacer(minLength: c.cg("minLength")) }
        }
        r.view("Divider", .layout) { v in
            v.form("") { _ in Divider() }
        }

        r.type("GridItem", .layout) { t in
            t.initializer(kinds: [nil: .typed("GridItem.Size")]) { c in
                var item = KGridItem(size: .flexible(10, .infinity), spacing: c.arg("spacing")?.asDouble)
                if case .native(.implicit(let n, let a))? = c.first {
                    switch n {
                    case "fixed": item.size = .fixed(a.first?.asDouble ?? 50)
                    case "adaptive": item.size = .adaptive(a.first?.asDouble ?? 80, a.count > 1 ? (a[1].asDouble ?? .infinity) : .infinity)
                    default: item.size = .flexible(a.first?.asDouble ?? 10, a.count > 1 ? (a[1].asDouble ?? .infinity) : .infinity)
                    }
                }
                return .native(.gridItem(item))
            }
        }
    }

    @MainActor static func gridItems(_ v: KV?) -> [GridItem] {
        v?.asArray?.compactMap { item -> GridItem? in
            guard case .native(.gridItem(let g)) = item else { return nil }
            let size: GridItem.Size
            switch g.size {
            case .flexible(let lo, let hi): size = .flexible(minimum: lo, maximum: hi)
            case .fixed(let w): size = .fixed(w)
            case .adaptive(let lo, let hi): size = .adaptive(minimum: lo, maximum: hi)
            }
            return GridItem(size, spacing: g.spacing.map { CGFloat($0) })
        } ?? [GridItem(.flexible())]
    }

    // MARK: Scroll views and readers

    static func containers(_ r: KRegistry) {
        r.view("ScrollView", .layout) { v in
            v.form("_:Axis.Set? showsIndicators:bool? content:content") { c in
                ScrollView(c[0].map { KLayout.axes($0) } ?? .vertical, showsIndicators: c.bool("showsIndicators", default: true)) { c.content() }
            }
        }
        r.view("ScrollViewReader", .layout, notes: "`proxy.scrollTo(id, anchor:)`.") { v in
            v.form("content:content") { c in
                ScrollViewReader { proxy in
                    c.content(nil, [.native(.object("ScrollViewProxy", KRef(KScrollProxy(proxy))))])
                }
            }
        }
        r.type("ScrollViewProxy", .layout) { t in
            t.method("scrollTo") { c in
                guard let p = c.object(KScrollProxy.self) else { return .void }
                let id = c.at(0) ?? .nilValue
                if let a = c.r.unitPoint(c.arg("anchor")) { p.proxy.scrollTo(id, anchor: a) } else { p.proxy.scrollTo(id) }
                return .void
            }
        }
        r.view("GeometryReader", .layout, notes: "The closure gets a `GeometryProxy`: `size`, `safeAreaInsets`, `frame(in:)`, `bounds(of:)`.") { v in
            v.form("content:content") { c in
                let fn = c.contentValue(nil)
                GeometryReader { proxy in c.r.renderContent(fn, [KGeometry.of(proxy).kv]) }
            }
        }
        r.view("ViewThatFits", .layout) { v in
            v.form("in:Axis.Set? content:content") { c in
                if c["in"] != nil { ViewThatFits(in: KLayout.axes(c["in"])) { c.content() } } else { ViewThatFits { c.content() } }
            }
        }
    }

    @MainActor static func scrollAxes(_ v: KV?) -> Axis.Set {
        if case .native(.implicit("horizontal", _))? = v { return .horizontal }
        if case .array? = v { return [.horizontal, .vertical] }
        return .vertical
    }

    // MARK: Modifiers

    static func modifiers(_ r: KRegistry) {
        r.modifier("padding", .layout, notes: "A length, edges, edges and a length, or `EdgeInsets`.") { m in
            m.form("") { _, view in view.padding() }
            // A length, edges or EdgeInsets: they look alike until they're evaluated.
            m.form("_:any") { c, view in
                if let n = c.cg(0) {
                    view.padding(n)
                } else if case .tuple(let vals, let labels)? = c[0] {
                    let inset: (String) -> Double = { l in labels.firstIndex(of: l).flatMap { vals[$0].asDouble } ?? 0 }
                    view.padding(EdgeInsets(top: inset("top"), leading: inset("leading"), bottom: inset("bottom"), trailing: inset("trailing")))
                } else {
                    view.padding(c.edges(0))
                }
            }
            m.form("_:Edge.Set _:number?") { c, view in
                if let n = c.cg(1) { view.padding(c.edges(0), n) } else { view.padding(c.edges(0)) }
            }
        }
        r.modifier("frame", .layout) { m in
            m.forms(["width:number? height:number? alignment:Alignment?",
                     "minWidth:number? idealWidth:number? maxWidth:number? minHeight:number? idealHeight:number? maxHeight:number? alignment:Alignment?"]) { c, view in
                frame(c, view)
            }
        }
        r.modifier("fixedSize", .layout) { m in
            m.form("") { _, view in view.fixedSize() }
            m.form("horizontal:bool vertical:bool") { c, view in
                view.fixedSize(horizontal: c.bool("horizontal", default: true), vertical: c.bool("vertical", default: true))
            }
        }
        r.modifier("layoutPriority", .layout) { m in
            m.form("_:number") { c, view in view.layoutPriority(c.double(0) ?? 0) }
        }
        r.modifier("offset", .layout) { m in
            m.form("_:CGSize") { c, view in
                if case .native(.size(let w, let h))? = c[0] { view.offset(x: w, y: h) } else { view }
            }
            m.form("x:number? y:number?") { c, view in view.offset(x: c.cg("x") ?? 0, y: c.cg("y") ?? 0) }
        }
        r.modifier("position", .layout) { m in
            m.form("_:CGPoint") { c, view in
                if case .native(.point(let x, let y))? = c[0] { view.position(x: x, y: y) } else { view }
            }
            m.form("x:number? y:number?") { c, view in view.position(x: c.cg("x") ?? 0, y: c.cg("y") ?? 0) }
            // On chart marks: grouped by value.
            m.form("by:any axis:any? span:any?", receiver: "ChartContent") { _, view in view }
        }
        r.modifier("zIndex", .layout) { m in
            m.form("_:number") { c, view in view.zIndex(c.double(0) ?? 0) }
        }
        r.modifier("ignoresSafeArea", .layout) { m in
            m.form("_:SafeAreaRegions? edges:Edge.Set?") { c, view in view.ignoresSafeArea(.all, edges: c.edges("edges")) }
        }
        r.modifier("edgesIgnoringSafeArea", .layout) { m in
            m.form("_:Edge.Set") { c, view in view.ignoresSafeArea(.all, edges: c.edges(0)) }
        }
        r.modifier("aspectRatio", .layout) { m in
            m.form("_:any? contentMode:ContentMode?") { c, view in
                let mode: ContentMode = c.symbol("contentMode") == "fill" ? .fill : .fit
                if let ratio = c.cg(0) { view.aspectRatio(ratio, contentMode: mode) } else { view.aspectRatio(contentMode: mode) }
            }
        }
        r.modifier("hidden", .layout) { m in m.form("") { _, view in view.hidden() } }
        r.modifier("scaledToFit", .layout) { m in m.form("") { _, view in view.scaledToFit() } }
        r.modifier("scaledToFill", .layout) { m in m.form("") { _, view in view.scaledToFill() } }
        r.modifier("safeAreaInset", .layout) { m in
            m.form("edge:any alignment:any? spacing:number? content:content") { c, view in
                let content = c.content("content")
                switch c.symbol("edge") {
                case "top": view.safeAreaInset(edge: .top, alignment: c.horizontalAlignment("alignment"), spacing: c.cg("spacing")) { content }
                case "leading": view.safeAreaInset(edge: .leading, alignment: c.verticalAlignment("alignment"), spacing: c.cg("spacing")) { content }
                case "trailing": view.safeAreaInset(edge: .trailing, alignment: c.verticalAlignment("alignment"), spacing: c.cg("spacing")) { content }
                default: view.safeAreaInset(edge: .bottom, alignment: c.horizontalAlignment("alignment"), spacing: c.cg("spacing")) { content }
                }
            }
        }
        r.modifier("scrollIndicators", .layout) { m in
            m.form("_:ScrollIndicatorVisibility axes:Axis.Set?") { c, view in
                let axes = c["axes"].map { KLayout.axes($0) } ?? [.vertical, .horizontal]
                switch c.symbol(0) {
                case "hidden": view.scrollIndicators(.hidden, axes: axes)
                case "never": view.scrollIndicators(.never, axes: axes)
                case "visible": view.scrollIndicators(.visible, axes: axes)
                default: view
                }
            }
        }
    }

    @MainActor static func frame(_ c: KCall, _ view: AnyView) -> AnyView {
        let w = c.cg("width"), h = c.cg("height")
        let minW = c.cg("minWidth"), maxW = c.cg("maxWidth"), minH = c.cg("minHeight"), maxH = c.cg("maxHeight")
        let idealW = c.cg("idealWidth"), idealH = c.cg("idealHeight")
        let align = c.alignment("alignment")
        var out = view
        if w != nil || h != nil { out = AnyView(out.frame(width: w, height: h, alignment: align)) }
        if minW != nil || maxW != nil || minH != nil || maxH != nil || idealW != nil || idealH != nil {
            out = AnyView(out.frame(minWidth: minW, idealWidth: idealW, maxWidth: maxW, minHeight: minH, idealHeight: idealH, maxHeight: maxH, alignment: align))
        }
        return out
    }

    // MARK: Geometry values

    static func geometry(_ r: KRegistry) {
        r.type("CGSize", .layout) { t in
            t.initializer { c in .native(.size(c.arg("width")?.asDouble ?? 0, c.arg("height")?.asDouble ?? 0)) }
            t.staticProperty("zero") { _ in .native(.size(0, 0)) }
            t.property("width") { c in if case .native(.size(let w, _)) = c.receiver { return .double(w) }; return .double(0) }
            t.property("height") { c in if case .native(.size(_, let h)) = c.receiver { return .double(h) }; return .double(0) }
        }
        r.type("CGPoint", .layout) { t in
            t.initializer { c in .native(.point(c.arg("x")?.asDouble ?? 0, c.arg("y")?.asDouble ?? 0)) }
            t.staticProperty("zero") { _ in .native(.point(0, 0)) }
            t.property("x") { c in if case .native(.point(let x, _)) = c.receiver { return .double(x) }; return .double(0) }
            t.property("y") { c in if case .native(.point(_, let y)) = c.receiver { return .double(y) }; return .double(0) }
        }
        r.type("CGRect", .layout) { t in
            t.initializer { c in
                if case .native(.point(let x, let y))? = c.arg("origin"), case .native(.size(let w, let h))? = c.arg("size") { return .native(.rect(x, y, w, h)) }
                return .native(.rect(c.arg("x")?.asDouble ?? 0, c.arg("y")?.asDouble ?? 0, c.arg("width")?.asDouble ?? 0, c.arg("height")?.asDouble ?? 0))
            }
            t.staticProperty("zero") { _ in .native(.rect(0, 0, 0, 0)) }
            @MainActor func rect(_ c: KCall) -> (Double, Double, Double, Double) {
                if case .native(.rect(let x, let y, let w, let h)) = c.receiver { return (x, y, w, h) }
                return (0, 0, 0, 0)
            }
            t.property("width") { c in .double(rect(c).2) }
            t.property("height") { c in .double(rect(c).3) }
            t.property("minX") { c in .double(rect(c).0) }
            t.property("minY") { c in .double(rect(c).1) }
            t.property("midX") { c in let r = rect(c); return .double(r.0 + r.2 / 2) }
            t.property("midY") { c in let r = rect(c); return .double(r.1 + r.3 / 2) }
            t.property("maxX") { c in let r = rect(c); return .double(r.0 + r.2) }
            t.property("maxY") { c in let r = rect(c); return .double(r.1 + r.3) }
            t.property("origin") { c in let r = rect(c); return .native(.point(r.0, r.1)) }
            t.property("size") { c in let r = rect(c); return .native(.size(r.2, r.3)) }
            t.method("insetBy") { c in
                let (x, y, w, h) = rect(c)
                let dx = c.arg("dx")?.asDouble ?? 0, dy = c.arg("dy")?.asDouble ?? 0
                return .native(.rect(x + dx, y + dy, w - 2 * dx, h - 2 * dy))
            }
            t.method("offsetBy") { c in
                let (x, y, w, h) = rect(c)
                return .native(.rect(x + (c.arg("dx")?.asDouble ?? 0), y + (c.arg("dy")?.asDouble ?? 0), w, h))
            }
        }
        r.type("EdgeInsets", .layout) { t in
            t.initializer { c in .tuple(c.args, c.labels) }
        }
        // SwiftUI's enum-like types: their members are symbolic until a view reads them.
        for name in ["UnitPoint", "Alignment", "Edge", "HorizontalAlignment", "VerticalAlignment", "TextAlignment", "ContentMode",
                     "Visibility", "ColorScheme", "Axis", "SymbolRenderingMode", "Image.Scale"] {
            r.type(name, .layout) { t in
                t.anyStatic { _, member in .native(.implicit(member, [])) }
            }
        }
    }
}
