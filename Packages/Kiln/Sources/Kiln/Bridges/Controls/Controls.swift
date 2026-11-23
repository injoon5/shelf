//
//  Controls.swift
//  Bridges: buttons, toggles, pickers, sliders, steppers, text fields, menus
//
//  The controls are SwiftUI's own, bound to the app's state through
//  `c.binding(_:_:)`. Their styles are in ControlStyles.swift.
//

import SwiftUI

@objc(KilnBridges_Controls)
final class ControlsBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        buttons(r)
        toggles(r)
        values(r)
        textFields(r)
        pickers(r)
        display(r)
        styles(r)
        tags(r)
    }

    /// The first argument as a title when it's an unlabeled string.
    @MainActor static func stringTitle(_ c: KCall) -> String? {
        if case .string(let s)? = c.first, (c.labels.first ?? nil) == nil { return s }
        return nil
    }

    // MARK: Buttons

    static func buttons(_ r: KRegistry) {
        r.view("Button", .controls) { v in
            v.forms(["_:title action:action", "_:title systemImage:string action:action", "_:title role:ButtonRole? action:action",
                     "_:title systemImage:string role:ButtonRole? action:action", "_:title image:any action:action",
                     "action:action label:content", "role:ButtonRole? action:action label:content"]) { c in button(c) }
        }
        r.view("EditButton", .controls) { v in
            v.form("") { _ in
                #if os(iOS)
                EditButton()
                #else
                EmptyView()
                #endif
            }
        }
        r.view("Link", .controls) { v in
            v.form("_:title destination:any") { c in
                if let u = c.url("destination") { Link(c.title(0), destination: u) } else { Text(c.title(0)) }
            }
            v.form("destination:any label:content") { c in
                if let u = c.url("destination") { Link(destination: u) { c.content("label") } } else { c.content("label") }
            }
        }
        r.view("Menu", .controls) { v in
            v.forms(["_:title content:content", "_:title systemImage:string content:content", "_:title content:content primaryAction:action",
                     "content:content label:content", "content:content label:content primaryAction:action"]) { c in
                if let t = stringTitle(c) {
                    Menu(t) { c.r.renderContent(c.a.firstFunction) }
                } else {
                    Menu { c.r.renderContent(c.a.firstFunction) } label: { c.r.renderContent(c.a["label"]) }
                }
            }
        }
        r.view("ControlGroup", .controls) { v in
            v.forms(["content:content", "_:title content:content", "content:content label:content"]) { c in ControlGroup { c.content("content") } }
        }
    }

    @MainActor static func button(_ c: KCall) -> AnyView {
        let a = c.a, r = c.r
        let title = stringTitle(c)
        var actionFn: KV? = a["action"]
        var labelFn: KV? = a["label"]
        let unlabeledFns = zip(a.args, a.labels).filter { $0.1 == nil && r.isFunction($0.0) }.map(\.0)
        if actionFn == nil { actionFn = unlabeledFns.first }
        if labelFn == nil, title == nil, unlabeledFns.count > 1 || (a["action"] != nil && !unlabeledFns.isEmpty) {
            labelFn = a["action"] != nil ? unlabeledFns.first : unlabeledFns.dropFirst().first
        }
        var role: ButtonRole? = nil
        if case .native(.implicit(let n, _))? = a["role"] { role = n == "destructive" ? .destructive : (n == "cancel" ? .cancel : nil) }
        let run = r.action(actionFn)
        if let title {
            if let icon = a["systemImage"].flatMap({ r.string($0) }) {
                return AnyView(Button(role: role, action: run) { Label(title, systemImage: icon) })
            }
            return AnyView(Button(title, role: role, action: run))
        }
        if let lf = labelFn { return AnyView(Button(role: role, action: run) { r.renderContent(lf) }) }
        return AnyView(Button(role: role, action: run) { Text(r.string(a.first) ?? "Button") })
    }

    // MARK: Toggles

    static func toggles(_ r: KRegistry) {
        r.view("Toggle", .controls) { v in
            v.form("_:title isOn:binding") { c in Toggle(c.title(0), isOn: c.binding("isOn", Bool.self)) }
            v.form("_:title systemImage:string isOn:binding") { c in
                Toggle(isOn: c.binding("isOn", Bool.self)) { Label(c.title(0), systemImage: c.title("systemImage")) }
            }
            v.form("isOn:binding label:content") { c in Toggle(isOn: c.binding("isOn", Bool.self)) { c.content("label") } }
        }
    }

    // MARK: Sliders, steppers, gauges

    static func values(_ r: KRegistry) {
        r.view("Slider", .controls, support: .partial, notes: "Labels and `onEditingChanged` are accepted but not shown.") { v in
            v.forms(["value:binding in:any? step:number? onEditingChanged:closure?",
                     "value:binding in:any? step:number? label:content minimumValueLabel:content? maximumValueLabel:content? onEditingChanged:closure?"]) { c in
                let range = c.optional("in", ClosedRange<Double>.self) ?? 0...1
                if let step = c.double("step") {
                    Slider(value: c.binding("value", Double.self), in: range, step: step)
                } else {
                    Slider(value: c.binding("value", Double.self), in: range)
                }
            }
        }
        r.view("Stepper", .controls) { v in
            v.forms(["_:title value:binding in:any? step:number? onEditingChanged:closure?",
                     "value:binding in:any? step:number? label:content onEditingChanged:closure?",
                     "_:title onIncrement:action? onDecrement:action? onEditingChanged:closure?",
                     "onIncrement:action? onDecrement:action? label:content"]) { c in stepper(c) }
            // Not SwiftUI's, but models write it.
            v.form("_:title value:binding in:any? increment:number", notes: "`increment:` is read as `step:`.") { c in stepper(c) }
        }
        r.view("Gauge", .controls, support: .partial) { v in
            v.form("value:any in:any? label:content currentValueLabel:content? minimumValueLabel:content? maximumValueLabel:content?") { c in
                Gauge(value: c.double("value") ?? 0, in: c.r.range(c["in"]) ?? 0...1) { c.r.renderContent(c.a.lastFunction) }
            }
        }
        r.view("ProgressView", .controls, support: .partial) { v in
            v.forms(["", "_:title", "value:any total:any?", "_:title value:any total:any?",
                     "value:any total:any? label:content currentValueLabel:content?", "label:content"]) { c in
                let title = stringTitle(c)
                if let value = c.double("value") {
                    let total = c.double("total") ?? 1
                    if let title {
                        ProgressView(title, value: min(max(value, 0), total), total: total)
                    } else {
                        ProgressView(value: min(max(value, 0), total), total: total)
                    }
                } else if let title {
                    ProgressView(title)
                } else {
                    ProgressView()
                }
            }
        }
    }

    @MainActor static func stepper(_ c: KCall) -> AnyView {
        let a = c.a, r = c.r
        let title = stringTitle(c)
        if let inc = a["onIncrement"] {
            return AnyView(Stepper(title ?? "", onIncrement: r.action(inc), onDecrement: r.action(a["onDecrement"])))
        }
        let b = r.binding(a["value"]) ?? .constant(.int(0))
        let step = (a["step"] ?? a["increment"])?.asDouble ?? 1
        let isInt: Bool = { if case .int = b.get() { return true }; return false }()
        let range = r.range(a["in"])
        let label: AnyView = title.map { AnyView(Text($0)) } ?? r.renderContent(a.lastFunction)
        if isInt {
            let ib = Binding<Int>(get: { b.get().asInt ?? 0 }, set: { b.set(.int($0)) })
            if let range { return AnyView(Stepper(value: ib, in: Int(range.lowerBound)...Int(range.upperBound), step: Int(step)) { label }) }
            return AnyView(Stepper(value: ib, step: Int(step)) { label })
        }
        let db = r.doubleBinding(b)
        if let range { return AnyView(Stepper(value: db, in: range, step: step) { label }) }
        return AnyView(Stepper(value: db, step: step) { label })
    }

    // MARK: Text fields

    static func textFields(_ r: KRegistry) {
        r.view("TextField", .controls, support: .partial, notes: "`text:`, or `value:format:` with `.number`, `.currency(code:)` or `.percent`; `axis: .vertical` grows.") { v in
            v.forms(["_:title text:binding prompt:any? axis:Axis?", "_:title text:binding onEditingChanged:closure? onCommit:action?",
                     "_:title value:binding format:any prompt:any?", "_:title value:binding formatter:any"]) { c in textField(c, secure: false) }
        }
        r.view("SecureField", .controls) { v in
            v.forms(["_:title text:binding prompt:any?", "_:title text:binding onCommit:action"]) { c in textField(c, secure: true) }
        }
        r.view("TextEditor", .controls) { v in
            v.form("text:binding") { c in TextEditor(text: c.binding("text", String.self)) }
        }
    }

    @MainActor static func textField(_ c: KCall, secure: Bool) -> AnyView {
        let a = c.a, r = c.r
        let placeholder = r.string(a.first) ?? ""
        if let vb = r.binding(a["value"]) {
            let isInt: Bool = { if case .int = vb.get() { return true }; return false }()
            if isInt {
                let ib = Binding<Int>(get: { vb.get().asInt ?? 0 }, set: { vb.set(.int($0)) })
                return AnyView(TextField(placeholder, value: ib, format: .number))
            }
            let db = Binding<Double>(get: { vb.get().asDouble ?? 0 }, set: { vb.set(.double($0)) })
            if case .native(.format(let f))? = a["format"], case .currency(let code) = f.kind {
                return AnyView(TextField(placeholder, value: db, format: .currency(code: code)))
            }
            if case .native(.format(let f))? = a["format"], f.kind == .percent {
                return AnyView(TextField(placeholder, value: db, format: .percent))
            }
            return AnyView(TextField(placeholder, value: db, format: .number))
        }
        let text = c.binding("text", String.self)
        if secure { return AnyView(SecureField(placeholder, text: text)) }
        if c.symbol("axis") == "vertical" { return AnyView(TextField(placeholder, text: text, axis: .vertical)) }
        if let submit = a["onCommit"] { return AnyView(TextField(placeholder, text: text).onSubmit(r.action(submit))) }
        return AnyView(TextField(placeholder, text: text))
    }

    // MARK: Pickers

    static func pickers(_ r: KRegistry) {
        r.view("Picker", .controls, support: .partial, notes: "Rows are tagged with `.tag`, or by their `ForEach` id.") { v in
            v.forms(["_:title selection:binding content:content", "_:title systemImage:string selection:binding content:content",
                     "selection:binding content:content label:content", "selection:binding label:any content:content"]) { c in picker(c) }
        }
        r.view("DatePicker", .controls, support: .partial, notes: "`displayedComponents` `.date` and `.hourAndMinute`; an `in:` range isn't enforced.") { v in
            v.forms(["_:title selection:binding displayedComponents:any?", "_:title selection:binding in:any displayedComponents:any?",
                     "selection:binding displayedComponents:any? label:content", "selection:binding in:any displayedComponents:any? label:content"]) { c in
                datePicker(c)
            }
        }
        r.view("ColorPicker", .controls, support: .partial) { v in
            v.forms(["_:title selection:binding supportsOpacity:bool?", "selection:binding supportsOpacity:bool? label:content"]) { c in
                ColorPicker(c.r.string(c.first) ?? "", selection: c.binding("selection", Color.self))
            }
        }
    }

    @MainActor static func picker(_ c: KCall) -> AnyView {
        let a = c.a, r = c.r
        let b = r.binding(a["selection"]) ?? .constant(.nilValue)
        let rows = pickerRows(c, r.content(a.lastFunction ?? a["content"]))
        let sel = Binding<KV>(get: {
            let v = b.get()
            return rows.first(where: { $0.0 == v })?.0 ?? v
        }, set: { b.set($0) })
        let title = r.string(a.first.flatMap { if case .string = $0 { return $0 }; return nil }) ?? ""
        let items = ForEach(Array(rows.enumerated()), id: \.offset) { _, row in r.render(row.1).tag(row.0) }
        if let lf = a["label"] { return AnyView(Picker(selection: sel) { items } label: { r.renderContent(lf) }) }
        return AnyView(Picker(title, selection: sel) { items })
    }

    /// Picker rows with their tags: an explicit `.tag`, else the `ForEach` id.
    @MainActor static func pickerRows(_ c: KCall, _ views: [KView]) -> [(KV, KView)] {
        let r = c.r
        var rows: [(KV, KView)] = []
        for v in views.flatMap(\.flattened) {
            if v.primitiveName == "ForEach", case .primitive(_, let args, let labels, _) = v.kind {
                for row in r.forEachRows(KArgs(args: args, labels: labels)) {
                    for rv in row.views.flatMap(\.flattened) { rows.append((rv.modifier("tag")?.first ?? row.id, rv.removing("tag"))) }
                }
            } else {
                rows.append((v.modifier("tag")?.first ?? .string(r.plainText(v) ?? "\(rows.count)"), v.removing("tag")))
            }
        }
        return rows
    }

    @MainActor static func datePicker(_ c: KCall) -> AnyView {
        var comps: DatePickerComponents = [.date, .hourAndMinute]
        if let dc = c["displayedComponents"] {
            comps = []
            let names: [String] = {
                if case .native(.implicit(let n, _)) = dc { return [n] }
                if case .array(let items) = dc { return items.compactMap { if case .native(.implicit(let n, _)) = $0 { return n }; return nil } }
                return []
            }()
            if names.contains("date") { comps.insert(.date) }
            if names.contains("hourAndMinute") { comps.insert(.hourAndMinute) }
            if comps.isEmpty { comps = .date }
        }
        return AnyView(DatePicker(c.r.string(c.first) ?? "", selection: c.binding("selection", Date.self), displayedComponents: comps))
    }

    // MARK: Labels and content

    static func display(_ r: KRegistry) {
        r.view("Label", .controls) { v in
            v.form("_:title systemImage:string") { c in Label(c.title(0), systemImage: c.title("systemImage")) }
            v.form("_:title image:string") { c in Label(c.title(0), image: c.title("image")) }
            v.form("title:content icon:content") { c in Label { c.content("title") } icon: { c.content("icon") } }
        }
        r.view("ContentUnavailableView", .controls) { v in
            v.forms(["_:title systemImage:string description:any?", "_:title image:string description:any?"]) { c in
                let desc = c["description"].flatMap { v -> Text? in
                    if case .view(let t) = v { return c.r.text(t) }
                    return c.r.string(v).map { Text($0) }
                }
                ContentUnavailableView(c.title(0), systemImage: c.string("systemImage") ?? "tray", description: desc)
            }
            v.form("label:content description:content? actions:content?") { c in
                ContentUnavailableView { c.content("label") } description: { c.content("description") } actions: { c.content("actions") }
            }
        }
        r.view("LabeledContent", .controls) { v in
            v.forms(["_:title value:any", "_:title value:any format:any"]) { c in
                if let style = c["format"] {
                    LabeledContent(c.title(0), value: KFormatting.formatted(c["value"] ?? .void, style, c.interp))
                } else {
                    LabeledContent(c.title(0), value: c.string("value") ?? "")
                }
            }
            v.form("_:title content:content") { c in LabeledContent(c.title(0)) { c.content("content") } }
            v.form("content:content label:content") { c in LabeledContent { c.content("content") } label: { c.content("label") } }
        }
    }
}
