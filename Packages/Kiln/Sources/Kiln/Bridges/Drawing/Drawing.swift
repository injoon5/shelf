//
//  Drawing.swift
//  Bridges: colors, shape styles, angles, animations and transitions
//
//  Shapes and paths are in Shapes.swift, images in Images.swift, and the
//  modifiers that draw (color, effects, transforms, animation) in Effects.swift.
//

import SwiftUI

/// Color names and parsing, shared with the renderer.
@MainActor
enum KDrawing {
    static let colorNames: [String: Color] = [
        "red": .red, "orange": .orange, "yellow": .yellow, "green": .green, "mint": .mint, "teal": .teal,
        "cyan": .cyan, "blue": .blue, "indigo": .indigo, "purple": .purple, "pink": .pink, "brown": .brown,
        "white": .white, "gray": .gray, "black": .black, "clear": .clear, "primary": .primary,
        "secondary": .secondary, "accentColor": .accentColor, "grey": .gray,
    ]

    static let systemColors: [String: Color] = [
        "systemBackground": Color(uiColorCompat: "systemBackground"), "secondarySystemBackground": Color(uiColorCompat: "secondarySystemBackground"),
        "tertiarySystemBackground": Color(uiColorCompat: "tertiarySystemBackground"), "systemGroupedBackground": Color(uiColorCompat: "systemGroupedBackground"),
        "secondarySystemGroupedBackground": Color(uiColorCompat: "secondarySystemGroupedBackground"), "systemGray": .gray,
        "systemGray2": Color(uiColorCompat: "systemGray2"), "systemGray3": Color(uiColorCompat: "systemGray3"),
        "systemGray4": Color(uiColorCompat: "systemGray4"), "systemGray5": Color(uiColorCompat: "systemGray5"),
        "systemGray6": Color(uiColorCompat: "systemGray6"), "label": .primary, "secondaryLabel": .secondary,
        "tertiaryLabel": Color(uiColorCompat: "tertiaryLabel"), "separator": Color(uiColorCompat: "separator"),
        "systemBlue": .blue, "systemRed": .red, "systemGreen": .green, "systemOrange": .orange, "systemYellow": .yellow,
        "systemPink": .pink, "systemPurple": .purple, "systemTeal": .teal, "systemIndigo": .indigo, "systemMint": .mint,
        "systemCyan": .cyan, "systemBrown": .brown, "systemFill": Color(uiColorCompat: "systemFill"),
        "secondarySystemFill": Color(uiColorCompat: "secondarySystemFill"), "tertiarySystemFill": Color(uiColorCompat: "tertiarySystemFill"),
    ]

    static let materials = ["secondary", "tertiary", "quaternary", "primary", "tint", "ultraThinMaterial", "thinMaterial", "regularMaterial",
                            "material", "thickMaterial", "ultraThickMaterial", "bar", "background", "foreground", "separator"]

    static func hexColor(_ s: String) -> Color? {
        var h = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        if h.hasPrefix("0x") { h.removeFirst(2) }
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        if h.count == 8 {
            return Color(red: Double((v >> 24) & 0xFF) / 255, green: Double((v >> 16) & 0xFF) / 255,
                         blue: Double((v >> 8) & 0xFF) / 255, opacity: Double(v & 0xFF) / 255)
        }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// `Color(…)`: components, a name, hex, another color.
    static func color(_ c: KCall) -> KV {
        let args = c.args, labels = c.labels
        func d(_ l: String) -> Double? { labels.firstIndex(of: l).flatMap { args[$0].asDouble } }
        if let r = d("red"), let g = d("green"), let b = d("blue") {
            return .native(.color(Color(red: r, green: g, blue: b, opacity: d("opacity") ?? d("alpha") ?? 1)))
        }
        if let h = d("hue"), let s = d("saturation"), let b = d("brightness") {
            return .native(.color(Color(hue: h, saturation: s, brightness: b, opacity: d("opacity") ?? 1)))
        }
        if let w = d("white") { return .native(.color(Color(white: w, opacity: d("opacity") ?? 1))) }
        if let first = args.first {
            switch first {
            case .native(.color(let col)): return .native(.color(col))
            case .native(.implicit(let n, _)):
                if let col = systemColors[n] ?? colorNames[n] { return .native(.color(col)) }
            case .string(let s):
                if let hex = hexColor(s) { return .native(.color(hex)) }
                if let col = colorNames[s.lowercased()] { return .native(.color(col)) }
                return .native(.color(Color(s)))
            default: break
            }
        }
        if let hex = labels.firstIndex(of: "hex"), let s = args[hex].asString, let col = hexColor(s) { return .native(.color(col)) }
        if labels.firstIndex(of: "hex") != nil, let n = args.first?.asInt {
            return .native(.color(Color(red: Double((n >> 16) & 0xFF) / 255, green: Double((n >> 8) & 0xFF) / 255, blue: Double(n & 0xFF) / 255)))
        }
        return .native(.color(.gray))
    }

    static func animation(_ name: String, _ args: [KV], _ labels: [String?]) -> Animation? {
        func arg(_ l: String) -> Double? { labels.firstIndex(of: l).flatMap { args[$0].asDouble } }
        let duration = arg("duration")
        switch name {
        case "default": return .default
        case "easeInOut": return duration.map { .easeInOut(duration: $0) } ?? .easeInOut
        case "easeIn": return duration.map { .easeIn(duration: $0) } ?? .easeIn
        case "easeOut": return duration.map { .easeOut(duration: $0) } ?? .easeOut
        case "linear": return duration.map { .linear(duration: $0) } ?? .linear
        case "spring", "interactiveSpring", "interpolatingSpring":
            if let r = arg("response") { return .spring(response: r, dampingFraction: arg("dampingFraction") ?? 0.825) }
            if let d = arg("duration") { return .spring(duration: d, bounce: arg("bounce") ?? 0) }
            return .spring()
        case "timingCurve":
            // `.timingCurve(0.2, 0.8, 0.2, 1, duration:)`, or a `UnitCurve` and a duration.
            let numbers = zip(args, labels).filter { $0.1 == nil }.compactMap { $0.0.asDouble }
            if numbers.count >= 4 { return .timingCurve(numbers[0], numbers[1], numbers[2], numbers[3], duration: duration ?? 0.35) }
            if let curve = args.first?.boxed(UnitCurve.self) { return .timingCurve(curve, duration: duration ?? 0.35) }
            return .easeInOut
        case "bouncy": return .bouncy
        case "snappy": return .snappy
        case "smooth": return .smooth
        default: return nil
        }
    }

    static let animationNames = ["default", "easeInOut", "easeIn", "easeOut", "linear", "spring", "interactiveSpring", "interpolatingSpring",
                                 "bouncy", "snappy", "smooth"]
    /// Static methods with no property form (`Animation.timingCurve(…)`).
    static let animationFunctions = ["timingCurve"]
}

@objc(KilnBridges_Drawing)
final class DrawingBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        colors(r)
        motion(r)
        shapes(r)
        animatable(r)
        images(r)
        effects(r)
        canvas(r)
        KAffines.register(r)
        round1(r)
        imageRendering(r)
    }

    override class func extend(into r: KRegistry) {
        imageRenderingLater(r)
    }

    // MARK: Colors and styles

    static func colors(_ r: KRegistry) {
        r.type("Color", .drawing, notes: "Named and system colors, `Color(red:green:blue:)`, `Color(hue:…)`, `Color(white:)`, hex strings, and `.opacity`.") { t in
            t.manifestKind = "view"
            t.membersInManifest = true
            for sig in ["red:number green:number blue:number opacity:number?", "_:any red:number green:number blue:number opacity:number?",
                        "hue:number saturation:number brightness:number opacity:number?", "white:number opacity:number?",
                        "_:UIColor", "uiColor:UIColor", "_:string bundle:any?"] {
                t.initializer(sig) { c in KDrawing.color(c) }
            }
            // And whatever else models write (`Color(hex:)`, `alpha:`), read loosely.
            t.initializer(kinds: [nil: .typed("UIColor")]) { c in KDrawing.color(c) }
            t.staticProperties(KDrawing.colorNames.mapValues { .native(.color($0)) })
            for (name, col) in KDrawing.systemColors { t.staticProperty(name) { _ in .native(.color(col)) } }
            t.anyStatic { _, name in .native(.implicit(name, [])) }
            t.anyStaticMethod { c, name in .native(.implicit(name, c.args)) }
            t.implicit { name, _, _ in (KDrawing.colorNames[name] ?? KDrawing.systemColors[name]).map { .native(.color($0)) } }
            @MainActor func col(_ c: KCall) -> Color { if case .native(.color(let x)) = c.receiver { return x }; return .clear }
            t.property("gradient") { c in
                .view(.primitive("LinearGradient", [.array([.native(.color(col(c).opacity(0.8))), .native(.color(col(c)))])], ["colors"], line: c.line))
            }
            t.property("description") { c in .string(col(c).description) }
            t.method("opacity") { c in .native(.color(col(c).opacity(c.first?.asDouble ?? 1))) }
            t.method("mix", "with:Color by:number in:any?") { c in
                guard #available(iOS 18, macOS 15, *), let other = c.color("with") else { return .native(.color(col(c))) }
                return .native(.color(col(c).mix(with: other, by: c.double("by") ?? 0.5)))
            }
        }
        r.alias("UIColor", to: "Color")
        r.alias("NSColor", to: "Color")
        r.alias("ColorOrStyle", to: "Color", engineOnly: true)
        // A color as a view (a color value in a body).
        r.view("Color", .drawing) { v in
            v.engineOnly()
            v.form("_:any") { c in c.color(0) ?? .gray }
        }
        // `.red` with no type expected is a color, except `.primary` and `.secondary` (also styles).
        for (name, col) in KDrawing.colorNames where name != "primary" && name != "secondary" {
            r.addContextFree(name) { _, _, expected in expected == nil ? .native(.color(col)) : nil }
        }

        r.type("ShapeStyle", .drawing) { t in
            t.membersInManifest = true
            for name in KDrawing.materials { t.staticProperty(name) { _ in .native(.implicit(name, [])) } }
            for name in KDrawing.colorNames.keys where name != "primary" && name != "secondary" {
                t.staticProperty(name) { _ in .native(.color(KDrawing.colorNames[name]!)) }
            }
        }
        r.type("Gradient", .drawing) { t in
            t.initializer(kinds: ["colors": .typedArray("Color")]) { c in .native(.implicit("gradient", [c.arg("colors") ?? .array([])])) }
        }
        r.type("StrokeStyle", .drawing) { t in
            t.initializer { c in
                var s = KStrokeStyle()
                s.lineWidth = c.arg("lineWidth")?.asDouble ?? 1
                if case .native(.implicit(let cap, _))? = c.arg("lineCap") { s.lineCap = cap }
                if case .native(.implicit(let join, _))? = c.arg("lineJoin") { s.lineJoin = join }
                if let dash = c.arg("dash")?.asArray { s.dash = dash.compactMap(\.asDouble) }
                return .native(.strokeStyle(s))
            }
        }
    }

    // MARK: Angles, animations, transitions

    static func motion(_ r: KRegistry) {
        r.addContextFree("degrees") { args, _, _ in args.first?.asDouble.map { .native(.angle($0)) } }
        r.addContextFree("radians") { args, _, _ in args.first?.asDouble.map { .native(.angle($0 * 180 / .pi)) } }
        r.type("Angle", .drawing) { t in
            t.initializer { c in
                if let d = c.arg("degrees")?.asDouble { return .native(.angle(d)) }
                if let rad = c.arg("radians")?.asDouble { return .native(.angle(rad * 180 / .pi)) }
                return .native(.angle(0))
            }
            t.staticProperty("zero") { _ in .native(.angle(0)) }
            t.implicit { name, args, _ in
                if name == "degrees", let d = args.first?.asDouble { return .native(.angle(d)) }
                if name == "radians", let rad = args.first?.asDouble { return .native(.angle(rad * 180 / .pi)) }
                if name == "zero" { return .native(.angle(0)) }
                return nil
            }
            @MainActor func deg(_ c: KCall) -> Double { if case .native(.angle(let d)) = c.receiver { return d }; return 0 }
            t.property("degrees") { c in .double(deg(c)) }
            t.property("radians") { c in .double(deg(c) * .pi / 180) }
            t.method("degrees") { c in .double(deg(c)) }
        }

        r.type("Animation", .drawing, notes: "`.default`, the eases with `duration:`, `.spring(response:dampingFraction:)` or `(duration:bounce:)`, `.bouncy`, `.snappy`, `.smooth`.") { t in
            t.membersInManifest = true
            t.initializer { _ in .native(.animation(KRef(.default))) }
            for name in KDrawing.animationNames {
                t.staticProperty(name) { _ in KDrawing.animation(name, [], []).map { .native(.animation(KRef($0))) } ?? .nilValue }
            }
            t.anyStaticMethod { c, name in
                KDrawing.animation(name, c.args, c.labels).map { .native(.animation(KRef($0))) } ?? .native(.implicit(name, c.args))
            }
            t.anyStatic { _, name in .native(.implicit(name, [])) }
            t.implicit { name, args, labels in KDrawing.animation(name, args, labels).map { .native(.animation(KRef($0))) } }
            @MainActor func anim(_ c: KCall) -> Animation? { if case .native(.animation(let a)) = c.receiver { return a.value }; return nil }
            t.method("repeatForever") { c in .native(.animation(KRef(anim(c)?.repeatForever(autoreverses: c.bool("autoreverses", default: true))))) }
            t.method("repeatCount") { c in
                .native(.animation(KRef(anim(c)?.repeatCount(c.first?.asInt ?? 1, autoreverses: c.bool("autoreverses", default: true)))))
            }
            t.method("delay") { c in .native(.animation(KRef(anim(c)?.delay(c.first?.asDouble ?? 0)))) }
            t.method("speed") { c in .native(.animation(KRef(anim(c)?.speed(c.first?.asDouble ?? 1)))) }
        }
        for name in KDrawing.animationNames where name != "default" {
            r.addContextFree(name) { args, labels, expected in
                guard expected == nil || expected == "Animation" else { return nil }
                return KDrawing.animation(name, args, labels).map { .native(.animation(KRef($0))) }
            }
        }
        r.function("withAnimation", .drawing, owner: "SwiftUI", kinds: [nil: .typed("Animation")]) { c in
            guard case .function(let body)? = c.last else { return .void }
            var anim: Animation? = .default
            if c.args.count > 1 {
                if case .native(.animation(let a)) = c.args[0] { anim = a.value }
                else if case .native(.implicit(let n, let a)) = c.args[0] { anim = KDrawing.animation(n, a, []) ?? .default }
                else if case .nilValue = c.args[0] { anim = nil }
            }
            var result: KV = .void
            var thrown: Error?
            withAnimation(anim) {
                do { result = try c.interp.call(body, [], []) } catch { thrown = error }
            }
            if let thrown { throw thrown }
            return result
        }

        // `Transition` (iOS 17): its members are read by `.transition` as symbols.
        r.type("Transition", .drawing) { t in
            t.membersInManifest = true
            for name in ["opacity", "scale", "slide", "move", "push", "identity", "blurReplace", "symbolEffect"] {
                t.staticProperty(name, support: name == "blurReplace" || name == "symbolEffect" ? .stub : .full) { _ in .native(.implicit(name, [])) }
            }
            t.anyStatic { _, name in .native(.implicit(name, [])) }
        }
        r.type("AnyTransition", .drawing, notes: "The built-ins, `.asymmetric`, `.combined(with:)` and `.modifier(active:identity:)`.") { t in
            t.membersInManifest = true
            for name in ["opacity", "scale", "slide", "move", "push", "identity"] { t.staticProperty(name) { _ in .native(.transition(name, [])) } }
            t.initializer("_:any") { c in c.args[0] }
            t.staticMethod("modifier", "active:any identity:any") { c in .native(.transition("modifier", c.args)) }
            t.staticMethod("asymmetric", "insertion:AnyTransition removal:AnyTransition") { c in .native(.transition("asymmetric", c.args)) }
            t.method("combined", "with:AnyTransition") { c in .native(.transition("combined", [c.receiver, c.args[0]])) }
            t.anyStatic { _, name in .native(.transition(name, [])) }
            t.anyStaticMethod { c, name in .native(.transition(name, c.args)) }
        }
    }
}

extension Color {
    /// A UIKit semantic color by name, without importing UIKit on macOS.
    init(uiColorCompat name: String) {
        #if canImport(UIKit)
        let map: [String: UIColor] = [
            "systemBackground": .systemBackground, "secondarySystemBackground": .secondarySystemBackground,
            "tertiarySystemBackground": .tertiarySystemBackground, "systemGroupedBackground": .systemGroupedBackground,
            "secondarySystemGroupedBackground": .secondarySystemGroupedBackground, "systemGray2": .systemGray2,
            "systemGray3": .systemGray3, "systemGray4": .systemGray4, "systemGray5": .systemGray5, "systemGray6": .systemGray6,
            "tertiaryLabel": .tertiaryLabel, "separator": .separator, "systemFill": .systemFill,
            "secondarySystemFill": .secondarySystemFill, "tertiarySystemFill": .tertiarySystemFill,
        ]
        self = Color(uiColor: map[name] ?? .systemGray)
        #else
        self = .gray
        #endif
    }
}
