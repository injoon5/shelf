//
//  WebBridgeTests.swift
//  KilnTests
//
//  PLAN.md §3.6: WebView and WebPage with local HTML, `callJavaScript`,
//  navigation events, back and forward, each app's own website data, and
//  teardown.
//

import XCTest
import SwiftUI
import WebKit
@testable import Kiln

@MainActor
@available(macOS 26.0, iOS 26.0, *)
final class WebBridgeTests: XCTestCase {
    private var folders: [URL] = []
    private var slugs: [String] = []

    override func tearDown() async throws {
        for f in folders { try? FileManager.default.removeItem(at: f) }
        for s in slugs { try? await KilnWebsiteData.remove(for: s) }
    }

    private func context(_ slug: String) -> KilnContext {
        let folder = FileManager.default.temporaryDirectory.appending(path: "kiln-web-\(UUID().uuidString)")
        folders.append(folder)
        slugs.append(slug)
        return KilnContext(slug: slug, name: slug, defaults: KilnMemoryDefaults(), files: KilnFiles(root: folder))
    }

    /// Runs the app's `async` `main()` for real with `context`, and returns what it returned.
    private func run(_ source: String, _ context: KilnContext) async throws -> (KInterpreter, KV?) {
        let c = try KilnEngine.compile(source + "\nstruct ContentView: View { var body: some View { Text(\"x\") } }",
                                       headless: false, context: context)
        let main = try XCTUnwrap(c.interp.functions["main"]?.first)
        let t = c.interp.startTask(KFunction(.user(main, c.interp.globalEnv, nil)), [], parent: nil, reportsErrors: true)
        if case .value(let v) = await t.completion() { return (c.interp, v) }
        return (c.interp, nil)
    }

    static let app = """
    import SwiftUI
    import WebKit

    struct ContentView: View {
        @State private var page = WebPage()
        @State private var answer = ""
        @State private var showFind = false
        @State private var position = ScrollPosition(edge: .top)
        @State private var offset = 0.0

        var body: some View {
            NavigationStack {
                VStack {
                    Text(page.title)
                    ProgressView(value: page.estimatedProgress)
                    Text(page.isLoading ? "Loading" : "Idle")
                    Text(page.url?.absoluteString ?? "none")
                    WebView(page)
                        .webViewBackForwardNavigationGestures(.enabled)
                        .webViewMagnificationGestures(.disabled)
                        .webViewLinkPreviews(.disabled)
                        .webViewTextSelection(.enabled)
                        .webViewContentBackground(.hidden)
                        .webViewElementFullscreenBehavior(.enabled)
                        .findNavigator(isPresented: $showFind)
                        .webViewScrollPosition($position)
                        .webViewOnScrollGeometryChange(for: Double.self, of: { $0.contentOffset.y }) { _, y in offset = y }
                    WebView(url: URL(string: "https://example.com"))
                        .frame(height: 100)
                    Text(answer)
                    Button("Back") {
                        if let item = page.backForwardList.backList.last { page.load(item) }
                    }
                    Button("Reload") { page.reload() }
                }
                .task {
                    page.load(html: "<title>Hi</title><p>Hello</p>")
                    do {
                        let value = try await page.callJavaScript("return 6 * 7")
                        answer = "\\(value ?? "")"
                    } catch {
                        answer = "failed"
                    }
                }
            }
        }
    }
    """

    func testTheWebAppChecksValidatesAndShows() {
        XCTAssertEqual(BridgeTest.problems(Self.app), [])
    }

    func testAPageLoadsHTMLAndRunsJavaScript() async throws {
        let (interp, value) = try await run("""
        import WebKit
        let page = WebPage()
        func main() async -> String {
            var events: [String] = []
            do {
                for try await event in page.load(html: "<title>Kiln</title><body><p id='p'>Hello</p></body>", baseURL: URL(string: "https://kiln.test/")!) {
                    events.append("\\(event)")
                }
            } catch {}
            let text = try? await page.callJavaScript("return document.getElementById('p').textContent")
            let sum = try? await page.callJavaScript("return a + b", arguments: ["a": 2, "b": 3])
            let list = try? await page.callJavaScript("return [1, 'two', true]")
            return "\\(page.title)|\\(page.isLoading)|\\(page.url?.host ?? "")|\\(events.last ?? "")|\\(text as? String ?? "")|\\(sum as? Int ?? 0)|\\((list as? [Any])?.count ?? 0)"
        }
        """, context("web-load"))
        XCTAssertEqual(interp.errors, [])
        XCTAssertEqual(value?.asString, "Kiln|false|kiln.test|.finished|Hello|5|3")
    }

    func testJavaScriptErrorsAreCaught() async throws {
        let (interp, value) = try await run("""
        import WebKit
        let page = WebPage()
        func main() async -> String {
            do { for try await _ in page.load(html: "<p>x</p>") {} } catch {}
            do {
                _ = try await page.callJavaScript("throw new Error('nope')")
                return "no error"
            } catch {
                return "caught"
            }
        }
        """, context("web-error"))
        XCTAssertEqual(interp.errors, [])
        XCTAssertEqual(value?.asString, "caught")
    }

    /// HTML loads make no history (natively too); the list reads as WebKit's.
    func testTheBackForwardListReads() async throws {
        let (interp, value) = try await run("""
        import WebKit
        let page = WebPage()
        func main() async -> String {
            do { for try await _ in page.load(html: "<title>One</title>", baseURL: URL(string: "https://kiln.test/one")!) {} } catch {}
            let list = page.backForwardList
            if let item = list.backList.last { page.load(item) }
            return "\\(list.backList.count) \\(list.forwardList.count) \\(list.currentItem?.url.absoluteString ?? "none")"
        }
        """, context("web-history"))
        XCTAssertEqual(interp.errors, [])
        XCTAssertEqual(value?.asString, "0 0 none")
    }

    /// Each app has its own store: a cookie one sets, another never sees.
    func testCookiesStayWithTheirApp() async throws {
        let a = context("web-a-\(UUID().uuidString.prefix(6))"), b = context("web-b-\(UUID().uuidString.prefix(6))")
        let set = """
        import WebKit
        let page = WebPage()
        func main() async -> String {
            do { for try await _ in page.load(html: "<p>x</p>", baseURL: URL(string: "https://kiln.test/")!) {} } catch {}
            let v = try? await page.callJavaScript("document.cookie = 'who=a; max-age=3600'; return document.cookie")
            return v as? String ?? ""
        }
        """
        let read = """
        import WebKit
        let page = WebPage()
        func main() async -> String {
            do { for try await _ in page.load(html: "<p>x</p>", baseURL: URL(string: "https://kiln.test/")!) {} } catch {}
            let v = try? await page.callJavaScript("return document.cookie")
            return v as? String ?? ""
        }
        """
        let (_, written) = try await run(set, a)
        XCTAssertEqual(written?.asString, "who=a")
        let (_, seen) = try await run(read, b)
        XCTAssertEqual(seen?.asString, "", "app B saw app A's cookie")
        let (_, again) = try await run(read, a)
        XCTAssertEqual(again?.asString, "who=a", "app A's cookie didn't stay in its store")

        XCTAssertEqual(KilnWebsiteData.identifier(for: "same"), KilnWebsiteData.identifier(for: "same"))
        XCTAssertNotEqual(KilnWebsiteData.identifier(for: "one"), KilnWebsiteData.identifier(for: "two"))
        XCTAssertTrue(KilnWebsiteData.store(for: a).isPersistent)
        XCTAssertFalse(KilnWebsiteData.store(for: KilnContext.stub()).isPersistent)
        let tryOut = context("web-try")
        tryOut.provide(KilnEphemeralWebsiteData())
        XCTAssertFalse(KilnWebsiteData.store(for: tryOut).isPersistent)

        a.tearDown(); b.tearDown()
        try await Task.sleep(for: .milliseconds(300))
        try await KilnWebsiteData.remove(for: a.slug)
        let ids = await WKWebsiteDataStore.allDataStoreIdentifiers
        XCTAssertFalse(ids.contains(KilnWebsiteData.identifier(for: a.slug)))
    }

    func testTeardownEmptiesThePage() async throws {
        let ctx = context("web-teardown")
        let (interp, _) = try await run("""
        import WebKit
        let page = WebPage()
        func main() async -> String {
            do { for try await _ in page.load(html: "<title>Open</title>", baseURL: URL(string: "https://kiln.test/")!) {} } catch {}
            return page.title
        }
        """, ctx)
        guard case .native(.object(_, let ref))? = interp.globalEnv.lookup("page")?.value, let page = ref.value as? WebPage else {
            return XCTFail("no page")
        }
        XCTAssertEqual(page.title, "Open")
        ctx.tearDown()
        let deadline = Date().addingTimeInterval(3)
        while page.title == "Open", Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNotEqual(page.url?.host(), "kiln.test")
    }

    /// A check never loads a web address.
    func testACheckNeverLoadsAWebAddress() async throws {
        let (interp, value) = try await run("""
        import WebKit
        let page = WebPage()
        func main() async -> String {
            var n = 0
            do { for try await _ in page.load(URL(string: "https://example.com")!) { n += 1 } } catch {}
            return "\\(n) \\(page.url == nil)"
        }
        """, .stub())
        XCTAssertEqual(interp.errors, [])
        XCTAssertEqual(value?.asString, "0 true")
    }
}
