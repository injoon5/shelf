import Foundation
import Kiln
import Testing
@testable import Shelf

/// The gate from the plan (§8.4): before anything depends on the `DB` prelude,
/// prove that Kiln's engine accepts it and that a `db://` request made by
/// interpreted code really reaches a `URLProtocol` on `URLSession.shared`.
@MainActor
@Suite(.serialized)
struct PreludeTests {
    @Test func kilnAcceptsThePreludeAndExample() throws {
        let source = SourceRewriter.prepare(try Fixture.app("todos-db"), slug: "todos-db")
        let result = Kiln.run(source)
        #expect(result.errors.isEmpty, "\(result.errors)")
        #expect(result.hasView)
    }

    @Test func interpretedCodeReachesTheDBScheme() throws {
        FakeServer.start(stored: ["todos": Data(#"[{"title":"Milk"}]"#.utf8)])
        defer { FakeServer.stop() }

        // The probe fires onAppear, which loads the stored list; that change saves it back.
        let source = SourceRewriter.prepare(try Fixture.app("todos-db"), slug: "todos-db")
        let validation = Kiln.validate(source)
        #expect(validation.errors.isEmpty, "\(validation.errors)")
        #expect(validation.hasView)

        let seen = FakeServer.seen
        #expect(seen.first.map { "\($0.method) \($0.path)" } == "GET /todos")
        let put = try #require(seen.first { $0.method == "PUT" && $0.path == "/todos" }, "\(seen.map { "\($0.method) \($0.path)" })")
        let saved = try #require(try JSONSerialization.jsonObject(with: put.body) as? [[String: Any]])
        // The stored item had only a title: the rest comes from the type's defaults.
        #expect(saved.first?["title"] as? String == "Milk")
        #expect(saved.first?["done"] as? Bool == false)
        #expect((saved.first?["id"] as? String).flatMap(UUID.init(uuidString:)) != nil)
    }
}
