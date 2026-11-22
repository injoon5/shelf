import Foundation
import Kiln
import Testing
@testable import Shelf

/// The gate from the plan (§8.4): Kiln's engine accepts the `DB` prelude.
/// That a `db://` request made by interpreted code really reaches Shelf's
/// protocol is `ShelfDBProtocolTests.kilnRoundTripsThroughARealSession`.
@MainActor
@Suite(.serialized)
struct PreludeTests {
    @Test func kilnAcceptsThePreludeAndExample() throws {
        let source = SourceRewriter.prepare(try Fixture.app("todos-db"), slug: "todos-db")
        let result = Kiln.run(source)
        #expect(result.errors.isEmpty, "\(result.errors)")
        #expect(result.hasView)
    }
}
