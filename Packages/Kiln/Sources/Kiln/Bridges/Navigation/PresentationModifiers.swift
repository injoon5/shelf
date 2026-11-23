//
//  PresentationModifiers.swift
//  Bridges: how a sheet is presented (detents, sizing, background,
//  interaction), the inspector, old action sheets, dialog extras, the status
//  bar, and `\.isPresented` and `\.editMode`
//

import SwiftUI

extension NavigationBridges {
    static func presentationModifiers(_ r: KRegistry) {
        r.type("PresentationDetent", .navigation, support: .full) { t in
            t.membersInManifest = true
            t.staticProperty("medium") { _ in .native(.implicit("medium", [])) }
            t.staticProperty("large") { _ in .native(.implicit("large", [])) }
            t.staticMethod("fraction", "_:number") { c in .native(.implicit("fraction", [c[0] ?? .double(0.5)])) }
            t.staticMethod("height", "_:number") { c in .native(.implicit("height", [c[0] ?? .double(300)])) }
        }
        r.type("PresentationSizing", .navigation, support: .full, introduced: "18.0") { t in
            t.membersInManifest = true
            for name in ["automatic", "fitted", "form", "page"] { t.staticProperty(name) { _ in .native(.implicit(name, [])) } }
        }
        r.modifier("presentationDetents", .navigation, notes: "`.medium`, `.large`, `.fraction(_:)`, `.height(_:)`; `selection:` follows the one shown.") { m in
            m.form("_:any selection:binding?") { c, view in
                if let b = c.kbinding("selection") {
                    AnyView(view.presentationDetents(detents(c[0]), selection: Binding(get: { detent(b.get()) ?? .large }, set: { b.set(detentValue($0)) })))
                } else {
                    AnyView(view.presentationDetents(detents(c[0])))
                }
            }
        }
        r.modifier("presentationDragIndicator", .navigation) { m in
            m.form("_:Visibility") { c, view in view.presentationDragIndicator(KControlValues.visibility(c[0])) }
        }
        r.modifier("presentationCornerRadius", .navigation) { m in
            m.form("_:number?") { c, view in view.presentationCornerRadius(c.cg(0)) }
        }
        r.modifier("interactiveDismissDisabled", .navigation) { m in
            m.form("_:bool?") { c, view in view.interactiveDismissDisabled(c.bool(0, default: true)) }
        }
        r.modifier("presentationBackground", .navigation) { m in
            m.form("_:ShapeStyle") { c, view in
                if let style = c.shapeStyle(0) { view.presentationBackground(style) } else { view }
            }
            m.form("alignment:Alignment? content:content") { c, view in
                let content = c.content("content")
                view.presentationBackground(alignment: c.alignment("alignment")) { content }
            }
        }
        r.modifier("presentationBackgroundInteraction", .navigation, notes: "`.enabled`, `.enabled(upThrough: .medium)`, `.disabled`.") { m in
            m.form("_:any") { c, view in
                switch c[0] {
                case .native(.implicit("enabled", let args))? where !args.isEmpty:
                    view.presentationBackgroundInteraction(.enabled(upThrough: detent(args.first) ?? .medium))
                case .native(.implicit("enabled", _))?: view.presentationBackgroundInteraction(.enabled)
                case .native(.implicit("disabled", _))?: view.presentationBackgroundInteraction(.disabled)
                default: view.presentationBackgroundInteraction(.automatic)
                }
            }
        }
        r.modifier("presentationCompactAdaptation", .navigation, notes: "`.popover` keeps a popover a popover on iPhone; `.sheet`, `.fullScreenCover`, `.none`.") { m in
            m.form("_:any") { c, view in view.presentationCompactAdaptation(adaptation(c[0])) }
            m.form("horizontal:any vertical:any") { c, view in
                view.presentationCompactAdaptation(horizontal: adaptation(c["horizontal"]), vertical: adaptation(c["vertical"]))
            }
        }
        r.modifier("presentationContentInteraction", .navigation) { m in
            m.form("_:any") { c, view in
                view.presentationContentInteraction(c.symbol(0) == "scrolls" ? .scrolls : (c.symbol(0) == "resizes" ? .resizes : .automatic))
            }
        }
        r.modifier("presentationSizing", .navigation, introduced: "18.0", notes: "`.form`, `.page`, `.fitted`: how big a sheet is on iPad.") { m in
            m.form("_:any") { c, view in
                if #available(iOS 18.0, macOS 15.0, *) {
                    switch c.symbol(0) {
                    case "form": AnyView(view.presentationSizing(.form))
                    case "page": AnyView(view.presentationSizing(.page))
                    case "fitted": AnyView(view.presentationSizing(.fitted))
                    default: AnyView(view.presentationSizing(.automatic))
                    }
                } else { view }
            }
        }
        r.modifier("presentationPlacement", .navigation, introduced: "27.0") { m in
            m.form("_:any") { c, view in
                #if os(iOS)
                if #available(iOS 27.0, *) {
                    AnyView(view.presentationPlacement(c.pick(0, ["center": PresentationPlacement.center, "leading": .leading, "trailing": .trailing]) ?? .automatic))
                } else { view }
                #else
                view
                #endif
            }
        }
        r.modifier("inspector", .navigation, notes: "A trailing column on iPad; a sheet on iPhone.") { m in
            m.form("isPresented:binding content:content") { c, view in
                if let b = c.kbinding("isPresented") {
                    let r = c.r, fn = c["content"]
                    AnyView(view.inspector(isPresented: r.boolBinding(b)) { KLazyView { r.renderContent(fn) } })
                } else { view }
            }
        }
        r.modifier("inspectorColumnWidth", .navigation) { m in
            m.form("_:number") { c, view in view.inspectorColumnWidth(c.cg(0) ?? 320) }
            m.form("min:number? ideal:number max:number?") { c, view in
                view.inspectorColumnWidth(min: c.cg("min"), ideal: c.cg("ideal") ?? 320, max: c.cg("max"))
            }
        }
        // The old API: `.actionSheet(isPresented:) { ActionSheet(title:message:buttons:) }`.
        r.type("ActionSheet", .navigation, notes: "Shown as a `.confirmationDialog`.") { t in
            t.initializer("title:any message:any? buttons:any?") { c in .tuple(c.args, c.labels) }
        }
        r.modifier("actionSheet", .navigation, notes: "Old; shown as a `confirmationDialog`.") { m in
            m.forms(["isPresented:binding content:closure", "item:binding content:closure"]) { c, view in actionSheet(c, view) }
        }
        r.modifier("dialogIcon", .navigation) { m in
            m.form("_:any?") { c, view in
                #if os(iOS)
                if #available(iOS 17.0, *) { AnyView(view.dialogIcon(image(c[0]))) } else { view }
                #else
                view
                #endif
            }
        }
        r.modifier("dialogSuppressionToggle", .navigation, notes: "macOS shows it in a dialog; on iPhone it shows nothing.") { m in
            m.forms(["_:title isSuppressed:binding", "isSuppressed:binding"]) { c, view in
                if let b = c.kbinding("isSuppressed") {
                    if let t = c.string(0) { AnyView(view.dialogSuppressionToggle(t, isSuppressed: c.r.boolBinding(b))) }
                    else { AnyView(view.dialogSuppressionToggle(isSuppressed: c.r.boolBinding(b))) }
                } else { view }
            }
        }
        r.modifier("dismissalConfirmationDialog", .navigation, introduced: "27.0", notes: "Asks before a sheet is swiped or cancelled away, when `shouldPresent` is true.") { m in
            m.forms(["_:title shouldPresent:bool actions:content", "_:title shouldPresent:bool actions:content message:content"]) { c, view in
                dismissalDialog(c, view)
            }
        }
        r.modifier("menuActionDismissBehavior", .navigation) { m in
            m.form("_:any") { c, view in
                #if os(iOS)
                view.menuActionDismissBehavior(c.symbol(0) == "disabled" ? .disabled : (c.symbol(0) == "enabled" ? .enabled : .automatic))
                #else
                view
                #endif
            }
        }
        r.modifier("renameAction", .navigation, notes: "What a `RenameButton` runs: a closure, or a focus binding to set.") { m in
            m.form("_:any") { c, view in
                if case .function(let f)? = c[0] {
                    let interp = c.interp
                    view.renameAction { interp.perform(f) }
                } else if let b = c.kbinding(0) {
                    view.renameAction { b.set(.bool(true)) }
                } else { view }
            }
            m.probe { _, _ in [] }
        }
        r.modifier("statusBarHidden", .navigation, notes: "Hides the status bar while the app's card is open.") { m in
            m.form("_:bool?") { c, view in statusBarHidden(c.bool(0, default: true), view) }
        }
        r.modifier("statusBar", .navigation, notes: "Old; `.statusBarHidden(_:)`.") { m in
            m.form("hidden:bool") { c, view in statusBarHidden(c.bool("hidden", default: true), view) }
        }
        r.liveEnvironment("isPresented", .navigation, read: { env, _ in .bool(env.isPresented) })
        r.liveEnvironment("editMode", .navigation, notes: "`editMode?.wrappedValue` is `.active` or `.inactive` (`isEditing`); set it to start editing.", read: { env, _ in
            #if os(iOS)
            guard let mode = env.editMode else { return .nilValue }
            return .binding(KBinding(get: { editModeValue(mode.wrappedValue) }, set: { v in
                if case .native(.implicit(let n, _)) = v { mode.wrappedValue = n == "active" ? .active : (n == "transient" ? .transient : .inactive) }
            }))
            #else
            return .nilValue
            #endif
        }, write: { view, v, _ in
            #if os(iOS)
            guard case .binding(let b) = v else { return view }
            return AnyView(view.environment(\.editMode, Binding(get: {
                if case .native(.implicit(let n, _)) = b.get() { return n == "active" ? .active : (n == "transient" ? .transient : .inactive) }
                return .inactive
            }, set: { b.set(editModeValue($0)) })))
            #else
            return view
            #endif
        })
        r.implicitProperties["isEditing"] = { base, _ in
            ["active", "inactive", "transient"].contains(base) ? .bool(base != "inactive") : nil
        }
    }

    #if os(iOS)
    @MainActor static func editModeValue(_ m: EditMode) -> KV {
        .native(.implicit(m == .active ? "active" : (m == .transient ? "transient" : "inactive"), []))
    }
    #endif

    @MainActor static func detent(_ v: KV?) -> PresentationDetent? {
        guard case .native(.implicit(let n, let a))? = v else { return nil }
        switch n {
        case "medium": return .medium
        case "large": return .large
        case "fraction": return a.first?.asDouble.map { .fraction($0) }
        case "height": return a.first?.asDouble.map { .height($0) }
        default: return nil
        }
    }

    @MainActor static func detentValue(_ d: PresentationDetent) -> KV {
        if d == .medium { return .native(.implicit("medium", [])) }
        return .native(.implicit("large", []))
    }

    @MainActor static func adaptation(_ v: KV?) -> PresentationAdaptation {
        switch v.flatMap({ if case .native(.implicit(let n, _)) = $0 { return n }; return nil }) {
        case "popover"?: return .popover
        case "sheet"?: return .sheet
        case "fullScreenCover"?: return .fullScreenCover
        case "none"?: return .none
        default: return .automatic
        }
    }

    @MainActor static func image(_ v: KV?) -> Image? {
        guard case .view(let iv)? = v, case .primitive("Image", let args, let labels, _) = iv.kind else { return nil }
        let a = KArgs(args: args, labels: labels)
        if let s = a["systemName"]?.asString { return Image(systemName: s) }
        if let s = a.first?.asString { return Image(s) }
        return nil
    }

    @MainActor static func statusBarHidden(_ hidden: Bool, _ view: AnyView) -> AnyView {
        #if os(iOS)
        return AnyView(view.statusBarHidden(hidden))
        #else
        return view
        #endif
    }

    @MainActor static func dismissalDialog(_ c: KCall, _ view: AnyView) -> AnyView {
        #if os(iOS)
        if #available(iOS 27.0, *) {
            let actions = c.content("actions"), title = c.string(0) ?? ""
            let should = c.bool("shouldPresent", default: true)
            if c["message"] != nil {
                let message = c.content("message")
                return AnyView(view.dismissalConfirmationDialog(title, shouldPresent: should) { actions } message: { message })
            }
            return AnyView(view.dismissalConfirmationDialog(title, shouldPresent: should) { actions })
        }
        #endif
        return view
    }

    /// `ActionSheet(title:message:buttons:)` as a confirmation dialog.
    @MainActor static func actionSheet(_ c: KCall, _ view: AnyView) -> AnyView {
        let interp = c.interp, r = c.r
        guard let b = c.kbinding("isPresented") ?? c.kbinding("item"), case .function(let fn)? = c.last else { return view }
        let shown = Binding<Bool>(get: { let v = b.get(); return v.isNil ? false : interp.truthy(v) },
                                  set: { if !$0 { b.set(b.get().asBool != nil ? .bool(false) : .nilValue) } })
        let item = b.get()
        guard let sheet = try? interp.entry({ try interp.call(fn, item.asBool == nil && !item.isNil ? [item] : [], [nil]) }),
              case .tuple(let vals, let labels) = sheet else { return view }
        func text(_ v: KV?) -> String? {
            guard let v else { return nil }
            if case .view(let tv) = v { return r.plainText(tv) }
            return r.string(v)
        }
        let get: (String) -> KV? = { l in labels.firstIndex(of: l).map { vals[$0] } }
        let title = text(get("title")) ?? ""
        let message = text(get("message"))
        let buttons: [(String, ButtonRole?, KV?)] = (get("buttons")?.asArray ?? []).compactMap { btn in
            guard case .native(.implicit(let kind, let args)) = btn else { return nil }
            let label = text(args.first) ?? (kind == "cancel" ? "Cancel" : "OK")
            let action = args.last { if case .function = $0 { return true }; return false }
            return (label, kind == "destructive" ? .destructive : (kind == "cancel" ? .cancel : nil), action)
        }
        return AnyView(view.confirmationDialog(title, isPresented: shown, titleVisibility: .visible) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { _, btn in
                Button(btn.0, role: btn.1) { r.action(btn.2)() }
            }
        } message: {
            if let message { Text(message) }
        })
    }
}
