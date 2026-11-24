//
//  Web.swift
//  Bridges: SwiftUI's WebView and WebKit's WebPage (PLAN.md §3.6)
//
//  - `WebView(url:)` and `WebView(page)`.
//  - `WebPage()`: `load` a URL, a request, HTML or data; `title`, `url`,
//    `isLoading`, `estimatedProgress`, `themeColor`; `reload()`,
//    `stopLoading()`; back and forward through `backForwardList`; and
//    `try await callJavaScript(…)`. `WebPage` is a native `@Observable`:
//    the app's `body` reads it inside the hosting view's real `body`, so
//    SwiftUI tracks its title and progress as it would natively (§1.4).
//  - The `webView…` modifiers.
//
//  Every page uses the app's own website data store (`KilnWebsiteData`),
//  and is stopped and emptied when the app's screen closes. A check never
//  touches the network: a web address isn't loaded, HTML is.
//

import SwiftUI
#if canImport(WebKit) && !os(tvOS) && !os(watchOS)
import WebKit
#endif

@objc(KilnBridges_Web)
final class WebBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        pages(r)
        views(r)
        modifiers(r)
    }

    static let iOS26 = "26.0"

    @MainActor static func isLive(_ c: KCall) -> Bool { !(c.interp.headless || c.context.isStub) }

    // MARK: WebPage

    static func pages(_ r: KRegistry) {
        r.type("WebPage", .web, support: .full, introduced: iOS26) { t in
            #if canImport(WebKit) && !os(tvOS) && !os(watchOS)
            t.initializer("") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) else { throw c.fail("WebPage needs iOS 26") }
                return KWeb.value(KWeb.makePage(c.context))
            }
            t.method("load", "_:any") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let page = KWeb.page(c.receiver) else { return .void }
                if case .native(.object("URLRequest", _))? = c[0], let request = KBuiltins.request(c[0]) {
                    return try KWeb.load(page, request: request, c)
                }
                if c[0]?.isNil == true { return KWeb.events(nil) }
                guard let url = c.url(0) else { throw c.fail("needs a URL or a URLRequest") }
                return try KWeb.load(page, request: URLRequest(url: url), c)
            }
            t.method("load", "html:string baseURL:URL?") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let page = KWeb.page(c.receiver) else { return .void }
                let base = c.url("baseURL") ?? URL(string: "about:blank")!
                return KWeb.events(page.load(html: c.string("html") ?? "", baseURL: KWeb.safeBase(base)))
            }
            t.method("load", "_:any mimeType:string characterEncoding:any baseURL:URL") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let page = KWeb.page(c.receiver) else { return .void }
                guard let data = KBuiltins.dataValue(c[0]) else { throw c.fail("needs Data") }
                let base = c.url("baseURL") ?? URL(string: "about:blank")!
                return KWeb.events(page.load(data, mimeType: c.string("mimeType") ?? "text/html", characterEncoding: .utf8,
                                             baseURL: KWeb.safeBase(base)))
            }
            t.method("reload", "fromOrigin:bool?") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let page = KWeb.page(c.receiver) else { return .void }
                guard isLive(c) || page.url?.isFileURL != false else { return KWeb.events(nil) }
                return KWeb.events(page.reload(fromOrigin: c.bool("fromOrigin", default: false)))
            }
            t.method("stopLoading", "") { c in
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) { KWeb.page(c.receiver)?.stopLoading() }
                return .void
            }
            t.method("callJavaScript", "_:string arguments:any? in:any? contentWorld:any?", async: true) { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let page = KWeb.page(c.receiver) else { return .nilValue }
                let body = c.string(0) ?? ""
                var arguments: [String: Any] = [:]
                if case .dict(let d)? = c["arguments"] {
                    for (k, v) in d { arguments[k.asString ?? c.interp.describe(k)] = KNativeValues.native(from: v) ?? NSNull() }
                }
                let args = KUnsafeSendable(arguments)
                return .suspension(KSuspension.async(headless: { .nilValue }) {
                    do {
                        let result = try await page.callJavaScript(body, arguments: args.value)
                        return KNativeValues.any(result)
                    } catch {
                        throw KEThrown(value: KBuiltins.errorValue(error.localizedDescription))
                    }
                })
            }
            t.property("navigations") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let page = KWeb.page(c.receiver) else { return .nilValue }
                return KWeb.events(page.navigations)
            }
            t.property("title") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) else { return .string("") }
                return .string(KWeb.page(c.receiver)?.title ?? "")
            }
            t.property("url") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) else { return .nilValue }
                return KWeb.page(c.receiver)?.url.map { .native(.url($0)) } ?? .nilValue
            }
            t.property("isLoading") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) else { return .bool(false) }
                return .bool(KWeb.page(c.receiver)?.isLoading ?? false)
            }
            t.property("estimatedProgress") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) else { return .double(0) }
                return .double(KWeb.page(c.receiver)?.estimatedProgress ?? 0)
            }
            t.property("hasOnlySecureContent") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) else { return .bool(false) }
                return .bool(KWeb.page(c.receiver)?.hasOnlySecureContent ?? false)
            }
            t.property("themeColor") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) else { return .nilValue }
                return KWeb.page(c.receiver)?.themeColor.map { .native(.color($0)) } ?? .nilValue
            }
            t.property("customUserAgent", { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) else { return .nilValue }
                return KWeb.page(c.receiver)?.customUserAgent.map(KV.string) ?? .nilValue
            }, set: { c in
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) { KWeb.page(c.receiver)?.customUserAgent = c.string(0) }
            })
            t.property("backForwardList") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let page = KWeb.page(c.receiver) else { return .nilValue }
                return .native(.object("WebPage.BackForwardList", KRef(KWebHistory(page))))
            }
            #endif
        }

        r.type("WebPage.BackForwardList", .web, support: .full, introduced: iOS26) { t in
            #if canImport(WebKit) && !os(tvOS) && !os(watchOS)
            @MainActor func items(_ c: KCall, _ pick: (KWebHistory) -> [KV]) -> KV {
                guard let h = c.object(KWebHistory.self) else { return .array([]) }
                return .array(pick(h))
            }
            t.property("backList") { c in items(c) { $0.back } }
            t.property("forwardList") { c in items(c) { $0.forward } }
            t.property("currentItem") { c in c.object(KWebHistory.self)?.current ?? .nilValue }
            #endif
        }
        r.type("WebPage.BackForwardList.Item", .web, support: .full, introduced: iOS26) { t in
            #if canImport(WebKit) && !os(tvOS) && !os(watchOS)
            t.property("title") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let i = c.receiver.boxedValue(WebPage.BackForwardList.Item.self) else { return .nilValue }
                return i.title.map(KV.string) ?? .nilValue
            }
            t.property("url") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let i = c.receiver.boxedValue(WebPage.BackForwardList.Item.self) else { return .nilValue }
                return .native(.url(i.url))
            }
            t.property("initialURL") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let i = c.receiver.boxedValue(WebPage.BackForwardList.Item.self) else { return .nilValue }
                return .native(.url(i.initialURL))
            }
            #endif
        }
    }

    // MARK: WebView

    static func views(_ r: KRegistry) {
        r.view("WebView", .web, introduced: iOS26) { v in
            v.form("url:any") { c in
                #if canImport(WebKit) && !os(tvOS) && !os(watchOS)
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                    KWebURLView(url: c.url("url"), context: c.context, live: isLive(c))
                }
                #endif
            }
            v.form("_:any") { c in
                #if canImport(WebKit) && !os(tvOS) && !os(watchOS)
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let page = KWeb.page(c[0]) {
                    WebView(page)
                }
                #endif
            }
        }
    }

    // MARK: Modifiers

    static func modifiers(_ r: KRegistry) {
        /// `.enabled`, `.disabled`, `.automatic`.
        func behavior(_ name: String) {
            r.modifier(name, .web, introduced: iOS26) { m in
                m.form("_:any") { c, view in
                    #if canImport(WebKit) && !os(tvOS) && !os(watchOS)
                    if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) { KWebModifiers.apply(name, c.symbol(0) ?? "automatic", view) } else { view }
                    #else
                    view
                    #endif
                }
            }
        }
        for name in ["webViewBackForwardNavigationGestures", "webViewMagnificationGestures", "webViewLinkPreviews",
                     "webViewElementFullscreenBehavior", "webViewTextSelection", "webViewContentBackground"] {
            behavior(name)
        }
        r.modifier("webViewScrollPosition", .web, introduced: iOS26, notes: nil) { m in
            m.form("_:binding") { c, view in
                #if canImport(WebKit) && !os(tvOS) && !os(watchOS)
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let b = c.kbinding(0) {
                    AnyView(view.webViewScrollPosition(Binding<ScrollPosition>(get: {
                        if case .native(.object(_, let ref)) = b.get(), let box = ref.value as? KScrollPositionBox { return box.position }
                        return ScrollPosition()
                    }, set: { b.set(KScrollPositionBox($0).kv) })))
                } else { view }
                #else
                view
                #endif
            }
        }
        r.modifier("webViewOnScrollGeometryChange", .web, introduced: iOS26,
                   notes: nil) { m in
            m.forms(["for:any of:closure action:closure", "for:any of:closure _:closure"]) { c, view in
                #if canImport(WebKit) && !os(tvOS) && !os(watchOS)
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) { KWebModifiers.onScrollGeometryChange(c, view) } else { view }
                #else
                view
                #endif
            }
            m.probe { label, _ in label == "action" ? [.double(0), .double(0)] : [.native(.object("ScrollGeometry", KRef(NSObject())))] }
        }
    }
}

#if canImport(WebKit) && !os(tvOS) && !os(watchOS)

// MARK: - Pages

@MainActor
enum KWeb {
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    static func makePage(_ context: KilnContext) -> WebPage {
        var config = WebPage.Configuration()
        config.websiteDataStore = KilnWebsiteData.store(for: context)
        let page = WebPage(configuration: config)
        // Closed with the card: nothing keeps loading or playing.
        context.onTearDown { [weak page] in
            page?.stopLoading()
            _ = page?.load(html: "", baseURL: URL(string: "about:blank")!)
        }
        return page
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    static func value(_ page: WebPage) -> KV { .native(.object("WebPage", KRef(page))) }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    static func page(_ v: KV?) -> WebPage? {
        if case .native(.object(_, let ref))? = v { return ref.value as? WebPage }
        return nil
    }

    /// A request: a web address (never in a check), or a file in the app's
    /// folder, loaded from its contents.
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    static func load(_ page: WebPage, request: URLRequest, _ c: KCall) throws -> KV {
        guard let url = request.url else { throw c.fail("needs a URL") }
        if url.isFileURL {
            let file: URL
            do { file = try c.context.files.resolve(url) } catch let refusal as KilnFiles.Refusal { throw c.fail(refusal.description) }
            let data: Data
            do { data = try Data(contentsOf: file) } catch { throw FoundationBridges.thrown(error, c) }
            let mime = file.pathExtension.lowercased() == "txt" ? "text/plain" : "text/html"
            return events(page.load(data, mimeType: mime, characterEncoding: .utf8, baseURL: safeBase(url)))
        }
        guard WebBridges.isLive(c) else { return events(nil) }
        return events(page.load(request))
    }

    /// A page's base URL: a file URL would give the page the app's folder,
    /// and the real folder's path, so it's left out.
    static func safeBase(_ url: URL) -> URL {
        url.isFileURL ? URL(string: "about:blank")! : url
    }

    /// What `load` returns: its navigation events, for `for try await`.
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    static func events<S: AsyncSequence>(_ s: S?) -> KV where S.Element == WebPage.NavigationEvent {
        guard let s else { return events(nil as AsyncStream<WebPage.NavigationEvent>?) }
        return .native(.object("AsyncSequence", KRef(KAsyncSequence.wrapping("WebPage.NavigationEvent", s) { event in
            switch event {
            case .startedProvisionalNavigation: return .native(.implicit("startedProvisionalNavigation", []))
            case .receivedServerRedirect: return .native(.implicit("receivedServerRedirect", []))
            case .committed: return .native(.implicit("committed", []))
            case .finished: return .native(.implicit("finished", []))
            @unknown default: return .native(.implicit("finished", []))
            }
        })))
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    static func events(_ none: AsyncStream<WebPage.NavigationEvent>?) -> KV {
        if let none { return events(Optional(none)) }
        return .native(.object("AsyncSequence", KRef(KAsyncSequence.wrapping("WebPage.NavigationEvent", AsyncStream<Int> { $0.finish() }) { _ in .void })))
    }
}

/// `page.backForwardList`, read when asked.
@MainActor
final class KWebHistory {
    private let read: () -> (back: [KV], forward: [KV], current: KV)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    init(_ page: WebPage) {
        read = {
            let list = page.backForwardList
            func item(_ i: WebPage.BackForwardList.Item) -> KV { .native(.boxed(KBoxed("WebPage.BackForwardList.Item", KHashableItem(i)))) }
            return (list.backList.map(item), list.forwardList.map(item), list.currentItem.map(item) ?? .nilValue)
        }
    }
    var back: [KV] { read().back }
    var forward: [KV] { read().forward }
    var current: KV { read().current }
}

/// A back-forward item as a boxed value (`Item` is `Equatable`, not `Hashable`).
struct KHashableItem: Hashable {
    let item: Any
    let id: AnyHashable
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    init(_ item: WebPage.BackForwardList.Item) { self.item = item; id = AnyHashable(item.id) }
    static func == (a: KHashableItem, b: KHashableItem) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

extension KV {
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    func boxedValue(_: WebPage.BackForwardList.Item.Type) -> WebPage.BackForwardList.Item? {
        if case .native(.boxed(let b)) = self { return (b.value.base as? KHashableItem)?.item as? WebPage.BackForwardList.Item }
        return nil
    }
}

// MARK: - Views

/// `WebView(url:)`: its own page, in the app's store, loading the URL
/// when it first shows and whenever it changes.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct KWebURLView: View {
    let url: URL?
    let context: KilnContext
    let live: Bool
    @State private var holder = KWebURLHolder()

    var body: some View {
        WebView(holder.page(context))
            .onAppear { holder.load(url, live: live, context: context) }
            .onChange(of: url) { holder.load(url, live: live, context: context) }
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@MainActor
final class KWebURLHolder {
    private var made: WebPage?
    private var loaded: URL?

    func page(_ context: KilnContext) -> WebPage {
        if let made { return made }
        let page = KWeb.makePage(context)
        made = page
        return page
    }

    func load(_ url: URL?, live: Bool, context: KilnContext) {
        guard let url, url != loaded else { return }
        loaded = url
        let page = page(context)
        if url.isFileURL {
            guard let file = try? context.files.resolve(url), let data = try? Data(contentsOf: file) else { return }
            _ = page.load(data, mimeType: "text/html", characterEncoding: .utf8, baseURL: URL(string: "about:blank")!)
        } else if live {
            _ = page.load(URLRequest(url: url))
        }
    }
}

// MARK: - Modifiers

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@MainActor
enum KWebModifiers {
    static func apply(_ name: String, _ symbol: String, _ view: AnyView) -> AnyView {
        switch name {
        case "webViewBackForwardNavigationGestures":
            let b: WebView.BackForwardNavigationGesturesBehavior = symbol == "enabled" ? .enabled : symbol == "disabled" ? .disabled : .automatic
            return AnyView(view.webViewBackForwardNavigationGestures(b))
        case "webViewMagnificationGestures":
            let b: WebView.MagnificationGesturesBehavior = symbol == "enabled" ? .enabled : symbol == "disabled" ? .disabled : .automatic
            return AnyView(view.webViewMagnificationGestures(b))
        case "webViewLinkPreviews":
            let b: WebView.LinkPreviewBehavior = symbol == "enabled" ? .enabled : symbol == "disabled" ? .disabled : .automatic
            return AnyView(view.webViewLinkPreviews(b))
        case "webViewElementFullscreenBehavior":
            let b: WebView.ElementFullscreenBehavior = symbol == "enabled" ? .enabled : symbol == "disabled" ? .disabled : .automatic
            return AnyView(view.webViewElementFullscreenBehavior(b))
        case "webViewTextSelection":
            return symbol == "disabled" ? AnyView(view.webViewTextSelection(.disabled)) : AnyView(view.webViewTextSelection(.enabled))
        case "webViewContentBackground":
            let v: Visibility = symbol == "hidden" ? .hidden : symbol == "visible" ? .visible : .automatic
            return AnyView(view.webViewContentBackground(v))
        default:
            return view
        }
    }

    static func onScrollGeometryChange(_ c: KCall, _ view: AnyView) -> AnyView {
        guard case .function(let transform)? = c["of"], case .function(let action)? = c.last else { return view }
        let interp = c.interp
        let n = c.r.closureParamCount(.function(action))
        return AnyView(view.webViewOnScrollGeometryChange(for: KHashableKV.self, of: { geo in
            MainActor.assumeIsolated {
                KHashableKV((try? interp.entry { try interp.call(transform, [.native(.object("ScrollGeometry", KRef(KScrollGeometryBox(geo))))], [nil]) }) ?? .nilValue)
            }
        }, action: { old, new in
            interp.perform(action, n >= 2 ? [old.value, new.value] : [new.value])
        }))
    }
}

/// A value SwiftUI compares, by Kiln's equality.
struct KHashableKV: Hashable, @unchecked Sendable {
    let value: KV
    init(_ value: KV) { self.value = value }
}

#endif
