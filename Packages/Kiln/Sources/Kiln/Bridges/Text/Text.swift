//
//  Text.swift
//  Bridges: Text, fonts and typography
//
//  A string literal in `Text("…")` is a LocalizedStringKey, so the numbers
//  in it are formatted as SwiftUI formats them ("1,400 pages"). Modifiers
//  that keep a `Text` a `Text` say how (`m.text`), so `Text + Text` and a
//  `Text` in a `Label` keep them.
//

import SwiftUI

@objc(KilnBridges_Text)
final class KTextBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        text(r)
        fonts(r)
        typography(r)
        attributed(r)
    }

    // MARK: Text

    static func text(_ r: KRegistry) {
        r.view("Text", .text, support: .partial, notes: "Strings, `verbatim:`, `format:`, and dates with `style:`. A literal's numbers are formatted as SwiftUI does.") { v in
            v.form("_:title") { c in c.r.textOf(c.a) }
            v.form("verbatim:string") { c in c.r.textOf(c.a) }
            v.form("_:any format:any") { c in c.r.textOf(c.a) }
            v.form("_:any style:Text.DateStyle") { c in c.r.textOf(c.a) }
            v.form("timerInterval:any pauseTime:any? countsDown:bool? showsHours:bool?", notes: "A live countdown or count-up over a `start...end` range of dates.") { c in c.r.textOf(c.a) }
            // A literal is marked so the renderer makes a LocalizedStringKey of it.
            v.make { c in
                var labels = c.labels
                if c.syntax.first == .stringLiteral, labels.first == .some(nil) { labels[0] = "_literal" }
                return .view(KView(.primitive("Text", c.args, labels, line: c.line), bound: c.overload.map { KBound(overload: $0, binding: c.binding) }))
            }
        }
    }

    // MARK: Fonts

    static let fontStyles: [String: Font] = [
        "largeTitle": .largeTitle, "title": .title, "title2": .title2, "title3": .title3, "headline": .headline,
        "subheadline": .subheadline, "body": .body, "callout": .callout, "footnote": .footnote, "caption": .caption,
        "caption2": .caption2,
    ]

    static func fonts(_ r: KRegistry) {
        r.addContextFree("system") { args, labels, _ in font("system", args, labels).map { .native(.font($0)) } }
        r.type("Font", .text) { t in
            t.membersInManifest = true
            t.initializer(kinds: [nil: .typed("Font")]) { c in
                if case .native(.font(let f))? = c.first { return .native(.font(f)) }
                return .native(.font(.body))
            }
            for (name, f) in fontStyles { t.staticProperty(name) { _ in .native(.font(f)) } }
            t.staticMethod("system", notes: "`size:weight:design:`, or a text style with `design:` and `weight:`.") { c in
                font("system", c.args, c.labels).map { .native(.font($0)) } ?? .native(.implicit("system", c.args))
            }
            t.staticMethod("custom") { c in font("custom", c.args, c.labels).map { .native(.font($0)) } ?? .native(.implicit("custom", c.args)) }
            t.implicit { name, args, labels in font(name, args, labels).map { .native(.font($0)) } }
            @MainActor func f(_ c: KCall) -> Font { if case .native(.font(let f)) = c.receiver { return f }; return .body }
            t.property("bold") { c in .native(.font(f(c).bold())) }
            t.property("italic") { c in .native(.font(f(c).italic())) }
            t.property("monospaced") { c in .native(.font(f(c).monospaced())) }
            t.property("monospacedDigit") { c in .native(.font(f(c).monospacedDigit())) }
            t.property("smallCaps") { c in .native(.font(f(c).smallCaps())) }
            t.method("bold") { c in .native(.font(f(c).bold())) }
            t.method("italic") { c in .native(.font(f(c).italic())) }
            t.method("weight") { c in
                if case .native(.implicit(let w, _))? = c.first { return .native(.font(f(c).weight(weight(w)))) }
                return .native(.font(f(c)))
            }
            t.method("monospacedDigit") { c in .native(.font(f(c).monospacedDigit())) }
            t.method("monospaced") { c in .native(.font(f(c).monospaced())) }
            t.method("smallCaps") { c in .native(.font(f(c).smallCaps())) }
            t.methods(["leading", "width"]) { c, _ in .native(.font(f(c))) }
        }
    }

    static func font(_ name: String, _ args: [KV], _ labels: [String?]) -> Font? {
        if let f = fontStyles[name] { return f }
        if name == "system" {
            if let i = labels.firstIndex(of: "size"), let size = args[i].asDouble {
                var f = Font.system(size: size)
                if let w = labels.firstIndex(of: "weight"), case .native(.implicit(let wn, _)) = args[w] {
                    f = Font.system(size: size, weight: weight(wn), design: labels.firstIndex(of: "design").flatMap { design(args[$0]) } ?? .default)
                } else if let d = labels.firstIndex(of: "design") {
                    f = Font.system(size: size, design: design(args[d]) ?? .default)
                }
                return f
            }
            if let style = args.first, case .native(.implicit(let s, _)) = style, let base = fontStyles[s] {
                var f = base
                if let d = labels.firstIndex(of: "design"), let dd = design(args[d]) { f = .system(textStyle(s), design: dd) }
                if let w = labels.firstIndex(of: "weight"), case .native(.implicit(let wn, _)) = args[w] { f = f.weight(weight(wn)) }
                return f
            }
        }
        if name == "custom", let fam = args.first?.asString {
            let size = labels.firstIndex(of: "size").flatMap { args[$0].asDouble } ?? 17
            return .custom(fam, size: size)
        }
        return nil
    }

    static func textStyle(_ s: String) -> Font.TextStyle {
        switch s {
        case "largeTitle": return .largeTitle
        case "title": return .title
        case "title2": return .title2
        case "title3": return .title3
        case "headline": return .headline
        case "subheadline": return .subheadline
        case "callout": return .callout
        case "footnote": return .footnote
        case "caption": return .caption
        case "caption2": return .caption2
        default: return .body
        }
    }

    static func design(_ v: KV) -> Font.Design? {
        guard case .native(.implicit(let d, _)) = v else { return nil }
        switch d {
        case "rounded": return .rounded
        case "monospaced": return .monospaced
        case "serif": return .serif
        default: return .default
        }
    }

    static func weight(_ n: String) -> Font.Weight {
        switch n {
        case "ultraLight": return .ultraLight
        case "thin": return .thin
        case "light": return .light
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return .regular
        }
    }

    // MARK: Typography

    static func typography(_ r: KRegistry) {
        r.modifier("font", .text) { m in
            m.form("_:Font?") { c, view in
                if let f = c.font(0) { view.font(f) } else { view }
            }
            m.text { c, t in c.font(0).map { t.font($0) } ?? t }
        }
        r.modifier("fontWeight", .text) { m in
            m.form("_:Font.Weight?") { c, view in
                if let w = c.symbol(0) { view.fontWeight(weight(w)) } else { view }
            }
            m.text { c, t in c.symbol(0).map { t.fontWeight(weight($0)) } ?? t }
        }
        r.modifier("fontDesign", .text) { m in
            m.form("_:Font.Design?") { c, view in
                if let d = design(c[0] ?? .void) { view.fontDesign(d) } else { view }
            }
        }
        r.modifier("bold", .text) { m in
            m.form("_:bool?") { c, view in view.bold(c.bool(0, default: true)) }
            m.text { c, t in t.bold(c.bool(0, default: true)) }
        }
        r.modifier("italic", .text) { m in
            m.form("_:bool?") { _, view in view.italic() }
            m.text { _, t in t.italic() }
        }
        r.modifier("underline", .text) { m in
            m.form("_:bool? pattern:any? color:Color?") { _, view in view.underline() }
            m.text { _, t in t.underline() }
        }
        r.modifier("strikethrough", .text) { m in
            m.form("_:bool? pattern:any? color:Color?") { _, view in view.strikethrough() }
            m.text { _, t in t.strikethrough() }
        }
        r.modifier("monospaced", .text) { m in
            m.form("_:bool?") { _, view in view.monospaced() }
        }
        r.modifier("monospacedDigit", .text) { m in
            m.form("") { _, view in view.monospacedDigit() }
            m.text { _, t in t.monospacedDigit() }
        }
        r.modifier("kerning", .text) { m in
            m.form("_:number") { c, view in view.kerning(c.cg(0) ?? 0) }
            m.text { c, t in t.kerning(c.cg(0) ?? 0) }
        }
        r.modifier("tracking", .text) { m in
            m.form("_:number") { c, view in view.tracking(c.cg(0) ?? 0) }
        }
        r.modifier("baselineOffset", .text, support: .partial, notes: "On a `Text`.") { m in
            m.form("_:number", receiver: "Text") { c, view in view }
            m.text { c, t in t.baselineOffset(c.cg(0) ?? 0) }
        }
        r.modifier("lineLimit", .text) { m in
            m.form("_:any") { c, view in
                if case .range(let lo, let hi, _)? = c[0] {
                    view.lineLimit((lo.asInt ?? 1)...(hi.asInt ?? 1))
                } else {
                    view.lineLimit(c.int(0))
                }
            }
            m.form("_:number reservesSpace:bool") { c, view in view.lineLimit(c.int(0) ?? 1, reservesSpace: c.bool("reservesSpace", default: false)) }
        }
        r.modifier("lineSpacing", .text) { m in
            m.form("_:number") { c, view in view.lineSpacing(c.cg(0) ?? 0) }
        }
        r.modifier("multilineTextAlignment", .text) { m in
            m.form("_:TextAlignment") { c, view in
                view.multilineTextAlignment(c.symbol(0) == "center" ? .center : (c.symbol(0) == "trailing" ? .trailing : .leading))
            }
        }
        r.modifier("minimumScaleFactor", .text) { m in
            m.form("_:number") { c, view in view.minimumScaleFactor(c.cg(0) ?? 1) }
        }
        r.modifier("truncationMode", .text) { m in
            m.form("_:Text.TruncationMode") { c, view in
                if let n = c.symbol(0) { view.truncationMode(n == "head" ? .head : (n == "middle" ? .middle : .tail)) } else { view }
            }
        }
        r.modifier("textCase", .text) { m in
            m.form("_:Text.Case?") { c, view in
                if let n = c.symbol(0) { view.textCase(n == "lowercase" ? .lowercase : .uppercase) } else { view.textCase(nil) }
            }
        }
        r.modifier("textSelection", .text) { m in
            m.form("_:any") { _, view in view.textSelection(.enabled) }
        }
    }
}
