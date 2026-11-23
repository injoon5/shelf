import Foundation

/// The prompt's "What works" and "What doesn't work", built from Kiln's
/// `kiln-manifest.json` (plan §7, §1.8), which is bundled with the app.
///
/// The manifest is the one record of what Kiln runs: every symbol with its
/// family, its support (`full`, `partial`, `stub`) and notes for authors,
/// the families with nothing yet, the Swift that fails today (each a probe
/// Kiln runs when it writes the manifest), and the won't-do list. So the
/// prompt can't promise what Kiln doesn't run, and a gap Kiln closes leaves
/// "What doesn't work" when the manifest is next written.
///
/// What's written by hand stays in `Resources/Prompts/new.md`: the reply
/// format, Swift itself, waiting, saving data and design.
enum PromptCatalog {
    struct Manifest: Decodable {
        struct Family: Decodable {
            var name: String
            var summary: String
            var supported: Int
            var stubs: Int
            /// "What works" in one line, written by Kiln for a family that's
            /// nearly all of SwiftUI's; nil lists the family's names.
            var line: String?
        }
        struct Gap: Decodable {
            var id: String
            var what: String
        }
        struct WontDo: Decodable {
            var id: String
            var what: String
            var reason: String
            var status: String
        }
        struct Symbol: Decodable {
            var id: String
            var kind: String
            var name: String
            var owner: String?
            var family: String
            var support: String
            var notes: String?
            /// A protocol the app's own types adopt and native code calls through (§1.5).
            var proxy: Bool?
        }
        var families: [Family]
        var gaps: [Gap]
        var wontDo: [WontDo]
        var symbols: [Symbol]
    }

    /// The bundled manifest.
    static let manifest: Manifest? = {
        guard let url = Prompts.bundle.url(forResource: "kiln-manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("kiln-manifest.json is missing from the bundle")
            return nil
        }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }()

    /// Families the prompt doesn't list by symbol: the language has its own
    /// hand-written part, and a Shelf app has no scene of its own.
    static let unlisted: Set<String> = ["Language", "Scenes", "Host"]
    /// Families that aren't SwiftUI: their types are what an author names.
    static let typeFamilies: Set<String> = ["Foundation", "Networking", "Concurrency", "Units"]

    /// The families "What works" lists, each with its symbols.
    static func listedFamilies(_ m: Manifest) -> [Manifest.Family] {
        m.families.filter { $0.supported > 0 && !unlisted.contains($0.name) }
    }

    // MARK: - What works

    /// One line per family: its views, property wrappers, environment
    /// values, types and modifiers, then the notes an author needs.
    static func whatWorks(_ m: Manifest? = manifest) -> String {
        guard let m else { return "" }
        var out: [String] = []
        for f in listedFamilies(m) {
            let working = m.symbols.filter { $0.family == f.name && $0.support != "stub" }
            if let line = f.line {
                out.append("- **\(f.name):** \(line).")
                for note in notes(working) { out.append("  - \(note)") }
                continue
            }
            var groups: [[String]] = []
            groups.append(names(working.filter { ["view", "content", "gesture"].contains($0.kind) }))
            groups.append(names(working.filter { $0.kind == "wrapper" }))
            groups.append(names(working.filter { $0.kind == "environment" }))
            let types = working.filter { s in
                s.kind == "type" && !isAlias(s) && (typeFamilies.contains(f.name) || s.notes != nil)
            }
            groups.append(names(types))
            groups.append(names(working.filter { $0.kind == "modifier" }))
            // `Shape`, `Layout`, a delegate: protocols the app's own types adopt (PLAN.md §1.5).
            groups.append(names(working.filter { $0.kind == "protocol" && $0.proxy == true }).map { "your own " + $0 })
            let line = groups.filter { !$0.isEmpty }.map { $0.joined(separator: ", ") }.joined(separator: "; ")
            guard !line.isEmpty else { continue }
            out.append("- **\(f.name):** \(line).")
            for note in notes(working) { out.append("  - \(note)") }
        }
        return out.joined(separator: "\n")
    }

    /// "`Button`", "`.padding`", "`@State`", "`\.dismiss`", sorted and once each.
    static func names(_ symbols: [Manifest.Symbol]) -> [String] {
        var seen = Set<String>()
        return symbols.map(display).filter { seen.insert($0).inserted }.sorted { $0.lowercased() < $1.lowercased() }
    }

    static func display(_ s: Manifest.Symbol) -> String {
        switch s.kind {
        case "modifier": return "`.\(s.name)`"
        case "wrapper": return "`@\(s.name)`"
        case "environment": return "`\\.\(s.name)`"
        case "member": return "`\(s.owner.map { $0 + "." } ?? "")\(s.name)`"
        default: return "`\(s.name)`"
        }
    }

    static func isAlias(_ s: Manifest.Symbol) -> Bool { s.notes?.hasPrefix("The same as") == true }

    /// "`List`: rows, sections…", one per note of a symbol that works only in
    /// part (what works fully needs no note in a prompt), or of a protocol the
    /// app's types adopt (its note says how); names that share a note share its line.
    static func notes(_ symbols: [Manifest.Symbol]) -> [String] {
        var order: [String] = []
        var byNote: [String: [String]] = [:]
        for s in symbols where s.kind != "style" && !isAlias(s)
            && (s.kind == "protocol" ? s.proxy == true : s.support == "partial") {
            guard let note = s.notes?.trimmingCharacters(in: .whitespaces), !note.isEmpty else { continue }
            if byNote[note] == nil { order.append(note) }
            let d = display(s)
            if byNote[note]?.contains(d) != true { byNote[note, default: []].append(d) }
        }
        return order.map { note in
            let who = byNote[note]!.sorted()
            return (who.count <= 3 ? who.joined(separator: ", ") : who.prefix(2).joined(separator: ", ") + " and the like") + ": " + note
        }
        .sorted { $0.lowercased() < $1.lowercased() }
    }

    // MARK: - What doesn't work

    static func whatDoesntWork(_ m: Manifest? = manifest) -> String {
        guard let m else { return "" }
        var out: [String] = []
        let missing = m.families.filter { $0.supported == 0 && !unlisted.contains($0.name) }
        if !missing.isEmpty {
            out.append("- Not in Kiln yet: " + missing.map { "\($0.summary) (\($0.name))" }.joined(separator: "; ") + ".")
        }
        let stubs = m.symbols.filter { $0.support == "stub" && $0.kind != "member" }
        if !stubs.isEmpty {
            out.append("- Accepted, but they do nothing yet: " + names(stubs).joined(separator: ", ") + ".")
            for s in stubs where ["view", "type"].contains(s.kind) && s.notes != nil {
                if let note = s.notes, note.contains(":") || note.lowercased().contains("instead") {
                    out.append("  - \(display(s)): \(note)")
                }
            }
        }
        for g in m.gaps { out.append("- \(g.what)") }
        let wontDo = m.wontDo.filter { $0.status == "wontDo" }.map { short($0.what) }
        if !wontDo.isEmpty { out.append("- Never: " + wontDo.joined(separator: "; ") + ".") }
        let later = m.wontDo.filter { $0.status == "later" }.map { short($0.what) }
        if !later.isEmpty { out.append("- Not planned yet: " + later.joined(separator: "; ") + ".") }
        return out.joined(separator: "\n")
    }

    /// A won't-do entry without its examples: "MapKit views (`Map`, …)" → "MapKit views".
    static func short(_ what: String) -> String {
        what.replacing(#/ \([^)]*\)/#, with: "")
    }
}
