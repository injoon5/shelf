//
//  ControlStyles.swift
//  Bridges: control styles and states
//
//  `.buttonStyle(.borderedProminent)`, `.pickerStyle(.segmented)` … A style
//  is written as an implicit member (`.segmented`) or a type
//  (`SegmentedPickerStyle()`); both arrive as the member's name. An app's own
//  style struct (`.buttonStyle(PressableStyle())`) goes through
//  CustomStyles.swift.
//

import SwiftUI

extension KCall {
    /// A symbolic argument (`.compact`) looked up in a table of SwiftUI values.
    func pick<T>(_ ref: KArgRef, _ table: [String: T]) -> T? {
        guard let n = symbol(ref) else { return nil }
        return table[n] ?? table[String(n.split(separator: "(").first ?? "")]
    }
}

extension ControlsBridges {
    static func styles(_ r: KRegistry) {
        r.modifier("buttonStyle", .controls, notes: "Every built-in style, `.glass` and `.glassProminent` included, or your own `ButtonStyle` or `PrimitiveButtonStyle`.") { m in
            m.styles("ButtonStyle", ["borderedProminent", "bordered", "borderless", "plain", "automatic", "glass", "glassProminent"])
            m.form("_:ButtonStyle") { c, view in buttonStyle(c, view) }
        }
        r.modifier("buttonBorderShape", .controls) { m in
            m.form("_:ButtonBorderShape") { c, view in
                if let shape = buttonBorderShape(c[0]) { view.buttonBorderShape(shape) } else { view }
            }
        }
        r.modifier("pickerStyle", .controls) { m in
            m.styles("PickerStyle", ["segmented", "menu", "inline", "palette", "wheel", "navigationLink", "automatic", "tabs"])
            m.form("_:PickerStyle") { c, view in pickerStyle(c, view) }
        }
        r.modifier("toggleStyle", .controls, notes: "`.switch`, `.button`, or your own `ToggleStyle`.") { m in
            m.styles("ToggleStyle", ["switch", "button", "automatic"])
            m.form("_:ToggleStyle") { c, view in
                if let s = KStyles.custom(c) { applyCustom("toggleStyle", s, c, view) }
                else if c.symbol(0) == "button" { AnyView(view.toggleStyle(.button)) }
                else if c.symbol(0) == "switch" { AnyView(view.toggleStyle(.switch)) }
                else { view }
            }
        }
        r.modifier("textFieldStyle", .controls) { m in
            m.styles("TextFieldStyle", ["roundedBorder", "plain", "automatic", "bordered"])
            m.form("_:TextFieldStyle") { c, view in
                switch c.symbol(0) {
                case "roundedBorder": AnyView(view.textFieldStyle(.roundedBorder))
                case "plain": AnyView(view.textFieldStyle(.plain))
                case "bordered": borderedTextField(view)
                default: view
                }
            }
        }
        r.modifier("datePickerStyle", .controls) { m in
            m.styles("DatePickerStyle", ["graphical", "compact", "wheel", "automatic"])
            m.form("_:DatePickerStyle") { c, view in
                if let s = KStyles.custom(c) { applyCustom("datePickerStyle", s, c, view) } else {
                switch c.symbol(0) {
                case "graphical": AnyView(view.datePickerStyle(.graphical))
                case "compact": AnyView(view.datePickerStyle(.compact))
                #if os(iOS)
                case "wheel": AnyView(view.datePickerStyle(.wheel))
                #endif
                default: view
                }
                }
            }
        }
        r.modifier("labelStyle", .controls) { m in
            m.styles("LabelStyle", ["iconOnly", "titleOnly", "titleAndIcon", "automatic"])
            m.form("_:LabelStyle") { c, view in
                if let s = KStyles.custom(c) { applyCustom("labelStyle", s, c, view) } else {
                    switch c.symbol(0) {
                    case "iconOnly": AnyView(view.labelStyle(.iconOnly))
                    case "titleOnly": AnyView(view.labelStyle(.titleOnly))
                    case "titleAndIcon": AnyView(view.labelStyle(.titleAndIcon))
                    default: view
                    }
                }
            }
        }
        r.modifier("progressViewStyle", .controls) { m in
            m.styles("ProgressViewStyle", ["circular", "linear", "automatic"])
            m.form("_:ProgressViewStyle") { c, view in
                if let s = KStyles.custom(c) { applyCustom("progressViewStyle", s, c, view) }
                else if c.symbol(0) == "circular" { AnyView(view.progressViewStyle(.circular)) }
                else if c.symbol(0) == "linear" { AnyView(view.progressViewStyle(.linear)) }
                else { view }
            }
        }
        r.modifier("gaugeStyle", .controls) { m in
            m.styles("GaugeStyle", ["accessoryCircular", "accessoryCircularCapacity", "accessoryLinear", "accessoryLinearCapacity", "linearCapacity", "automatic"])
            m.form("_:GaugeStyle") { c, view in gaugeStyle(c, view) }
        }
        r.modifier("menuStyle", .controls) { m in
            m.styles("MenuStyle", ["automatic", "button", "borderlessButton"])
            m.form("_:MenuStyle") { c, view in menuStyle(c, view) }
        }
        r.modifier("controlGroupStyle", .controls) { m in
            m.styles("ControlGroupStyle", ["automatic", "compactMenu", "menu", "navigation", "palette"])
            m.form("_:ControlGroupStyle") { c, view in
                if let s = KStyles.custom(c) { applyCustom("controlGroupStyle", s, c, view) } else {
                    switch c.symbol(0) {
                    case "compactMenu": AnyView(view.controlGroupStyle(.compactMenu))
                    case "menu": AnyView(view.controlGroupStyle(.menu))
                    case "navigation": AnyView(view.controlGroupStyle(.navigation))
                    case "palette": AnyView(view.controlGroupStyle(.palette))
                    default: view
                    }
                }
            }
        }
        r.modifier("formStyle", .controls) { m in
            m.styles("FormStyle", ["automatic", "columns", "grouped"])
            m.form("_:FormStyle") { c, view in
                if let s = KStyles.custom(c) { applyCustom("formStyle", s, c, view) }
                else if c.symbol(0) == "grouped" { AnyView(view.formStyle(.grouped)) }
                else if c.symbol(0) == "columns" { AnyView(view.formStyle(.columns)) }
                else { view }
            }
        }
        for (name, owner) in [("groupBoxStyle", "GroupBoxStyle"), ("labeledContentStyle", "LabeledContentStyle"), ("disclosureGroupStyle", "DisclosureGroupStyle")] {
            r.modifier(name, .controls, notes: "`.automatic`, or your own `\(owner)`.") { m in
                m.styles(owner, ["automatic"])
                m.form("_:\(owner)") { c, view in
                    if let s = KStyles.custom(c) { applyCustom(name, s, c, view) } else { view }
                }
            }
        }
        r.modifier("textEditorStyle", .controls) { m in
            m.styles("TextEditorStyle", ["automatic", "plain"])
            m.form("_:TextEditorStyle") { c, view in
                if let s = KStyles.custom(c) { applyCustom("textEditorStyle", s, c, view) }
                else if c.symbol(0) == "plain" { AnyView(view.textEditorStyle(.plain)) }
                else { view }
            }
        }
        r.modifier("controlSize", .controls) { m in
            m.form("_:ControlSize") { c, view in
                if let size = c.pick(0, controlSizes) { view.controlSize(size) } else { view }
            }
        }
        r.modifier("disabled", .controls) { m in
            m.form("_:bool") { c, view in view.disabled(c.bool(0, default: true)) }
        }
    }

    static let controlSizes: [String: ControlSize] = ["mini": .mini, "small": .small, "regular": .regular, "large": .large, "extraLarge": .extraLarge]

    @MainActor static func buttonStyle(_ c: KCall, _ view: AnyView) -> AnyView {
        if let s = KStyles.custom(c) { return applyCustom("buttonStyle", s, c, view) }
        switch c.symbol(0) {
        case "borderedProminent": return AnyView(view.buttonStyle(.borderedProminent))
        case "bordered": return AnyView(view.buttonStyle(.bordered))
        case "borderless": return AnyView(view.buttonStyle(.borderless))
        case "plain": return AnyView(view.buttonStyle(.plain))
        case "glass":
            if #available(iOS 26.0, macOS 26.0, *) {
                if case .native(.implicit(_, let args))? = c[0], let g = args.first, let glass = glass(g) { return AnyView(view.buttonStyle(.glass(glass))) }
                return AnyView(view.buttonStyle(.glass))
            }
            return AnyView(view.buttonStyle(.bordered))
        case "glassProminent":
            if #available(iOS 26.0, macOS 26.0, *) { return AnyView(view.buttonStyle(.glassProminent)) }
            return AnyView(view.buttonStyle(.borderedProminent))
        default: return view
        }
    }

    /// `.glass(.clear)`, `.glass(.regular.tint(.blue))`.
    @available(iOS 26.0, macOS 26.0, *)
    @MainActor static func glass(_ v: KV) -> Glass? {
        guard case .native(.implicit(let n, let args)) = v else { return nil }
        var g: Glass = n.hasPrefix("clear") ? .clear : (n.hasPrefix("identity") ? .identity : .regular)
        if n.hasSuffix(".interactive") { g = g.interactive() }
        if n.hasSuffix(".tint"), let color = args.first.flatMap({ v -> Color? in if case .native(.color(let c)) = v { return c }; return nil }) { g = g.tint(color) }
        return g
    }

    @MainActor static func buttonBorderShape(_ v: KV?) -> ButtonBorderShape? {
        guard case .native(.implicit(let n, let args))? = v else { return nil }
        switch n {
        case "capsule": return .capsule
        case "circle": return .circle
        case "roundedRectangle": return args.first?.cg.map { .roundedRectangle(radius: $0) } ?? .roundedRectangle
        case "automatic": return .automatic
        default: return nil
        }
    }

    @MainActor static func pickerStyle(_ c: KCall, _ view: AnyView) -> AnyView {
        switch c.symbol(0) {
        case "segmented": return AnyView(view.pickerStyle(.segmented))
        case "menu": return AnyView(view.pickerStyle(.menu))
        case "inline": return AnyView(view.pickerStyle(.inline))
        case "palette": return AnyView(view.pickerStyle(.palette))
        #if os(iOS)
        case "wheel": return AnyView(view.pickerStyle(.wheel))
        case "navigationLink": return AnyView(view.pickerStyle(.navigationLink))
        #endif
        case "tabs":
            #if os(iOS)
            if #available(iOS 27.0, *) { return AnyView(view.pickerStyle(.tabs)) }
            #endif
            return AnyView(view.pickerStyle(.segmented))
        default: return view
        }
    }

    @MainActor static func menuStyle(_ c: KCall, _ view: AnyView) -> AnyView {
        if let s = KStyles.custom(c) { return applyCustom("menuStyle", s, c, view) }
        switch c.symbol(0) {
        case "button": return AnyView(view.menuStyle(.button))
        #if os(iOS)
        case "borderlessButton": return AnyView(view.menuStyle(.borderlessButton))
        #endif
        default: return view
        }
    }

    @MainActor static func borderedTextField(_ view: AnyView) -> AnyView {
        #if os(iOS)
        if #available(iOS 27.0, *) { return AnyView(view.textFieldStyle(.bordered)) }
        #endif
        return AnyView(view.textFieldStyle(.roundedBorder))
    }

    @MainActor static func gaugeStyle(_ c: KCall, _ view: AnyView) -> AnyView {
        if let s = KStyles.custom(c) { return applyCustom("gaugeStyle", s, c, view) }
        #if os(iOS)
        switch c.symbol(0) {
        case "accessoryCircular": return AnyView(view.gaugeStyle(.accessoryCircular))
        case "accessoryCircularCapacity": return AnyView(view.gaugeStyle(.accessoryCircularCapacity))
        case "accessoryLinear": return AnyView(view.gaugeStyle(.accessoryLinear))
        case "accessoryLinearCapacity": return AnyView(view.gaugeStyle(.accessoryLinearCapacity))
        case "linearCapacity": return AnyView(view.gaugeStyle(.linearCapacity))
        default: return view
        }
        #else
        return view
        #endif
    }
}

extension ControlsBridges {
    /// `.tag(_:)`: how a `Picker` or a `TabView` knows a row.
    static func tags(_ r: KRegistry) {
        r.modifier("tag", .controls, notes: "Read by `Picker` and `TabView`.") { m in
            m.form("_:any includeOptional:bool?") { c, view in view.tag(c[0] ?? .nilValue) }
        }
    }
}
