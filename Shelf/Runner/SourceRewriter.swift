import Foundation

/// Gets an app's source ready to run: scopes its `@AppStorage` keys to the app
/// (`AppStorageKeys`) and adds the `DB` helper when the app uses it.
///
/// The key rewrite stops two apps that both store `"count"` from overwriting
/// each other. It is not a security boundary: Kiln hands apps
/// `UserDefaults.standard`, so an app that spells out another app's key can
/// still reach it. Nothing of Shelf's own lives there for that reason.
enum SourceRewriter {
    static func prepare(_ source: String, slug: String) -> String {
        var prepared = scopingAppStorage(in: source, to: slug)
        if needsPrelude(source) {
            // Appended, not prepended, so the line numbers in an error still
            // match the author's file.
            prepared += "\n\n" + Prelude.db + "\n"
        }
        return prepared
    }

    /// Whether the app calls `DB` without bringing its own.
    static func needsPrelude(_ source: String) -> Bool {
        source.contains("DB.") && source.range(of: #"\b(enum|struct|class)\s+DB\b"#, options: .regularExpression) == nil
    }

    /// `@AppStorage("key")` becomes `@AppStorage("<slug>.key")`, wherever the
    /// attribute is real code. The same text in a comment or inside a string
    /// is left alone, which is why this reads the source as Swift instead of
    /// running one regex over it.
    static func scopingAppStorage(in source: String, to slug: String) -> String {
        let text = SwiftText(source)
        let s = text.scalars
        let scope = AppStorageKeys.scope(slug).unicodeScalars
        var out = String.UnicodeScalarView()
        var i = 0
        while i < s.count {
            if text.isCode(i), let quote = keyQuote(in: s, at: i) {
                out.append(contentsOf: s[i...quote])
                out.append(contentsOf: scope)
                i = quote + 1
            } else {
                out.append(s[i])
                i += 1
            }
        }
        return String(out)
    }

    private static let attribute = Array("@AppStorage".unicodeScalars)

    /// Where the key's opening quote is, when an `@AppStorage(` with a plain
    /// one-line literal key (not `"""`, not a raw string) starts at `i`.
    private static func keyQuote(in s: [Unicode.Scalar], at i: Int) -> Int? {
        var j = i + attribute.count
        guard s[i...].starts(with: attribute), !(j < s.count && SwiftText.isIdentifier(s[j])) else { return nil }
        func skipSpace() { while j < s.count, [" ", "\t", "\n", "\r"].contains(s[j]) { j += 1 } }
        skipSpace()
        guard j < s.count, s[j] == "(" else { return nil }
        j += 1
        skipSpace()
        guard j < s.count, s[j] == "\"", !(j + 2 < s.count && s[j + 1] == "\"" && s[j + 2] == "\"") else { return nil }
        return j
    }
}
