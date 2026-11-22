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
        let source = self.source(from: reply)
        let header = self.header(of: source)
        let name = header["name"].flatMap(nonEmpty)
        return ParsedReply(
            name: name,
            icon: header["icon"].flatMap(nonEmpty),
            tint: header["tint"].flatMap { Tint(rawValue: $0.lowercased()) } ?? .blue,
            slug: name.map(slug(from:)) ?? "app",
            source: source
        )
    }

    /// The slug a name suggests, by the same rule `parse` uses (rule 11).
    static func slug(from name: String) -> String {
        let folded = String(String.UnicodeScalarView(
            name.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !isMark($0) }
        )).lowercased()
        var slug = ""
        var inRun = false
        for scalar in folded.unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                slug.unicodeScalars.append(scalar)
                inRun = false
            } else if !inRun {
                slug.append("-")
                inRun = true
            }
        }
        slug = String(trimmingHyphens(slug).prefix(64))
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "app" : slug
    }

    // MARK: - Rules 1–6: the source

    /// The Swift to store: the reply's Swift blocks, or the whole reply when it
    /// has none, with blank lines trimmed from both ends.
    static func source(from reply: String) -> String {
        let lines = normalized(reply).components(separatedBy: "\n")
        var blocks: [[String]] = []
        var current: [String]? = nil
        var currentIsSwift = false
        for line in lines {
            let isFence = hasPrefix(trimmed(line), "```")
            if current != nil {
                if isFence {
                    if currentIsSwift { blocks.append(current!) }
                    current = nil
                } else {
                    current!.append(line)
                }
            } else if isFence {
                let info = trimmed(String(trimmed(line).unicodeScalars.drop { $0 == "`" }))
                currentIsSwift = hasPrefix(info.lowercased(), "swift")
                current = []
            }
        }
        if let open = current, currentIsSwift { blocks.append(open) }

        let body = blocks.isEmpty ? lines : blocks.map { $0.joined(separator: "\n") }.joined(separator: "\n\n").components(separatedBy: "\n")
        guard let first = body.firstIndex(where: { !isBlank($0) }),
              let last = body.lastIndex(where: { !isBlank($0) }) else { return "" }
        return body[first...last].joined(separator: "\n") + "\n"
    }

    /// Rule 1: no byte-order mark and no `\r`.
    static func normalized(_ text: String) -> String {
        var scalars = text.unicodeScalars[...]
        if scalars.first == "\u{FEFF}" { scalars = scalars.dropFirst() }
        var out = String.UnicodeScalarView()
        var previousWasCR = false
        for scalar in scalars {
            if scalar == "\r" {
                out.append("\n")
                previousWasCR = true
                continue
            }
            if scalar == "\n" && previousWasCR {
                previousWasCR = false
                continue
            }
            previousWasCR = false
            out.append(scalar)
        }
        return String(out)
    }

    // MARK: - Rules 7–10: the header

    /// The first value of each header key, read from the comment lines at the top.
    static func header(of source: String) -> [String: String] {
        var found: [String: String] = [:]
        for line in source.components(separatedBy: "\n") {
            if isBlank(line) { continue }
            guard hasPrefix(trimmed(line), "//") else { break }
            if let (key, value) = headerLine(line), found[key] == nil { found[key] = value }
        }
        return found
    }

    /// `^\s*//\s*(name|icon|tint)\s*:\s*(.*?)\s*$`, case-insensitively, as
    /// JavaScript reads it: `.` doesn't match U+2028 or U+2029.
    static func headerLine(_ line: String) -> (String, String)? {
        var rest = Substring(line).unicodeScalars.drop(while: isSpace)
        guard rest.starts(with: "//".unicodeScalars) else { return nil }
        rest = rest.dropFirst(2).drop(while: isSpace)
        let key = String(String.UnicodeScalarView(rest.prefix(4))).lowercased()
        guard ["name", "icon", "tint"].contains(key), rest.count >= 4,
              rest.prefix(4).allSatisfy(\.isASCII) else { return nil }
        rest = rest.dropFirst(4).drop(while: isSpace)
        guard rest.first == ":" else { return nil }
        let value = trimmed(String(String.UnicodeScalarView(rest.dropFirst())))
        if value.unicodeScalars.contains(where: { $0 == "\u{2028}" || $0 == "\u{2029}" }) { return nil }
        return (key, value)
    }

    // MARK: - Text helpers, with JavaScript's idea of whitespace

    /// What `\s` and `String.prototype.trim` treat as whitespace.
    static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    static func trimmed(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let start = scalars.firstIndex(where: { !isSpace($0) }),
              let end = scalars.lastIndex(where: { !isSpace($0) }) else { return "" }
        return String(scalars[start...end])
    }

    static func isBlank(_ line: String) -> Bool {
        line.unicodeScalars.allSatisfy(isSpace)
    }

    /// By scalars, as JavaScript compares: `"```\u{301}"` starts with three backticks.
    static func hasPrefix(_ text: String, _ prefix: String) -> Bool {
        text.unicodeScalars.starts(with: prefix.unicodeScalars)
    }

    static func nonEmpty(_ text: String) -> String? {
        let t = trimmed(text)
        return t.isEmpty ? nil : t
    }

    static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    static func trimmingHyphens(_ text: String) -> String {
        var s = Substring(text)
        while s.hasPrefix("-") { s = s.dropFirst() }
        while s.hasSuffix("-") { s = s.dropLast() }
        return String(s)
    }
}
