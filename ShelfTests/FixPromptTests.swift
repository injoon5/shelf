import Foundation
import Testing
@testable import Shelf

/// Copy for Agents on the error screen: a prompt a coding agent can fix the
/// app with on its own. An installed app's is the change prompt with the
/// error as the change and an update key; a reply the New App sheet won't
/// install goes back with the sheet's own key; offline, or with no key,
/// the agent is asked to reply with the fixed file.
@MainActor
struct FixPromptTests {
    static let install = PromptsTests.install
    static let source = PromptsTests.source
    static let error = CompileError(errors: ["Line 13: Calendar.date isn't supported in Kiln"], source: source)

    // MARK: Pieces

    @Test func theReportIsTheLineTheCodeAroundItAndTheMessage() {
        #expect(Self.error.report == [
            "Line 13: Calendar.date isn't supported in Kiln",
            "",
            "  11 | ",
            "  12 | struct ContentView: View {",
            "> 13 |     @State private var habits: [Habit] = []",
            "  14 | ",
            "  15 |     var body: some View {",
        ].joined(separator: "\n"))
    }

    // MARK: An installed app

    @Test func anInstalledAppWithAnUpdateKey() {
        let prompt = Prompts.fixApp(Self.error.report, slug: "habits", source: Self.source, install: Self.install)
        #expect(prompt.hasPrefix("Change this Shelf app."))
        #expect(prompt.contains("""
            Change:
            Kiln stops this app with this error:

            ```text
            \(Self.error.report)
            ```

            Find the cause and fix it, using only what "What works" lists. Change nothing else.

            Current file:

            ```swift
            // Name: Habits
            """))
        #expect(prompt.contains("curl -sS -X PUT https://ij5.dev/api/apps/habits \\\n  -H \"Authorization: Bearer shelf_ik_abc_SECRET\""))
        #expect(prompt.contains("The key updates this one app, `habits`, once"))
        #expect(prompt.hasSuffix(Prompts.rules))
        PromptsTests.expectClean(prompt)
    }

    @Test func anInstalledAppWithNoKey() {
        let prompt = Prompts.fixApp(Self.error.report, slug: "habits", source: Self.source, install: nil)
        #expect(prompt.contains("Kiln stops this app with this error:"))
        #expect(prompt.contains("    @State private var habits: [Habit] = []"))
        #expect(prompt.contains("Reply with the whole updated file in one ```swift block"))
        #expect(!prompt.contains("curl"))
        #expect(!prompt.contains("Bearer"))
        PromptsTests.expectClean(prompt)
    }

    // MARK: A reply that can't be installed

    @Test func aNewAppsReplyWithTheSheetsInstallKey() {
        let prompt = Prompts.fixReply(Self.error.report, source: Self.source, slug: "habits", idea: "A habit tracker.\n",
                                      changing: false, install: Self.install)
        #expect(prompt.hasPrefix("Fix this Shelf app before it's installed."))
        #expect(prompt.contains("""
            Kiln finds this error in it, so Shelf won't install it:

            ```text
            \(Self.error.report)
            ```

            It was written for this request:
            A habit tracker.

            Find the cause and fix it
            """))
        #expect(prompt.contains("Current file:\n\n```swift\n// Name: Habits\n"))
        #expect(prompt.contains("## Installing"))
        #expect(prompt.contains("curl -sS -X PUT https://ij5.dev/api/apps/habits \\\n  -H \"Authorization: Bearer shelf_ik_abc_SECRET\""))
        #expect(prompt.contains("The key installs one new app."))
        #expect(prompt.hasSuffix(Prompts.rules))
        PromptsTests.expectClean(prompt)
    }

    @Test func aNewAppsReplyWithNoKey() {
        let prompt = Prompts.fixReply(Self.error.report, source: Self.source, slug: "habits", idea: "", changing: false, install: nil)
        #expect(!prompt.contains("It was written for this request"))
        #expect(prompt.contains("Reply with the whole fixed file in one ```swift block"))
        #expect(!prompt.contains("## Installing"))
        #expect(!prompt.contains("curl"))
        #expect(!prompt.contains("Bearer"))
        PromptsTests.expectClean(prompt)
    }

    @Test func aChangesReplyGoesBackAsTheChangeWithTheUpdateKey() {
        let prompt = Prompts.fixReply(Self.error.report, source: Self.source, slug: "habits", idea: "Add streaks.",
                                      changing: true, install: Self.install)
        #expect(prompt.hasPrefix("Change this Shelf app."))
        #expect(prompt.contains("Change:\nKiln finds this error in it, so Shelf won't install it:"))
        #expect(prompt.contains("It was written for this request:\nAdd streaks."))
        #expect(prompt.contains("The key updates this one app, `habits`, once"))
        PromptsTests.expectClean(prompt)
    }

    // MARK: The keys

    /// The sheet's own key goes in while online; offline it's left out,
    /// even though the sheet still holds it.
    @Test func theSheetsKeyOnlineAndNotOffline() async throws {
        let server = StubServer { _ in Self.liveKey }
        let library = Self.library(server)
        let model = CreateModel(app: nil, source: nil)
        await model.mint(library: library)
        model.paste(NewAppCheckTests.reply(#"Text("\(count)")"#), library: library)
        let error = CompileError(errors: ["Line 11: Something failed"], source: model.reply?.source ?? "")

        let online = model.fixPrompt(for: error, online: true)
        #expect(online.contains("/api/apps/tally \\\n  -H \"Authorization: Bearer shelf_ik_live_SECRET\""))
        #expect(online.contains("The key installs one new app."))
        #expect(online.contains("// Name: Tally"))

        let offline = model.fixPrompt(for: error, online: false)
        #expect(!offline.contains("curl"))
        #expect(!offline.contains("shelf_ik_live_SECRET"))
        #expect(offline.contains("Reply with the whole fixed file"))
    }

    /// An installed app's update key comes from the key ring while online,
    /// and not at all offline or signed out.
    @Test func anUpdateKeyOnlineAndNotOffline() async throws {
        let server = StubServer { request in
            request.path == "/api/install-keys" ? Self.liveKey : .json(#"{"status": "waiting"}"#)
        }
        let library = Self.library(server)
        let key = try #require(await library.updateKey(for: "habits", online: true))
        #expect(key.key == "shelf_ik_live_SECRET")
        #expect(server.requests.first?.json == .object(["slug": .string("habits")]))
        #expect(await library.updateKey(for: "habits", online: false) == nil)
        #expect(await LibraryStore(demo: [], cache: AppCache(root: temporaryFolder())).updateKey(for: "habits", online: true) == nil)

        // The runner's Copy for Agents asks the host for it.
        let install = await library.host.fixKey("habits")
        #expect(install?.key == "shelf_ik_live_SECRET")
    }

    /// A key an agent has used since it was handed out isn't handed out
    /// again: the key ring asks the server, and mints a new one.
    @Test func aUsedKeyIsNotHandedOutAgain() async throws {
        let used = Locked(false)
        let mints = Locked(0)
        let server = StubServer { request in
            if request.path == "/api/install-keys" {
                mints.withLock { $0 += 1 }
                return mints.value == 1 ? Self.liveKey : Self.key("shelf_ik_next_SECRET", id: "next")
            }
            return used.value ? .json(#"{"status": "used", "slug": "habits"}"#) : .json(#"{"status": "waiting"}"#)
        }
        let library = Self.library(server)
        #expect(await library.updateKey(for: "habits", online: true)?.key == "shelf_ik_live_SECRET")
        #expect(await library.updateKey(for: "habits", online: true)?.key == "shelf_ik_live_SECRET")
        used.withLock { $0 = true }
        #expect(await library.updateKey(for: "habits", online: true)?.key == "shelf_ik_next_SECRET")
        #expect(mints.value == 2)
    }

    // MARK: Helpers

    nonisolated static var liveKey: StubResponse { key("shelf_ik_live_SECRET", id: "live") }

    nonisolated static func key(_ key: String, id: String) -> StubResponse {
        let expires = Int((Date.now.timeIntervalSince1970 + 3600) * 1000)
        return .json(#"{"key": "\#(key)", "id": "\#(id)", "expires_at": \#(expires)}"#, status: 201)
    }

    static func library(_ server: StubServer) -> LibraryStore {
        let folder = temporaryFolder()
        let api = server.api()
        return LibraryStore(cache: AppCache(root: folder.appending(path: "apps")),
                            data: AppData(root: folder.appending(path: "data"), api: { nil }),
                            layoutURL: folder.appending(path: "layout.json"),
                            server: { api })
    }
}

extension FixPromptTests {
    /// The screen shows each line's indent apart, less what they share and
    /// halved; the report keeps the lines as they are.
    @Test func theScreenSetsTheIndentApart() {
        let source = "struct A {\n    var body: some View {\n        Text(x)\n\n\tText(y)\n    }\n}"
        let error = CompileError(errors: ["Line 3: x"], source: source)
        #expect(error.shownExcerpt.map(\.text) == ["struct A {", "var body: some View {", "Text(x)", "", "Text(y)"])
        #expect(error.shownExcerpt.map(\.indent) == [0, 2, 4, 0, 2])
        let inner = CompileError(errors: ["Line 3: x"], source: "    a\n        b\n            c\n        d\n    e")
        #expect(inner.shownExcerpt.map(\.indent) == [0, 2, 4, 2, 0])
        #expect(error.report.contains("> 3 |         Text(x)"))
    }
}

extension FixPromptTests {
    /// Code may wrap after `(` and a member's `.`, never inside `.now`.
    @Test func codeBreaksWhereCodeDoes() {
        let zw = "\u{200B}"
        #expect(ErrorScreen.breakable("a.b(of: .now)") == "a.\(zw)b(\(zw)of: .now)")
        #expect(ErrorScreen.breakable("f().g[0].h") == "f(\(zw)).\(zw)g[0].\(zw)h")
    }
}
