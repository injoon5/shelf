//
//  ControlModifiers.swift
//  Bridges: the controls' other modifiers, views and environment values
//
//  `labelsHidden`, `menuIndicator`, `buttonRepeatBehavior`, `SliderTick`,
//  `RenameButton`, and `\.isEnabled`, `\.controlSize`… read from SwiftUI's
//  environment where the view is shown.
//

import SwiftUI

extension ControlsBridges {
    static func moreControls(_ r: KRegistry) {
        controlViews(r)
        symbolicTypes(r)
        controlModifiers(r)
        controlEnvironment(r)
    }

    // MARK: Views

    static func controlViews(_ r: KRegistry) {
        r.view("RenameButton", .controls, notes: "Runs the nearest `.renameAction { }`.") { v in
            v.form("") { _ in RenameButton() }
        }
        r.view("SliderTick", .controls, notes: "In a `Slider`'s `ticks:`.") { v in
            v.manifestKind = "content"
            v.forms(["_:number", "_:number label:content", "_:title _:number"]) { _ in EmptyView() }
        }
        r.view("SliderTickContentForEach", .controls, notes: "In a `Slider`'s `ticks:`: one `SliderTick` per element.") { v in
            v.manifestKind = "content"
            v.forms(["_:any content:content", "_:any id:any content:content"]) { _ in EmptyView() }
        }
        // `ButtonBorderShape.capsule` and `TextInputBorderShape.roundedRectangle` as shapes.
        r.view("ButtonBorderShape", .controls, support: .partial,
               notes: "Its members as a shape (`ButtonBorderShape.capsule`), filled with the foreground style; use `Capsule()` to `.fill` or `.stroke` one.") { v in
            v.form("_:ButtonBorderShape") { c in
                if let shape = buttonBorderShape(c[0]) { shape } else { Capsule() }
            }
        }
        r.type("ButtonBorderShape", .controls) { t in
            t.internal()
            for name in ["capsule", "circle", "roundedRectangle", "automatic"] {
                t.staticProperty(name) { _ in .view(.primitive("ButtonBorderShape", [.native(.implicit(name, []))], [nil], line: 0)) }
            }
            t.staticMethod("roundedRectangle", "radius:number") { c in
                .view(.primitive("ButtonBorderShape", [.native(.implicit("roundedRectangle", [c[0] ?? .double(8)]))], [nil], line: c.line))
            }
        }
        r.view("TextInputBorderShape", .controls, introduced: "27.0", notes: "For `.textInputBorderShape(_:)`: `.capsule`, `.roundedRectangle` or `.automatic`.") { v in
            v.form("_:TextInputBorderShape") { c in
                if c.symbol(0) == "capsule" { Capsule() } else { RoundedRectangle(cornerRadius: 8) }
            }
        }
    }

    // MARK: Modifiers

    static func symbolicTypes(_ r: KRegistry) {
        for name in ["ButtonRole", "ControlSize", "MenuOrder", "ButtonRepeatBehavior", "ButtonSizing", "PaletteSelectionEffect"] {
            r.type(name, .controls) { t in
                t.internal()
                t.anyStatic { _, member in .native(.implicit(member, [])) }
            }
        }
    }

    static let visibilities = ["automatic", "visible", "hidden"]

    static func controlModifiers(_ r: KRegistry) {
        r.modifier("labelsHidden", .controls) { m in
            m.form("") { _, view in view.labelsHidden() }
        }
        r.modifier("labelsVisibility", .controls, introduced: "18.0") { m in
            m.form("_:Visibility") { c, view in
                if #available(iOS 18.0, macOS 15.0, *) { AnyView(view.labelsVisibility(KControlValues.visibility(c[0]))) } else { view }
            }
        }
        r.modifier("menuIndicator", .controls) { m in
            m.form("_:Visibility") { c, view in view.menuIndicator(KControlValues.visibility(c[0])) }
        }
        r.modifier("menuOrder", .controls) { m in
            m.form("_:MenuOrder") { c, view in
                view.menuOrder(menuOrder(c))
            }
        }
        r.modifier("buttonRepeatBehavior", .controls, notes: "`.enabled`: holding the button repeats its action.") { m in
            m.form("_:ButtonRepeatBehavior") { c, view in
                view.buttonRepeatBehavior(c.pick(0, ["enabled": ButtonRepeatBehavior.enabled, "disabled": .disabled]) ?? .automatic)
            }
        }
        r.modifier("buttonSizing", .controls, introduced: "26.0") { m in
            m.form("_:ButtonSizing") { c, view in
                if #available(iOS 26.0, macOS 26.0, *) {
                    AnyView(view.buttonSizing(c.pick(0, ["fitted": ButtonSizing.fitted, "flexible": .flexible]) ?? .automatic))
                } else { view }
            }
        }
        r.modifier("paletteSelectionEffect", .controls) { m in
            m.form("_:PaletteSelectionEffect") { c, view in
                if c.symbol(0) == "custom" { view.paletteSelectionEffect(.custom) }
                else if case .native(.implicit("symbolVariant", _))? = c[0] { view.paletteSelectionEffect(.symbolVariant(.fill)) }
                else { view.paletteSelectionEffect(.automatic) }
            }
        }
        r.modifier("help", .controls, notes: "Shown when a pointer hovers (iPad with a trackpad); nothing on touch.") { m in
            m.form("_:title") { c, view in view.help(c.string(0) ?? "") }
            m.form("_:title", receiver: "TabContent", introduced: "27.0") { _, view in view }
        }
        r.modifier("backgroundStyle", .controls) { m in
            m.form("_:ShapeStyle") { c, view in
                if let style = c.shapeStyle(0) { view.backgroundStyle(style) } else { view }
            }
        }
        r.modifier("labelIconToTitleSpacing", .controls, introduced: "26.0") { m in
            m.form("_:number") { c, view in
                if #available(iOS 26.0, macOS 26.0, *) { AnyView(view.labelIconToTitleSpacing(c.cg(0) ?? 8)) } else { view }
            }
        }
        r.modifier("labelReservedIconWidth", .controls, introduced: "26.0") { m in
            m.form("_:number") { c, view in
                if #available(iOS 26.0, macOS 26.0, *) { AnyView(view.labelReservedIconWidth(c.cg(0) ?? 0)) } else { view }
            }
        }
        r.modifier("sliderThumbVisibility", .controls, introduced: "26.0") { m in
            m.form("_:Visibility") { c, view in
                if #available(iOS 26.0, macOS 26.0, *) { AnyView(view.sliderThumbVisibility(KControlValues.visibility(c[0]))) } else { view }
            }
        }
        r.modifier("scrollEdgeEffectStyle", .controls, introduced: "26.0") { m in
            m.form("_:ScrollEdgeEffectStyle? for:Edge.Set") { c, view in
                if #available(iOS 26.0, macOS 26.0, *) {
                    AnyView(view.scrollEdgeEffectStyle(c.pick(0, ["hard": ScrollEdgeEffectStyle.hard, "soft": .soft, "automatic": .automatic]), for: c.edges("for")))
                } else { view }
            }
        }
        r.modifier("textInputBorderShape", .controls, introduced: "27.0") { m in
            m.form("_:TextInputBorderShape") { c, view in textInputBorderShape(c, view) }
        }
        r.modifier("textInputFormattingControlVisibility", .controls, introduced: "26.0",
                   notes: "Shows or hides the formatting controls of a `TextEditor` bound to an `AttributedString`.") { m in
            m.form("_:Visibility for:any") { c, view in formattingControls(c, view) }
        }
    }

    @MainActor static func menuOrder(_ c: KCall) -> MenuOrder {
        switch c.symbol(0) {
        case "fixed": return .fixed
        #if os(iOS)
        case "priority": return .priority
        #endif
        default: return .automatic
        }
    }

    @MainActor static func textInputBorderShape(_ c: KCall, _ view: AnyView) -> AnyView {
        #if os(iOS)
        if #available(iOS 27.0, *) {
            switch c.symbol(0) {
            case "capsule": return AnyView(view.textInputBorderShape(.capsule))
            case "roundedRectangle": return AnyView(view.textInputBorderShape(.roundedRectangle))
            default: return AnyView(view.textInputBorderShape(.automatic))
            }
        }
        #endif
        return view
    }

    @MainActor static func formattingControls(_ c: KCall, _ view: AnyView) -> AnyView {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            var placements: TextInputFormattingControlPlacement.Set = []
            let names: [String] = {
                if case .native(.implicit(let n, _))? = c["for"] { return [n] }
                return ((try? c.interp.sequence(c["for"] ?? .array([]))) ?? []).compactMap { if case .native(.implicit(let n, _)) = $0 { return n }; return nil }
            }()
            for n in names {
                switch n {
                case "inputAssistant": placements.insert(.inputAssistant)
                case "contextMenu": placements.insert(.contextMenu)
                default: placements = .all
                }
            }
            return AnyView(view.textInputFormattingControlVisibility(KControlValues.visibility(c[0]), for: placements.isEmpty ? .all : placements))
        }
        #endif
        return view
    }

    // MARK: Environment values

    static func controlEnvironment(_ r: KRegistry) {
        r.liveEnvironment("isEnabled", .controls, read: { env, _ in .bool(env.isEnabled) },
                          write: { view, v, _ in AnyView(view.environment(\.isEnabled, v.asBool ?? true)) })
        r.liveEnvironment("controlSize", .controls, read: { env, _ in
            let name = controlSizes.first { $0.value == env.controlSize }?.key ?? "regular"
            return .native(.implicit(name, []))
        }, write: { view, v, c in
            guard case .native(.implicit(let n, _)) = v, let size = controlSizes[n] else { return view }
            return AnyView(view.environment(\.controlSize, size))
        })
        r.liveEnvironment("buttonRepeatBehavior", .controls, read: { env, _ in
            .native(.implicit(env.buttonRepeatBehavior == .enabled ? "enabled" : (env.buttonRepeatBehavior == .disabled ? "disabled" : "automatic"), []))
        })
        r.liveEnvironment("menuIndicatorVisibility", .controls, read: { env, _ in KControlValues.visibilityValue(env.menuIndicatorVisibility) })
        r.liveEnvironment("labelsVisibility", .controls, read: { env, _ in
            if #available(iOS 18.0, macOS 15.0, *) { return KControlValues.visibilityValue(env.labelsVisibility) }
            return .native(.implicit("automatic", []))
        })
        r.liveEnvironment("labelIconToTitleSpacing", .controls, read: { env, _ in
            if #available(iOS 26.0, macOS 26.0, *) { return env.labelIconToTitleSpacing.map { .double(Double($0)) } ?? .nilValue }
            return .nilValue
        })
        r.liveEnvironment("labelReservedIconWidth", .controls, read: { env, _ in
            if #available(iOS 26.0, macOS 26.0, *) { return env.labelReservedIconWidth.map { .double(Double($0)) } ?? .nilValue }
            return .nilValue
        })
    }
}

/// `DateComponents` as Kiln holds them: a tuple of labelled values.
@MainActor
enum KDateComponents {
    static let fields: [(String, Calendar.Component)] = [("year", .year), ("month", .month), ("day", .day), ("hour", .hour), ("minute", .minute), ("second", .second)]

    static func native(_ v: KV) -> DateComponents? {
        guard case .tuple(let vals, let labels) = v else { return nil }
        var dc = DateComponents()
        for (i, l) in labels.enumerated() {
            guard let l, let n = vals[i].asInt else { continue }
            switch l {
            case "year": dc.year = n
            case "month": dc.month = n
            case "day": dc.day = n
            case "hour": dc.hour = n
            case "minute": dc.minute = n
            case "second": dc.second = n
            default: break
            }
        }
        return dc
    }

    static func kv(_ dc: DateComponents) -> KV {
        var vals: [KV] = [], labels: [String?] = []
        for (name, comp) in fields {
            if let n = dc.value(for: comp), n != NSDateComponentUndefined { vals.append(.int(n)); labels.append(name) }
        }
        return .tuple(vals, labels)
    }
}
