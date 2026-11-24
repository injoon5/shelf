//
//  Search.swift
//  Bridges: the search field, its suggestions, scopes and tokens, and the
//  search environment values
//
//  `.searchable(text:)` with `placement:`, `prompt:` and `isPresented:`;
//  `.searchSuggestions { … }` with `.searchCompletion`; `.searchScopes`; and
//  `@Environment(\.isSearching)` and `\.dismissSearch` read where the view is
//  shown.
//

import SwiftUI

/// A token in the search field: the app's value, known by its id.
struct KSearchToken: Identifiable {
    let id: KV
    let value: KV
}

extension NavigationBridges {
    static func search(_ r: KRegistry) {
        r.modifier("searchable", .navigation, notes: "`text:` with `placement:`, `prompt:` and `isPresented:`; `tokens:` (with `token:`) and `suggestions:`.") { m in
            m.forms(["text:binding placement:any? prompt:title?", "text:binding isPresented:binding placement:any? prompt:title?",
                     "text:binding placement:any? prompt:title? suggestions:content",
                     "text:binding tokens:binding placement:any? prompt:title? token:content",
                     "text:binding tokens:binding isPresented:binding placement:any? prompt:title? token:content",
                     "text:binding tokens:binding suggestedTokens:binding placement:any? prompt:title? token:content",
                     "text:binding tokens:binding suggestedTokens:binding isPresented:binding placement:any? prompt:title? token:content",
                     "text:binding editableTokens:binding placement:any? prompt:title? token:content",
                     "text:binding editableTokens:binding isPresented:binding placement:any? prompt:title? token:content"]) { c, view in searchable(c, view) }
        }
        // iOS 26: the selection in the search field, a `TextSelection?` over the `.searchable` text (Sharing).
        r.modifier("searchSelection", .navigation, introduced: "26.0") { m in
            m.form("_:binding", introduced: "26.0") { c, view in
                if #available(iOS 26, macOS 26, *), let sb = c.kbinding(0) {
                    let text = c.base?.modifier("searchable")?.arg("text")
                    let interp = c.interp
                    view.searchSelection(KTextSelection.binding(sb) {
                        if case .binding(let b)? = text { return b.get().asString ?? "" }
                        return text.flatMap { interp.describe($0) } ?? ""
                    })
                } else {
                    view
                }
            }
        }
        r.modifier("searchSuggestions", .navigation) { m in
            m.form("_:content") { c, view in
                let content = c.content(0)
                view.searchSuggestions { content }
            }
            m.form("_:Visibility for:any") { c, view in
                view.searchSuggestions(KControlValues.visibility(c[0]), for: c.symbol("for") == "content" ? .content : .menu)
            }
        }
        r.modifier("searchCompletion", .navigation, notes: "On a suggestion: tapping it fills the field with this text (or adds this token).") { m in
            m.form("_:any") { c, view in
                if case .string(let s)? = c[0] { AnyView(view.searchCompletion(s)) }
                else { AnyView(view.searchCompletion(KSearchToken(id: c[0] ?? .nilValue, value: c[0] ?? .nilValue))) }
            }
        }
        r.modifier("searchScopes", .navigation) { m in
            m.forms(["_:binding scopes:content", "_:binding activation:any _:content"]) { c, view in
                if let b = c.kbinding(0) {
                    let scope = Binding<KV>(get: { b.get() }, set: { b.set($0) })
                    let scopes = c.content(c["scopes"] != nil ? "scopes" : 1)
                    switch c.symbol("activation") {
                    case "onTextEntry": AnyView(view.searchScopes(scope, activation: .onTextEntry) { scopes })
                    case "onSearchPresentation": AnyView(view.searchScopes(scope, activation: .onSearchPresentation) { scopes })
                    default: AnyView(view.searchScopes(scope) { scopes })
                    }
                } else { view }
            }
        }
        r.modifier("searchDictationBehavior", .navigation, notes: "Inline dictation is visionOS's; on iPhone the field keeps its usual dictation.") { m in
            m.form("_:any") { _, view in
                #if os(iOS)
                view.searchDictationBehavior(.automatic)
                #else
                view
                #endif
            }
        }
        r.modifier("searchPresentationToolbarBehavior", .navigation) { m in
            m.form("_:any") { c, view in
                if #available(iOS 17.1, macOS 14.1, *) {
                    AnyView(view.searchPresentationToolbarBehavior(c.symbol(0) == "avoidHidingContent" ? .avoidHidingContent : .automatic))
                } else { view }
            }
        }
        r.modifier("searchToolbarBehavior", .navigation, introduced: "26.0", notes: "`.minimize`: the search field shrinks to a button in the toolbar.") { m in
            m.form("_:any") { c, view in
                #if os(iOS)
                if #available(iOS 26.0, *) { AnyView(view.searchToolbarBehavior(c.symbol(0) == "minimize" ? .minimize : .automatic)) } else { view }
                #else
                view
                #endif
            }
        }
        r.type("SearchFieldPlacement", .navigation, support: .full) { t in
            t.anyStatic { _, member in .native(.implicit(member, [])) }
        }
        r.liveEnvironment("isSearching", .navigation, read: { env, _ in .bool(env.isSearching) })
        r.liveEnvironment("dismissSearch", .navigation, read: { env, _ in
            let dismiss = env.dismissSearch
            return .native(.dismiss(KRef({ dismiss() })))
        })
        r.liveEnvironment("searchSuggestionsPlacement", .navigation, read: { env, _ in
            .native(.implicit(env.searchSuggestionsPlacement == .content ? "content" : "menu", []))
        })
    }

    @MainActor static func searchPlacement(_ v: KV?) -> SearchFieldPlacement {
        guard case .native(.implicit(let n, let args))? = v else { return .automatic }
        switch n {
        #if os(iOS)
        case "navigationBarDrawer":
            if case .native(.implicit("always", _))? = args.first { return .navigationBarDrawer(displayMode: .always) }
            return .navigationBarDrawer
        #endif
        case "toolbar": return .toolbar
        case "sidebar": return .sidebar
        case "toolbarPrincipal":
            if #available(iOS 18.0, macOS 15.0, *) { return .toolbarPrincipal }
            return .automatic
        default: return .automatic
        }
    }

    @MainActor static func searchable(_ c: KCall, _ view: AnyView) -> AnyView {
        guard let b = c.kbinding("text") else { return view }
        let r = c.r
        let text = r.stringBinding(b)
        let placement = searchPlacement(c["placement"])
        let prompt = Text(c.string("prompt") ?? "Search")
        if let tb = c.kbinding("tokens") ?? c.kbinding("editableTokens"), let tokenFn = c["token"] {
            let tokens = Binding<[KSearchToken]>(get: {
                ((try? c.interp.sequence(tb.get())) ?? []).map { KSearchToken(id: r.rowID($0, nil) ?? $0, value: $0) }
            }, set: { tb.set(.array($0.map(\.value))) })
            if let sb = c.kbinding("suggestedTokens") {
                let suggested = Binding<[KSearchToken]>(get: {
                    ((try? c.interp.sequence(sb.get())) ?? []).map { KSearchToken(id: r.rowID($0, nil) ?? $0, value: $0) }
                }, set: { sb.set(.array($0.map(\.value))) })
                if let pb = c.kbinding("isPresented") {
                    return AnyView(view.searchable(text: text, tokens: tokens, suggestedTokens: suggested, isPresented: r.boolBinding(pb), placement: placement,
                                                   prompt: prompt) { token in r.renderContent(tokenFn, [token.value]) })
                }
                return AnyView(view.searchable(text: text, tokens: tokens, suggestedTokens: suggested, placement: placement, prompt: prompt) { token in
                    r.renderContent(tokenFn, [token.value])
                })
            }
            if let pb = c.kbinding("isPresented") {
                return AnyView(view.searchable(text: text, tokens: tokens, isPresented: r.boolBinding(pb), placement: placement, prompt: prompt) { token in
                    r.renderContent(tokenFn, [token.value])
                })
            }
            return AnyView(view.searchable(text: text, tokens: tokens, placement: placement, prompt: prompt) { token in r.renderContent(tokenFn, [token.value]) })
        }
        if let pb = c.kbinding("isPresented") {
            return AnyView(view.searchable(text: text, isPresented: r.boolBinding(pb), placement: placement, prompt: prompt))
        }
        if let s = c["suggestions"] {
            let suggestions = r.renderContent(s)
            return AnyView(view.searchable(text: text, placement: placement, prompt: prompt).searchSuggestions { suggestions })
        }
        return AnyView(view.searchable(text: text, placement: placement, prompt: prompt))
    }
}
