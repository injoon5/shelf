import Foundation

/// What a pasted reply (or a raw Swift file) turns into.
struct ParsedReply: Equatable, Sendable {
    /// From `// Name:`. Nil when the line is missing or empty.
    var name: String?
    /// From `// Icon:`, as written. Whether it is a real SF Symbol is the caller's check.
    var icon: String?
    /// From `// Tint:`. Missing or unknown is blue.
    var tint: Tint
    /// Made from the name. `"app"` when the name has nothing usable.
    var slug: String
    /// The Swift to store and run, header lines included.
    var source: String
}

/// Reads a chat reply into an app. The rules are in `fixtures/replies/README.md`;
/// the admin's TypeScript copy follows the same file, and both are tested
/// against the same fixtures.
///
/// CONTRACT — signatures are fixed; bodies belong to the Create package.
enum ReplyParser {
    static func parse(_ reply: String) -> ParsedReply {
        ParsedReply(name: nil, icon: nil, tint: .blue, slug: "app", source: reply)
    }

    /// The slug a name suggests, by the same rule `parse` uses.
    static func slug(from name: String) -> String { "app" }
}
