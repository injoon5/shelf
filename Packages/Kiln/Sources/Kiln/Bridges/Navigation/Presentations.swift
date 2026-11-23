//
//  Presentations.swift
//  Bridges: sheets, full-screen covers, alerts, dialogs and context menus
//

import SwiftUI

extension NavigationBridges {
    static func presentations(_ r: KRegistry) {
        for name in ["sheet", "fullScreenCover", "popover"] {
            r.modifier(name, .navigation, support: name == "popover" ? .partial : .full,
                       notes: name == "popover" ? "Shown as a sheet." : nil) { m in
                let extra = name == "popover" ? "attachmentAnchor:any? arrowEdge:any? " : "onDismiss:action? "
                m.forms(["isPresented:binding \(extra)content:content", "item:binding \(extra)content:content"]) { c, view in sheet(c, view, name) }
            }
        }
        r.modifier("alert", .navigation, support: .partial, notes: "Buttons and a message; or the old `Alert(title:message:dismissButton:)`, shown with one OK button.") { m in
            m.forms(["_:title isPresented:binding actions:content", "_:title isPresented:binding actions:content message:content",
                     "_:title isPresented:binding presenting:any? actions:content message:content?",
                     "isPresented:binding content:closure", "item:binding content:closure"]) { c, view in alert(c, view) }
        }
        r.modifier("confirmationDialog", .navigation, support: .partial) { m in
            m.forms(["_:title isPresented:binding titleVisibility:any? actions:content", "_:title isPresented:binding titleVisibility:any? actions:content message:content",
                     "_:title isPresented:binding titleVisibility:any? presenting:any? actions:content message:content?"]) { c, view in
                if let b = c.kbinding("isPresented") {
                    let actions = c.r.renderContent(c["actions"] ?? c.a.unlabeledFunction(0))
                    let title = c.string(0) ?? ""
                    if let message = c["message"].map({ c.r.renderContent($0) }) {
                        AnyView(view.confirmationDialog(title, isPresented: c.r.boolBinding(b), titleVisibility: .visible) { actions } message: { message })
                    } else {
                        AnyView(view.confirmationDialog(title, isPresented: c.r.boolBinding(b), titleVisibility: .visible) { actions })
                    }
                } else {
                    view
                }
            }
        }
        r.modifier("presentationDetents", .navigation) { m in
            m.form("_:any selection:binding?") { c, view in view.presentationDetents(detents(c[0])) }
        }
        r.modifier("presentationDragIndicator", .navigation, support: .partial, notes: "Always visible.") { m in
            m.form("_:Visibility") { _, view in view.presentationDragIndicator(.visible) }
        }
        r.modifier("presentationCornerRadius", .navigation, support: .stub) { m in m.stub(["_:number?"]) }
        r.modifier("interactiveDismissDisabled", .navigation, support: .stub) { m in m.stub(["_:bool?"]) }
        r.modifier("contextMenu", .navigation, support: .partial, notes: "Its menu items; `preview:` isn't shown.") { m in
            m.forms(["menuItems:content", "menuItems:content preview:content"]) { c, view in
                let content = c.content("menuItems")
                view.contextMenu { content }
            }
        }
    }

    @MainActor static func detents(_ v: KV?) -> Set<PresentationDetent> {
        var detents: Set<PresentationDetent> = []
        for d in v?.asArray ?? [] {
            guard case .native(.implicit(let n, let a)) = d else { continue }
            if n == "medium" { detents.insert(.medium) }
            else if n == "large" { detents.insert(.large) }
            else if n == "fraction", let f = a.first?.asDouble { detents.insert(.fraction(f)) }
            else if n == "height", let h = a.first?.asDouble { detents.insert(.height(h)) }
        }
        return detents.isEmpty ? [.large] : detents
    }

    @MainActor static func sheet(_ c: KCall, _ view: AnyView, _ name: String) -> AnyView {
        let r = c.r
        guard let fn = c.last, r.isFunction(fn) else { return view }
        let onDismiss = r.action(c["onDismiss"])
        if let b = c.kbinding("item") {
            let item = Binding<KSheetItem?>(get: { let v = b.get(); return v.isNil ? nil : KSheetItem(value: v) },
                                            set: { b.set($0?.value ?? .nilValue) })
            #if os(iOS)
            if name == "fullScreenCover" {
                return AnyView(view.fullScreenCover(item: item, onDismiss: onDismiss) { it in KLazyView { r.renderContent(fn, [it.value]) } })
            }
            #endif
            return AnyView(view.sheet(item: item, onDismiss: onDismiss) { it in KLazyView { r.renderContent(fn, [it.value]) } })
        }
        guard let b = c.kbinding("isPresented") else { return view }
        let shown = r.boolBinding(b)
        #if os(iOS)
        if name == "fullScreenCover" {
            return AnyView(view.fullScreenCover(isPresented: shown, onDismiss: onDismiss) { KLazyView { r.renderContent(fn) } })
        }
        #endif
        return AnyView(view.sheet(isPresented: shown, onDismiss: onDismiss) { KLazyView { r.renderContent(fn) } })
    }

    @MainActor static func alert(_ c: KCall, _ view: AnyView) -> AnyView {
        let interp = c.interp, r = c.r
        guard let b = c.kbinding("isPresented") ?? c.kbinding("item") else { return view }
        let shown = Binding<Bool>(get: { let v = b.get(); return v.isNil ? false : interp.truthy(v) },
                                  set: { if !$0 { b.set(b.get().asBool != nil ? .bool(false) : .nilValue) } })
        // The old API: .alert(isPresented:) { Alert(title:message:dismissButton:) }
        if c.labels.contains("content"), case .function(let fn)? = c.last,
           let alertValue = try? interp.entry({ try interp.call(fn, [], []) }), case .tuple(let vals, let labels) = alertValue {
            func text(_ l: String) -> String? {
                guard let i = labels.firstIndex(of: l) else { return nil }
                if case .view(let tv) = vals[i] { return r.plainText(tv) }
                return r.string(vals[i])
            }
            let title = text("title") ?? ""
            let message = text("message")
            return AnyView(view.alert(title, isPresented: shown) { Button("OK", role: .cancel) {} } message: {
                if let message { Text(message) }
            })
        }
        let title = r.string(c.first.flatMap { if case .string = $0 { return $0 }; if case .view = $0 { return $0 }; return nil }) ?? ""
        let actions = (c["actions"] ?? c.a.unlabeledFunction(0)).map { r.renderContent($0) }
        let message = c["message"].map { r.renderContent($0) }
        switch (actions, message) {
        case (let a?, let msg?): return AnyView(view.alert(title, isPresented: shown) { a } message: { msg })
        case (let a?, nil): return AnyView(view.alert(title, isPresented: shown) { a })
        case (nil, let msg?): return AnyView(view.alert(title, isPresented: shown) { Button("OK", role: .cancel) {} } message: { msg })
        default: return AnyView(view.alert(title, isPresented: shown) { Button("OK", role: .cancel) {} })
        }
    }
}
