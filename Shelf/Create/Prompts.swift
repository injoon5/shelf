import Foundation

/// The prompts Shelf copies (plan §9.1 and the Appendix), filled in from the
/// templates in `Resources/Prompts`.
enum Prompts {
    /// The one-time key that lets an agent install the app itself.
    struct Install: Equatable, Sendable {
        /// The site, with no trailing slash: `https://ij5.dev`.
        var origin: String
        var key: String
        var expires: Date
    }

    /// The new-app prompt. Without `install` (offline, no key) the Installing
    /// section is left out and the rest still works by paste.
    static func newApp(idea: String, install: Install?) -> String {
        var values = installValues(install)
        values["IDEA"] = idea
        return fill(template("new"), install: install != nil, values)
    }

    /// The change prompt. `includeSource` picks the full source or the outline.
    static func change(_ change: String, slug: String, source: String, includeSource: Bool, install: Install?) -> String {
        var values = installValues(install)
        values["SLUG"] = slug
        let current = includeSource
            ? fill(template("current-source"), install: install != nil, ["SOURCE": trimmingTrailingNewlines(source)])
            : fill(template("current-outline"), install: install != nil, values.merging(["OUTLINE": trimmingTrailingNewlines(Outline.make(from: source))]) { $1 })
        values["CHANGE"] = change
        values["CURRENT"] = current
        values["RULES"] = rules
        return fill(template("edit"), install: install != nil, values)
    }

    // MARK: - Templates

    /// Everything in the new-app prompt from "## What works" to the end: the
    /// rules the change prompt repeats as `{{RULES}}`.
    static var rules: String {
        let new = template("new")
        guard let start = new.range(of: "## What works") else { return "" }
        return fill(String(new[start.lowerBound...]), install: false, [:])
    }

    /// Where the templates are: the app's bundle, found through a type in the
    /// app so tests (whose main bundle differs) read the same files.
    static let bundle = Bundle(for: BundleAnchor.self)
    private final class BundleAnchor {}

    static func template(_ name: String) -> String {
        guard let folder = bundle.url(forResource: "Prompts", withExtension: nil),
              let text = try? String(contentsOf: folder.appending(path: "\(name).md"), encoding: .utf8) else {
            assertionFailure("Prompts/\(name).md is missing from the bundle")
            return ""
        }
        return text
    }

    /// `{{EXPIRES}}`: the local time the key stops working, as "3:42 PM".
    static func expiresText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    static func installValues(_ install: Install?) -> [String: String] {
        guard let install else { return [:] }
        return ["ORIGIN": install.origin, "KEY": install.key, "EXPIRES": expiresText(install.expires)]
    }

    // MARK: - Filling

    /// Fills a template in two steps, so text the user wrote is never read as
    /// template syntax:
    ///
    /// 1. Sections: the lines between `<!-- if install -->` and `<!-- else -->`
    ///    (or `<!-- end -->`) are kept only with a key; the `else` lines only
    ///    without one. The marker lines go. Runs of blank lines left behind
    ///    become one, and the result is trimmed of blank lines at both ends.
    /// 2. Placeholders: one pass from left to right replaces each `{{NAME}}`
    ///    with its value as it is. A value is never scanned again, so an idea
    ///    that says "{{KEY}}" stays that way. An unknown name is left alone.
    static func fill(_ template: String, install: Bool, _ values: [String: String]) -> String {
        substitute(sections(template, install: install), values)
    }

    static func sections(_ template: String, install: Bool) -> String {
        enum Branch { case always, ifInstall, elseInstall }
        var branch = Branch.always
        var kept: [String] = []
        for line in template.components(separatedBy: "\n") {
            switch line.trimmingCharacters(in: .whitespaces) {
            case "<!-- if install -->": branch = .ifInstall; continue
            case "<!-- else -->": branch = .elseInstall; continue
            case "<!-- end -->": branch = .always; continue
            default: break
            }
            switch branch {
            case .always: break
            case .ifInstall: if !install { continue }
            case .elseInstall: if install { continue }
            }
            let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if blank && (kept.last?.isEmpty ?? true) { continue }
            kept.append(blank ? "" : line)
        }
        while kept.last?.isEmpty == true { kept.removeLast() }
        return kept.joined(separator: "\n")
    }

    static func substitute(_ template: String, _ values: [String: String]) -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.range(of: "{{") {
            out += rest[..<open.lowerBound]
            let after = rest[open.upperBound...]
            if let close = after.range(of: "}}"), let value = values[String(after[..<close.lowerBound])] {
                out += value
                rest = after[close.upperBound...]
            } else {
                out += "{{"
                rest = after
            }
        }
        out += rest
        return out
    }

    /// A source or outline goes inside a code fence, which supplies the line break.
    static func trimmingTrailingNewlines(_ text: String) -> String {
        var text = Substring(text)
        while text.hasSuffix("\n") { text = text.dropLast() }
        return String(text)
    }
}
