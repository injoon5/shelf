//
//  CustomStyles.swift
//  Bridges: an app's own control styles
//
//  `struct PressableStyle: ButtonStyle { func makeBody(configuration:) … }`
//  and `.buttonStyle(PressableStyle())`: a native style forwards SwiftUI's
//  `makeBody(configuration:)` to the app's, with the configuration as a
//  value whose `label`, `isPressed`, `isOn`… are SwiftUI's own. A view the
//  configuration holds (`configuration.label`) is shown as SwiftUI made it.
//
//  The styles whose requirements SwiftUI keeps private (`PickerStyle`,
//  `TextFieldStyle`, `ListStyle`, `TabViewStyle`…) can't be adopted by any
//  app, compiled or not; they're in won't-do.
//

import SwiftUI

/// A SwiftUI view a configuration hands the app (`configuration.label`).
class KNativeViewBox {
    let view: AnyView
    init(_ view: some View) { self.view = AnyView(view) }
}

/// A style's configuration: its views, values and the native value itself
/// (for `Toggle(configuration)`).
final class KStyleConfiguration {
    let kind: String
    let native: Any
    var values: [String: KV]
    init(_ kind: String, _ native: Any, _ values: [String: KV]) {
        self.kind = kind
        self.native = native
        self.values = values
    }
}

@MainActor
enum KStyles {
    /// The style protocols an app can adopt, with their configuration's members.
    static let protocols: [(name: String, members: [String])] = [
        ("ButtonStyle", ["label", "isPressed", "role"]),
        ("PrimitiveButtonStyle", ["label", "role", "trigger()"]),
        ("ToggleStyle", ["label", "isOn", "$isOn", "isMixed"]),
        ("LabelStyle", ["title", "icon"]),
        ("ProgressViewStyle", ["fractionCompleted", "label", "currentValueLabel"]),
        ("GaugeStyle", ["value", "label", "currentValueLabel", "minimumValueLabel", "maximumValueLabel"]),
        ("GroupBoxStyle", ["label", "content"]),
        ("LabeledContentStyle", ["label", "content"]),
        ("DisclosureGroupStyle", ["label", "content", "isExpanded", "$isExpanded"]),
        ("ControlGroupStyle", ["label", "content"]),
        ("FormStyle", ["content"]),
        ("MenuStyle", []),
        ("TextEditorStyle", []),
        ("NavigationSplitViewStyle", []),
        ("DatePickerStyle", ["label", "selection", "$selection", "minimumDate", "maximumDate"]),
    ]

    static func view(_ v: some View) -> KV {
        .view(.primitive("KilnNativeView", [.native(.object("NativeView", KRef(KNativeViewBox(v))))], [nil], line: 0))
    }

    static func config(_ kind: String, _ native: Any, _ values: [String: KV]) -> KV {
        .native(.object(kind + "Configuration", KRef(KStyleConfiguration(kind, native, values))))
    }

    /// The configuration an argument holds, if it's one (`Toggle(configuration)`).
    static func configuration(_ v: KV?, _ kind: String) -> KStyleConfiguration? {
        guard case .native(.object(_, let ref))? = v, let c = ref.value as? KStyleConfiguration, c.kind == kind else { return nil }
        return c
    }

    /// The app's `makeBody(configuration:)`, run with SwiftUI's configuration,
    /// its `@Environment` properties read where the style is shown.
    static func body(_ style: KStructValue, _ interp: KInterpreter, _ config: KV) -> AnyView {
        if interp.readsLiveEnvironment(style.type) {
            return AnyView(KLiveEnvironment { env in run(interp.withLiveEnvironment(style, env), interp, config) })
        }
        return run(style, interp, config)
    }

    private static func run(_ style: KStructValue, _ interp: KInterpreter, _ config: KV) -> AnyView {
        guard let make = style.type.method("makeBody") else {
            return AnyView(KErrorView(message: "\(style.type.name) has no makeBody(configuration:)"))
        }
        do {
            let ctx = KSelfContext(type: style.type, location: .box(KBox(.structV(style))))
            let v = try interp.entry {
                try interp.invoke(make, args: [config], labels: ["configuration"], selfContext: ctx, parent: interp.globalEnv)
            }
            return KRenderer(interp: interp).render(.group(KBuiltins.asViews(v, interp)))
        } catch {
            interp.report(error)
            return AnyView(KErrorView(message: interp.describeError(error)))
        }
    }

    /// The app's style, when a style modifier is given one rather than `.bordered`.
    static func custom(_ c: KCall) -> KStructValue? {
        if case .structV(let s)? = c[0], s.type.method("makeBody") != nil { return s }
        return nil
    }
}

// MARK: - The native styles

struct KButtonStyle: ButtonStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        KStyles.body(style, interp, KStyles.config("ButtonStyle", configuration, [
            "label": KStyles.view(configuration.label), "isPressed": .bool(configuration.isPressed),
            "role": KControlValues.role(configuration.role),
        ]))
    }
}

struct KPrimitiveButtonStyle: PrimitiveButtonStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        KStyles.body(style, interp, KStyles.config("PrimitiveButtonStyle", configuration, [
            "label": KStyles.view(configuration.label), "role": KControlValues.role(configuration.role),
        ]))
    }
}

struct KToggleStyle: ToggleStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.$isOn
        let binding = KBinding(get: { .bool(isOn.wrappedValue) }, set: { isOn.wrappedValue = $0.asBool ?? false })
        return KStyles.body(style, interp, KStyles.config("ToggleStyle", configuration, [
            "label": KStyles.view(configuration.label), "isOn": .binding(binding), "isMixed": .bool(configuration.isMixed),
        ]))
    }
}

struct KLabelStyle: LabelStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        KStyles.body(style, interp, KStyles.config("LabelStyle", configuration, [
            "title": KStyles.view(configuration.title), "icon": KStyles.view(configuration.icon),
        ]))
    }
}

struct KProgressViewStyle: ProgressViewStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        KStyles.body(style, interp, KStyles.config("ProgressViewStyle", configuration, [
            "fractionCompleted": configuration.fractionCompleted.map { .double($0) } ?? .nilValue,
            "label": configuration.label.map { KStyles.view($0) } ?? .nilValue,
            "currentValueLabel": configuration.currentValueLabel.map { KStyles.view($0) } ?? .nilValue,
        ]))
    }
}

struct KGaugeStyle: GaugeStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        KStyles.body(style, interp, KStyles.config("GaugeStyle", configuration, [
            "value": .double(configuration.value), "label": KStyles.view(configuration.label),
            "currentValueLabel": configuration.currentValueLabel.map { KStyles.view($0) } ?? .nilValue,
            "minimumValueLabel": configuration.minimumValueLabel.map { KStyles.view($0) } ?? .nilValue,
            "maximumValueLabel": configuration.maximumValueLabel.map { KStyles.view($0) } ?? .nilValue,
        ]))
    }
}

struct KGroupBoxStyle: GroupBoxStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        KStyles.body(style, interp, KStyles.config("GroupBoxStyle", configuration, [
            "label": KStyles.view(configuration.label), "content": KStyles.view(configuration.content),
        ]))
    }
}

struct KLabeledContentStyle: LabeledContentStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        KStyles.body(style, interp, KStyles.config("LabeledContentStyle", configuration, [
            "label": KStyles.view(configuration.label), "content": KStyles.view(configuration.content),
        ]))
    }
}

struct KDisclosureGroupStyle: DisclosureGroupStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        let expanded = configuration.$isExpanded
        let binding = KBinding(get: { .bool(expanded.wrappedValue) }, set: { expanded.wrappedValue = $0.asBool ?? false })
        return KStyles.body(style, interp, KStyles.config("DisclosureGroupStyle", configuration, [
            "label": KStyles.view(configuration.label), "content": KStyles.view(configuration.content), "isExpanded": .binding(binding),
        ]))
    }
}

struct KControlGroupStyle: ControlGroupStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        KStyles.body(style, interp, KStyles.config("ControlGroupStyle", configuration, [
            "label": KStyles.view(configuration.label), "content": KStyles.view(configuration.content),
        ]))
    }
}

struct KFormStyle: FormStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        KStyles.body(style, interp, KStyles.config("FormStyle", configuration, ["content": KStyles.view(configuration.content)]))
    }
}

struct KMenuStyle: MenuStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        KStyles.body(style, interp, KStyles.config("MenuStyle", configuration, [:]))
    }
}

struct KTextEditorStyle: TextEditorStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        KStyles.body(style, interp, KStyles.config("TextEditorStyle", configuration, [:]))
    }
}

struct KDatePickerStyle: DatePickerStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        let selection = configuration.$selection
        let binding = KBinding(get: { .native(.date(selection.wrappedValue)) }, set: { if case .native(.date(let d)) = $0 { selection.wrappedValue = d } })
        return KStyles.body(style, interp, KStyles.config("DatePickerStyle", configuration, [
            "label": KStyles.view(configuration.label), "selection": .binding(binding),
            "minimumDate": configuration.minimumDate.map { .native(.date($0)) } ?? .nilValue,
            "maximumDate": configuration.maximumDate.map { .native(.date($0)) } ?? .nilValue,
        ]))
    }
}

struct KNavigationSplitViewStyle: NavigationSplitViewStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        KStyles.body(style, interp, KStyles.config("NavigationSplitViewStyle", configuration, [:]))
    }
}

// MARK: - Registration

extension ControlsBridges {
    static func customStyles(_ r: KRegistry) {
        for p in KStyles.protocols {
            r.protocolBridge(p.name, .controls, requirements: ["makeBody(configuration:)"],
                             support: .full,
                             notes: p.name == "MenuStyle" ? "`makeBody(configuration:)` gets SwiftUI's configuration: show the menu with `Menu(configuration)`."
                                 : p.members.isEmpty ? "SwiftUI's configuration holds nothing to show, so `makeBody(configuration:)` replaces the view."
                                 : "`makeBody(configuration:)` gets SwiftUI's configuration: " + p.members.map { "`\($0)`" }.joined(separator: ", ") + ".")
            configurationType(r, p.name)
        }
        configurationType(r, "ArrangementViewStyle")
        // `configuration.label` and the other views SwiftUI hands a style.
        r.view("KilnNativeView", .controls) { v in
            v.engineOnly()
            v.form("_:any") { c in
                if case .native(.object(_, let ref))? = c[0], let box = ref.value as? KNativeViewBox { box.view } else { EmptyView() }
            }
        }
    }

    /// `configuration.label`, `configuration.isOn`… on a style's configuration.
    static func configurationType(_ r: KRegistry, _ kind: String) {
        r.type(kind + "Configuration", .controls, support: .full) { t in
            t.internal()
            t.anyProperty { c, name in
                guard case .native(.object(_, let ref)) = c.receiver, let conf = ref.value as? KStyleConfiguration else { return nil }
                // `configuration.$isOn`: the binding itself.
                if name.hasPrefix("$") { return conf.values[String(name.dropFirst())] }
                if case .binding(let b)? = conf.values[name] { return b.get() }
                return conf.values[name]
            }
            t.anySetter { c, name in
                guard case .native(.object(_, let ref)) = c.receiver, let conf = ref.value as? KStyleConfiguration,
                      case .binding(let b)? = conf.values[name] else { return false }
                b.set(c.first ?? .nilValue)
                return true
            }
            if kind == "PrimitiveButtonStyle" {
                t.method("trigger", "") { c in
                    if case .native(.object(_, let ref)) = c.receiver, let conf = ref.value as? KStyleConfiguration,
                       let native = conf.native as? PrimitiveButtonStyleConfiguration { native.trigger() }
                    return .void
                }
            }
        }
    }

    /// `.toggleStyle(CheckboxStyle())`: the app's style, natively.
    @MainActor static func applyCustom(_ name: String, _ s: KStructValue, _ c: KCall, _ view: AnyView) -> AnyView {
        let i = c.interp
        switch name {
        case "buttonStyle":
            if s.type.conformances.contains("PrimitiveButtonStyle") { return AnyView(view.buttonStyle(KPrimitiveButtonStyle(style: s, interp: i))) }
            return AnyView(view.buttonStyle(KButtonStyle(style: s, interp: i)))
        case "toggleStyle": return AnyView(view.toggleStyle(KToggleStyle(style: s, interp: i)))
        case "labelStyle": return AnyView(view.labelStyle(KLabelStyle(style: s, interp: i)))
        case "progressViewStyle": return AnyView(view.progressViewStyle(KProgressViewStyle(style: s, interp: i)))
        case "gaugeStyle": return AnyView(view.gaugeStyle(KGaugeStyle(style: s, interp: i)))
        case "groupBoxStyle": return AnyView(view.groupBoxStyle(KGroupBoxStyle(style: s, interp: i)))
        case "labeledContentStyle": return AnyView(view.labeledContentStyle(KLabeledContentStyle(style: s, interp: i)))
        case "disclosureGroupStyle": return AnyView(view.disclosureGroupStyle(KDisclosureGroupStyle(style: s, interp: i)))
        case "controlGroupStyle": return AnyView(view.controlGroupStyle(KControlGroupStyle(style: s, interp: i)))
        case "formStyle": return AnyView(view.formStyle(KFormStyle(style: s, interp: i)))
        case "menuStyle": return AnyView(view.menuStyle(KMenuStyle(style: s, interp: i)))
        case "textEditorStyle":
            if #available(iOS 17.0, macOS 14.0, *) { return AnyView(view.textEditorStyle(KTextEditorStyle(style: s, interp: i))) }
            return view
        case "datePickerStyle": return AnyView(view.datePickerStyle(KDatePickerStyle(style: s, interp: i)))
        case "navigationSplitViewStyle": return AnyView(view.navigationSplitViewStyle(KNavigationSplitViewStyle(style: s, interp: i)))
        default: return view
        }
    }
}

/// Small conversions the control bridges share.
@MainActor
enum KControlValues {
    static func role(_ role: ButtonRole?) -> KV {
        switch role {
        case .destructive?: return .native(.implicit("destructive", []))
        case .cancel?: return .native(.implicit("cancel", []))
        case nil: return .nilValue
        default: return .native(.implicit("confirm", []))
        }
    }

    static func buttonRole(_ v: KV?) -> ButtonRole? {
        guard case .native(.implicit(let n, _))? = v else { return nil }
        switch n {
        case "destructive": return .destructive
        case "cancel": return .cancel
        case "confirm": if #available(iOS 26.0, macOS 26.0, *) { return .confirm }; return nil
        case "close": if #available(iOS 26.0, macOS 26.0, *) { return .close }; return nil
        default: return nil
        }
    }

    static func visibility(_ v: KV?) -> Visibility {
        switch v.flatMap({ if case .native(.implicit(let n, _)) = $0 { return n }; return nil }) {
        case "visible"?: return .visible
        case "hidden"?: return .hidden
        default: return .automatic
        }
    }

    static func visibilityValue(_ v: Visibility) -> KV {
        switch v {
        case .visible: return .native(.implicit("visible", []))
        case .hidden: return .native(.implicit("hidden", []))
        default: return .native(.implicit("automatic", []))
        }
    }
}
