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
        customStyles(r)
        moreControls(r)
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
            // Inside a `PrimitiveButtonStyle`'s `makeBody`.
            v.form("_:any") { c in
                if let conf = KStyles.configuration(c[0], "PrimitiveButtonStyle"), let native = conf.native as? PrimitiveButtonStyleConfiguration { Button(native) }
            }
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
            v.forms(["_:title content:content", "_:title systemImage:string content:content", "_:title image:string content:content",
                     "_:title content:content primaryAction:action", "_:title systemImage:string content:content primaryAction:action",
                     "_:title image:string content:content primaryAction:action",
                     "content:content label:content", "content:content label:content primaryAction:action"]) { c in menu(c) }
            // Inside a `MenuStyle`'s `makeBody`: the menu as SwiftUI made it.
            v.form("_:any") { c in
                if let conf = KStyles.configuration(c[0], "MenuStyle"), let native = conf.native as? MenuStyleConfiguration { Menu(native) }
            }
        }
        r.view("ControlGroup", .controls) { v in
            v.forms(["content:content", "_:title content:content", "_:title systemImage:string content:content", "_:title image:string content:content",
                     "content:content label:content"]) { c in
                if let t = stringTitle(c) {
                    if let icon = c.string("systemImage") { ControlGroup(t, systemImage: icon) { c.content("content") } }
                    else { ControlGroup { c.content("content") } label: { Text(t) } }
                } else if c["label"] != nil {
                    ControlGroup { c.content("content") } label: { c.content("label") }
                } else {
                    ControlGroup { c.content("content") }
                }
            }
            v.form("_:any") { c in
                if let conf = KStyles.configuration(c[0], "ControlGroupStyle"), let native = conf.native as? ControlGroupStyleConfiguration { ControlGroup(native) }
            }
        }
    }

    @MainActor static func menu(_ c: KCall) -> AnyView {
        let primary = c["primaryAction"].map { c.r.action($0) }
        let items = c.content("content")
        let label: AnyView = {
            if let t = stringTitle(c) {
                if let icon = c.string("systemImage") { return AnyView(Label(t, systemImage: icon)) }
                if let image = c.string("image") { return AnyView(Label(t, image: image)) }
                return AnyView(Text(t))
            }
            return c.content("label")
        }()
        if let primary { return AnyView(Menu { items } label: { label } primaryAction: { primary() }) }
        return AnyView(Menu { items } label: { label })
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
        let role = KControlValues.buttonRole(a["role"])
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
            v.form("_:title image:string isOn:binding") { c in
                Toggle(isOn: c.binding("isOn", Bool.self)) { Label(c.title(0), image: c.title("image")) }
            }
            // Inside a `ToggleStyle`'s `makeBody`: the toggle as SwiftUI made it.
            v.form("_:any") { c in
                if let conf = KStyles.configuration(c[0], "ToggleStyle"), let native = conf.native as? ToggleStyleConfiguration { Toggle(native) }
            }
        }
    }

    // MARK: Sliders, steppers, gauges

    static func values(_ r: KRegistry) {
        r.view("Slider", .controls, notes: "Labels, `step:`, `neutralValue:`, `enabledBounds:`, and tick marks (`ticks: { SliderTick(0.5) }`, iOS 26).") { v in
            v.forms(["value:binding in:any? step:number? onEditingChanged:closure?",
                     "value:binding in:any? step:number? label:content minimumValueLabel:content? maximumValueLabel:content? onEditingChanged:closure?",
                     "value:binding in:any? step:number? onEditingChanged:closure? label:content",
                     "value:binding in:any? step:number? onEditingChanged:closure? minimumValueLabel:content maximumValueLabel:content label:content",
                     "value:binding in:any? step:number? neutralValue:number? enabledBounds:any? label:content currentValueLabel:content? minimumValueLabel:content? maximumValueLabel:content? ticks:content onEditingChanged:closure?",
                     "value:binding in:any? step:number? neutralValue:number? enabledBounds:any? label:content currentValueLabel:content? minimumValueLabel:content? maximumValueLabel:content? tick:closure? onEditingChanged:closure?"]) { c in
                slider(c)
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
        r.view("Gauge", .controls) { v in
            v.forms(["value:any in:any? label:content", "value:any in:any? label:content currentValueLabel:content",
                     "value:any in:any? label:content currentValueLabel:content minimumValueLabel:content maximumValueLabel:content",
                     "value:any in:any? label:content currentValueLabel:content? markedValueLabels:content",
                     "value:any in:any? label:content currentValueLabel:content? minimumValueLabel:content? maximumValueLabel:content? markedValueLabels:content?"]) { c in
                gauge(c)
            }
        }
        r.view("ProgressView", .controls, notes: "Indeterminate, `value:total:`, `timerInterval:countsDown:`, or your own `ProgressViewStyle`.") { v in
            v.forms(["", "_:title", "value:any total:any?", "_:title value:any total:any?",
                     "value:any total:any? label:content currentValueLabel:content?", "label:content",
                     "timerInterval:any countsDown:bool?", "timerInterval:any countsDown:bool? label:content currentValueLabel:content?"]) { c in
                progressView(c)
            }
        }
    }

    @MainActor static func slider(_ c: KCall) -> AnyView {
        let range = c.optional("in", ClosedRange<Double>.self) ?? 0...1
        let value = c.binding("value", Double.self)
        let step = c.double("step")
        let edit: (Bool) -> Void = { [interp = c.interp] editing in
            if case .function(let f)? = c["onEditingChanged"] { interp.perform(f, [.bool(editing)]) }
        }
        let label = c["label"].map { c.r.renderContent($0) } ?? AnyView(EmptyView())
        let minLabel = c["minimumValueLabel"].map { c.r.renderContent($0) } ?? AnyView(EmptyView())
        let maxLabel = c["maximumValueLabel"].map { c.r.renderContent($0) } ?? AnyView(EmptyView())
        if #available(iOS 26.0, macOS 26.0, *), c["ticks"] != nil || c["tick"] != nil || c["neutralValue"] != nil || c["enabledBounds"] != nil || c["currentValueLabel"] != nil {
            let marks = sliderTicks(c, range: range, step: step)
            let current = c["currentValueLabel"].map { c.r.renderContent($0) } ?? AnyView(EmptyView())
            let enabled = c.optional("enabledBounds", ClosedRange<Double>.self)
            return AnyView(Slider(value: value, in: range, neutralValue: c.double("neutralValue"), enabledBounds: enabled,
                                  label: { label }, currentValueLabel: { current }, minimumValueLabel: { minLabel }, maximumValueLabel: { maxLabel },
                                  ticks: { SliderTickContentForEach(marks.map(\.value), id: \.self) { v in SliderTick(v) { marks.first { $0.value == v }?.label ?? AnyView(EmptyView()) } } },
                                  onEditingChanged: edit))
        }
        if let step {
            return AnyView(Slider(value: value, in: range, step: step, label: { label }, minimumValueLabel: { minLabel }, maximumValueLabel: { maxLabel }, onEditingChanged: edit))
        }
        return AnyView(Slider(value: value, in: range, label: { label }, minimumValueLabel: { minLabel }, maximumValueLabel: { maxLabel }, onEditingChanged: edit))
    }

    struct SliderMark { let value: Double; let label: AnyView? }

    /// `ticks: { SliderTick(0); SliderTickContentForEach(stops, id: \.self) { SliderTick($0) } }`, or `tick: { v in … }` per step.
    @MainActor static func sliderTicks(_ c: KCall, range: ClosedRange<Double>, step: Double?) -> [SliderMark] {
        var marks: [SliderMark] = []
        func add(_ v: KView) {
            guard case .primitive(let n, let args, let labels, _)? = c.r.rootPrimitive(v) else { return }
            let a = KArgs(args: args, labels: labels)
            if n == "SliderTick" {
                let numbers = args.enumerated().filter { labels[$0.offset] == nil && $0.element.asDouble != nil && $0.element.asString == nil }
                guard let value = numbers.last?.element.asDouble else { return }
                var label: AnyView? = nil
                if case .string(let t)? = a.first { label = AnyView(Text(t)) }
                if let fn = a["label"] { label = c.r.renderContent(fn) }
                marks.append(SliderMark(value: value, label: label))
            } else if n == "SliderTickContentForEach" {
                for row in c.r.forEachRows(a) { row.views.flatMap(\.flattened).forEach(add) }
            }
        }
        if let fn = c["ticks"] { c.r.content(fn).flatMap(\.flattened).forEach(add) }
        if case .function(let f)? = c["tick"] {
            let by = step ?? (range.upperBound - range.lowerBound) / 10
            var v = range.lowerBound
            while v <= range.upperBound + by / 2, by > 0, marks.count < 200 {
                if let out = try? c.interp.entry({ try c.interp.call(f, [.double(v)], [nil]) }) {
                    KBuiltins.asViews(out, c.interp).forEach(add)
                }
                v += by
            }
        }
        return marks
    }

    @MainActor static func gauge(_ c: KCall) -> AnyView {
        let range = c.r.range(c["in"]) ?? 0...1
        let value = min(max(c.double("value") ?? 0, range.lowerBound), range.upperBound)
        let label = c.content("label")
        let current = c["currentValueLabel"].map { c.r.renderContent($0) }
        let lo = c["minimumValueLabel"].map { c.r.renderContent($0) }, hi = c["maximumValueLabel"].map { c.r.renderContent($0) }
        if let lo, let hi {
            return AnyView(Gauge(value: value, in: range) { label } currentValueLabel: { current ?? AnyView(EmptyView()) } minimumValueLabel: { lo } maximumValueLabel: { hi })
        }
        if let current { return AnyView(Gauge(value: value, in: range) { label } currentValueLabel: { current }) }
        return AnyView(Gauge(value: value, in: range) { label })
    }

    @MainActor static func progressView(_ c: KCall) -> AnyView {
        if let conf = KStyles.configuration(c[0], "ProgressViewStyle"), let native = conf.native as? ProgressViewStyleConfiguration {
            return AnyView(ProgressView(native))
        }
        let title = stringTitle(c)
        if let interval = c["timerInterval"], let range = dateRange(interval) {
            let down = c.bool("countsDown", default: true)
            if let fn = c["label"] {
                let current = c["currentValueLabel"].map { c.r.renderContent($0) }
                return AnyView(ProgressView(timerInterval: range, countsDown: down) { c.r.renderContent(fn) } currentValueLabel: { current ?? AnyView(EmptyView()) })
            }
            return AnyView(ProgressView(timerInterval: range, countsDown: down))
        }
        if let value = c.double("value") {
            let total = c.double("total") ?? 1
            let v = min(max(value, 0), total)
            if let fn = c["label"] {
                let current = c["currentValueLabel"].map { c.r.renderContent($0) }
                return AnyView(ProgressView(value: v, total: total) { c.r.renderContent(fn) } currentValueLabel: { current ?? AnyView(EmptyView()) })
            }
            if let title { return AnyView(ProgressView(title, value: v, total: total)) }
            return AnyView(ProgressView(value: v, total: total))
        }
        if let fn = c["label"] { return AnyView(ProgressView { c.r.renderContent(fn) }) }
        if let title { return AnyView(ProgressView(title)) }
        return AnyView(ProgressView())
    }

    /// `start...end` of dates.
    @MainActor static func dateRange(_ v: KV) -> ClosedRange<Date>? {
        if case .range(.native(.date(let a)), .native(.date(let b)), _) = v, a <= b { return a...b }
        return nil
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
                     "_:title text:binding selection:binding prompt:any? axis:Axis?",
                     "_:title value:binding format:any prompt:any?", "_:title value:binding formatter:any prompt:any?",
                     "_:title value:binding formatter:any onEditingChanged:closure? onCommit:action?",
                     "text:binding prompt:any? axis:Axis? label:content", "text:binding selection:binding prompt:any? axis:Axis? label:content",
                     "value:binding format:any prompt:any? label:content"]) { c in textField(c, secure: false) }
        }
        r.view("SecureField", .controls) { v in
            v.forms(["_:title text:binding prompt:any?", "_:title text:binding onCommit:action", "text:binding prompt:any? label:content"]) { c in textField(c, secure: true) }
        }
        r.view("TextEditor", .controls, support: .partial, notes: "`selection:` isn't kept.") { v in
            v.forms(["text:binding", "text:binding selection:binding"]) { c in textEditor(c) }
        }
    }

    @MainActor static func textEditor(_ c: KCall) -> AnyView {
        if let b = c.kbinding("text"), case .native(.object("AttributedString", _)) = b.get() {
            if #available(iOS 26.0, macOS 26.0, *) {
                let text = Binding<AttributedString>(get: { KAttributed.value(b.get()) ?? AttributedString() }, set: { b.set(KAttributed.kv($0)) })
                return AnyView(TextEditor(text: text))
            }
            let plain = Binding<String>(get: { String((KAttributed.value(b.get()) ?? AttributedString()).characters) },
                                        set: { b.set(KAttributed.kv(AttributedString($0))) })
            return AnyView(TextEditor(text: plain))
        }
        return AnyView(TextEditor(text: c.binding("text", String.self)))
    }

    @MainActor static func textField(_ c: KCall, secure: Bool) -> AnyView {
        let a = c.a, r = c.r
        let placeholder = stringTitle(c) ?? ""
        let prompt: Text? = c["prompt"].flatMap { v -> Text? in
            if case .view(let t) = v { return r.text(t) }
            return r.string(v).map { Text($0) }
        }
        let label: AnyView = c["label"].map { r.renderContent($0) } ?? AnyView(Text(placeholder))
        if let vb = r.binding(a["value"]) {
            let isInt: Bool = { if case .int = vb.get() { return true }; return false }()
            if isInt {
                let ib = Binding<Int>(get: { vb.get().asInt ?? 0 }, set: { vb.set(.int($0)) })
                return AnyView(TextField(value: ib, format: .number, prompt: prompt) { label })
            }
            let db = Binding<Double>(get: { vb.get().asDouble ?? 0 }, set: { vb.set(.double($0)) })
            if case .native(.format(let f))? = a["format"], case .currency(let code) = f.kind {
                return AnyView(TextField(value: db, format: .currency(code: code), prompt: prompt) { label })
            }
            if case .native(.format(let f))? = a["format"], f.kind == .percent {
                return AnyView(TextField(value: db, format: .percent, prompt: prompt) { label })
            }
            return AnyView(TextField(value: db, format: .number, prompt: prompt) { label })
        }
        let text = c.binding("text", String.self)
        if secure { return AnyView(SecureField(text: text, prompt: prompt) { label }) }
        let editing: ((Bool) -> Void)? = c["onEditingChanged"].flatMap { f -> ((Bool) -> Void)? in
            guard case .function(let fn) = f else { return nil }
            return { [interp = c.interp] e in interp.perform(fn, [.bool(e)]) }
        }
        if let editing {
            return AnyView(TextField(placeholder, text: text, onEditingChanged: editing, onCommit: r.action(a["onCommit"])))
        }
        if c.symbol("axis") == "vertical" { return AnyView(TextField(text: text, prompt: prompt, axis: .vertical) { label }) }
        if let submit = a["onCommit"] { return AnyView(TextField(text: text, prompt: prompt) { label }.onSubmit(r.action(submit))) }
        return AnyView(TextField(text: text, prompt: prompt) { label })
    }

    // MARK: Pickers

    static func pickers(_ r: KRegistry) {
        r.view("Picker", .controls, support: .partial, notes: "Rows are tagged with `.tag`, or by their `ForEach` id.") { v in
            v.forms(["_:title selection:binding content:content", "_:title systemImage:string selection:binding content:content",
                     "selection:binding content:content label:content", "selection:binding label:any content:content"]) { c in picker(c) }
        }
        r.view("DatePicker", .controls, notes: "`displayedComponents` `.date`, `.hourAndMinute` or both, with an `in:` range (`date...`, `...date` or `a...b`); every style, `.graphical` included.") { v in
            v.forms(["_:title selection:binding displayedComponents:any?", "_:title selection:binding in:any displayedComponents:any?",
                     "selection:binding displayedComponents:any? label:content", "selection:binding in:any displayedComponents:any? label:content"]) { c in
                datePicker(c)
            }
        }
        r.view("MultiDatePicker", .controls, notes: "`selection` is a `Set<DateComponents>`; read `.year`, `.month` and `.day` from each.") { v in
            v.forms(["_:title selection:binding", "_:title selection:binding in:any", "selection:binding label:content", "selection:binding in:any label:content"]) { c in
                multiDatePicker(c)
            }
        }
        r.view("ColorPicker", .controls) { v in
            v.forms(["_:title selection:binding supportsOpacity:bool?", "selection:binding supportsOpacity:bool? label:content"]) { c in
                if let fn = c["label"] {
                    ColorPicker(selection: c.binding("selection", Color.self), supportsOpacity: c.bool("supportsOpacity", default: true)) { c.r.renderContent(fn) }
                } else {
                    ColorPicker(stringTitle(c) ?? "", selection: c.binding("selection", Color.self), supportsOpacity: c.bool("supportsOpacity", default: true))
                }
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
                if case .set(let items) = dc { return items.compactMap { if case .native(.implicit(let n, _)) = $0 { return n }; return nil } }
                return []
            }()
            if names.contains("date") { comps.insert(.date) }
            if names.contains("hourAndMinute") { comps.insert(.hourAndMinute) }
            if comps.isEmpty { comps = .date }
        }
        let selection = c.binding("selection", Date.self)
        let label: AnyView = c["label"].map { c.r.renderContent($0) } ?? AnyView(Text(stringTitle(c) ?? ""))
        switch c["in"] {
        case .range(.native(.date(let lo)), .native(.date(let hi)), _)? where lo <= hi:
            return AnyView(DatePicker(selection: selection, in: lo...hi, displayedComponents: comps) { label })
        case .range(.native(.date(let lo)), .nilValue, _)?:
            return AnyView(DatePicker(selection: selection, in: lo..., displayedComponents: comps) { label })
        case .range(.nilValue, .native(.date(let hi)), _)?:
            return AnyView(DatePicker(selection: selection, in: ...hi, displayedComponents: comps) { label })
        default:
            return AnyView(DatePicker(selection: selection, displayedComponents: comps) { label })
        }
    }

    @MainActor static func multiDatePicker(_ c: KCall) -> AnyView {
        #if os(iOS) || os(visionOS)
        let b = c.kbinding("selection") ?? .constant(.set([]))
        let cal = Calendar.current
        let selection = Binding<Set<DateComponents>>(get: {
            Set(((try? c.interp.sequence(b.get())) ?? []).compactMap { KDateComponents.native($0) }.map { cal.dateComponents([.calendar, .era, .year, .month, .day], from: cal.date(from: $0) ?? Date()) })
        }, set: { new in
            b.set(.set(Set(new.map { KDateComponents.kv($0) })))
        })
        let label: AnyView = c["label"].map { c.r.renderContent($0) } ?? AnyView(Text(stringTitle(c) ?? ""))
        switch c["in"] {
        case .range(.native(.date(let lo)), .native(.date(let hi)), _)? where lo < hi:
            return AnyView(MultiDatePicker(selection: selection, in: lo..<hi) { label })
        case .range(.native(.date(let lo)), .nilValue, _)?:
            return AnyView(MultiDatePicker(selection: selection, in: lo...) { label })
        case .range(.nilValue, .native(.date(let hi)), _)?:
            return AnyView(MultiDatePicker(selection: selection, in: ..<hi) { label })
        default:
            return AnyView(MultiDatePicker(selection: selection) { label })
        }
        #else
        return AnyView(EmptyView())
        #endif
    }

    // MARK: Labels and content

    static func display(_ r: KRegistry) {
        r.view("Label", .controls) { v in
            v.form("_:title systemImage:string") { c in Label(c.title(0), systemImage: c.title("systemImage")) }
            v.form("_:title image:string") { c in Label(c.title(0), image: c.title("image")) }
            v.form("title:content icon:content") { c in Label { c.content("title") } icon: { c.content("icon") } }
            // Inside a `LabelStyle`'s `makeBody`.
            v.form("_:any") { c in
                if let conf = KStyles.configuration(c[0], "LabelStyle"), let native = conf.native as? LabelStyleConfiguration { Label(native) }
            }
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
            // Inside a `LabeledContentStyle`'s `makeBody`.
            v.form("_:any") { c in
                if let conf = KStyles.configuration(c[0], "LabeledContentStyle"), let native = conf.native as? LabeledContentStyleConfiguration { LabeledContent(native) }
            }
        }
    }
}
