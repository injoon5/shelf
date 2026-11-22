import Foundation

/// Gets an app's source ready to run: scopes its `@AppStorage` keys to the app
/// and adds the `DB` helper when the app uses it.
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
    /// is left alone, which is why this walks the source instead of running
    /// one regex over it.
    static func scopingAppStorage(in source: String, to slug: String) -> String {
        var scanner = Scanner(bytes: Array(source.utf8), prefix: Array((slug + ".").utf8))
        scanner.code(untilCloseParen: false)
        return String(decoding: scanner.out, as: UTF8.self)
    }

    private struct Scanner {
        let bytes: [UInt8]
        let prefix: [UInt8]
        var i = 0
        var out: [UInt8] = []

        private static let attribute = Array("@AppStorage".utf8)

        init(bytes: [UInt8], prefix: [UInt8]) {
            self.bytes = bytes
            self.prefix = prefix
            out.reserveCapacity(bytes.count + 64)
        }

        private func at(_ offset: Int = 0) -> UInt8? {
            i + offset < bytes.count ? bytes[i + offset] : nil
        }

        private func matches(_ text: [UInt8]) -> Bool {
            i + text.count <= bytes.count && bytes[i..<(i + text.count)].elementsEqual(text)
        }

        private mutating func take(_ count: Int = 1) {
            let end = min(i + count, bytes.count)
            out.append(contentsOf: bytes[i..<end])
            i = end
        }

        /// Copies code through to the end, or to the `)` that closes a string
        /// interpolation.
        mutating func code(untilCloseParen: Bool) {
            var depth = 0
            while let c = at() {
                switch c {
                case UInt8(ascii: "/") where at(1) == UInt8(ascii: "/"):
                    while let d = at(), d != UInt8(ascii: "\n") { _ = d; take() }
                case UInt8(ascii: "/") where at(1) == UInt8(ascii: "*"):
                    blockComment()
                case UInt8(ascii: "\""):
                    string()
                case UInt8(ascii: "#") where startsString():
                    string()
                case UInt8(ascii: "("):
                    depth += 1
                    take()
                case UInt8(ascii: ")"):
                    if untilCloseParen, depth == 0 { return }
                    depth -= 1
                    take()
                case UInt8(ascii: "@") where matches(Self.attribute) && !isIdentifier(at(Self.attribute.count)):
                    take(Self.attribute.count)
                    appStorageKey()
                default:
                    take()
                }
            }
        }

        private func isIdentifier(_ c: UInt8?) -> Bool {
            guard let c else { return false }
            return c == UInt8(ascii: "_") || (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c >= 128
        }

        private func isSpace(_ c: UInt8?) -> Bool {
            c == UInt8(ascii: " ") || c == UInt8(ascii: "\t") || c == UInt8(ascii: "\n") || c == UInt8(ascii: "\r")
        }

        /// After `@AppStorage`: `("key"` gets the prefix inside its quotes.
        private mutating func appStorageKey() {
            var j = i
            func skipSpace() { while j < bytes.count, isSpace(bytes[j]) { j += 1 } }
            skipSpace()
            guard j < bytes.count, bytes[j] == UInt8(ascii: "(") else { return }
            j += 1
            skipSpace()
            // A plain one-line literal only: not `"""`, not a raw string.
            guard j < bytes.count, bytes[j] == UInt8(ascii: "\""),
                  !(j + 2 < bytes.count && bytes[j + 1] == UInt8(ascii: "\"") && bytes[j + 2] == UInt8(ascii: "\"")) else { return }
            take(j + 1 - i)
            out.append(contentsOf: prefix)
        }

        private mutating func blockComment() {
            var depth = 0
            while at() != nil {
                if matches([UInt8(ascii: "/"), UInt8(ascii: "*")]) {
                    depth += 1
                    take(2)
                } else if matches([UInt8(ascii: "*"), UInt8(ascii: "/")]) {
                    depth -= 1
                    take(2)
                    if depth == 0 { return }
                } else {
                    take()
                }
            }
        }

        /// A `#` only matters when it opens a raw string: `#"…"#`.
        private func startsString() -> Bool {
            var j = i
            while j < bytes.count, bytes[j] == UInt8(ascii: "#") { j += 1 }
            return j < bytes.count && bytes[j] == UInt8(ascii: "\"")
        }

        private mutating func string() {
            var hashes = 0
            while at() == UInt8(ascii: "#") { hashes += 1; take() }
            let quote = UInt8(ascii: "\"")
            let isMultiline = at(1) == quote && at(2) == quote
            take(isMultiline ? 3 : 1)

            func closes(at j: Int) -> Bool {
                let quotes = isMultiline ? 3 : 1
                guard j + quotes + hashes <= bytes.count else { return false }
                for k in 0..<quotes where bytes[j + k] != quote { return false }
                for k in 0..<hashes where bytes[j + quotes + k] != UInt8(ascii: "#") { return false }
                return true
            }

            while let c = at() {
                if closes(at: i) {
                    take((isMultiline ? 3 : 1) + hashes)
                    return
                }
                if c == UInt8(ascii: "\\") {
                    // An escape needs the same number of `#` as the string has.
                    var j = i + 1
                    var seen = 0
                    while seen < hashes, j < bytes.count, bytes[j] == UInt8(ascii: "#") { seen += 1; j += 1 }
                    if seen == hashes {
                        take(j - i)
                        if at() == UInt8(ascii: "(") {
                            take()
                            code(untilCloseParen: true)
                            if at() == UInt8(ascii: ")") { take() }
                        } else if at() != nil {
                            take()
                        }
                        continue
                    }
                }
                if c == UInt8(ascii: "\n"), !isMultiline {
                    return   // an unterminated literal ends with its line
                }
                take()
            }
        }
    }
}
