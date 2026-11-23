//
//  Typesetting.swift
//  Bridges: the rest of Text's modifiers (PLAN.md §2)
//

import SwiftUI
#if os(iOS) && canImport(DataDetection)
import DataDetection
#endif

extension KTextBridges {
    static func typesetting(_ r: KRegistry) {
        r.extend("Font") { t in
            t.staticProperty("default") { _ in
                if #available(iOS 26, macOS 26, *) { return .native(.font(.default)) }
                return .native(.font(.body))
            }
        }
        r.modifier("allowsTightening", .text) { m in
            m.form("_:bool") { c, view in view.allowsTightening(c.bool(0, default: true)) }
        }
        r.modifier("flipsForRightToLeftLayoutDirection", .text) { m in
            m.form("_:bool") { c, view in view.flipsForRightToLeftLayoutDirection(c.bool(0, default: true)) }
        }
        r.modifier("fontWidth", .text) { m in
            m.form("_:any") { c, view in view.fontWidth(width(c.symbol(0))) }
            m.text { c, t in t.fontWidth(width(c.symbol(0))) }
        }
        r.modifier("textScale", .text) { m in
            m.form("_:any isEnabled:bool?") { c, view in view.textScale(.secondary, isEnabled: c.bool("isEnabled", default: true)) }
            m.text { c, t in t.textScale(.secondary, isEnabled: c.bool("isEnabled", default: true)) }
        }
        r.modifier("textVariant", .text, introduced: "18.0") { m in
            m.formOnBase("_:any", receiver: "Text") { c in
                if #available(iOS 18, macOS 15, *), let t = c.base.flatMap({ c.r.text($0) }) { AnyView(t.textVariant(.sizeDependent)) } else { c.view }
            }
        }
        r.modifier("typesettingLanguage", .text) { m in
            m.form("_:any isEnabled:bool?") { c, view in
                view.typesettingLanguage(language(c[0]), isEnabled: c.bool("isEnabled", default: true))
            }
            m.text { c, t in t.typesettingLanguage(language(c[0]), isEnabled: c.bool("isEnabled", default: true)) }
        }
        r.modifier("writingDirection", .text, introduced: "26.0") { m in
            m.form("strategy:any") { c, view in
                if #available(iOS 26, macOS 26, *) {
                    AnyView(view.writingDirection(strategy: c.symbol("strategy") == "contentBased" ? .contentBased : .layoutBased))
                } else {
                    view
                }
            }
        }
        r.modifier("lineHeight", .text, introduced: "26.0") { m in
            m.form("_:any") { c, view in
                if #available(iOS 26, macOS 26, *) { AnyView(view.lineHeight(lineHeight(c[0]))) } else { view }
            }
        }
        r.modifier("dataDetection", .text, introduced: "27.0", notes: "Links, phone numbers and dates in text become tappable.") { m in
            m.form("_:any? options:any?") { _, view in
                #if os(iOS) && canImport(DataDetection)
                if #available(iOS 27, *) { AnyView(view.dataDetection()) } else { view }
                #else
                view
                #endif
            }
        }
    }

    @MainActor static func width(_ name: String?) -> Font.Width? {
        switch name {
        case "compressed": return .compressed
        case "condensed": return .condensed
        case "expanded": return .expanded
        case "standard": return .standard
        default: return nil
        }
    }

    @MainActor static func language(_ v: KV?) -> Locale.Language {
        if case .native(.object(_, let ref))? = v, let locale = ref.value as? Locale { return locale.language }
        if case .string(let s)? = v { return Locale.Language(identifier: s) }
        if case .native(.implicit(_, let a))? = v, case .string(let s)? = a.first { return Locale.Language(identifier: s) }
        return Locale.current.language
    }

    @available(iOS 26, macOS 26, *)
    @MainActor static func lineHeight(_ v: KV?) -> AttributedString.LineHeight? {
        guard case .native(.implicit(let n, let a))? = v else { return nil }
        let x = a.first?.cg ?? 1
        switch n {
        case "multiple": return .multiple(factor: x)
        case "exact": return .exact(points: x)
        case "leading": return .leading(increase: x)
        case "loose": return .loose
        case "tight": return .tight
        default: return nil
        }
    }
}
