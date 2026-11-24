//
//  KilnCorpus.swift
//  Kiln's bridge registry
//
//  The Foundation and standard-library corpus (PLAN.md §3, Round 2C): a few
//  hundred everyday calls, each with the value compiled Swift prints. It's
//  `Tests/Corpus/<Family>.corpus`; `CorpusTests` runs every entry, the
//  manifest records which pass (`corpus`), and the coverage report counts
//  Foundation and the standard library against it.
//
//  The format, one entry per call:
//
//      ## Dates                                   a section
//      Calendar.date(from:) :: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 2))! => 2026-01-02 05:00:00 +0000
//
//      Sequence conformance ::                    several lines of code, indented
//          struct Count: Sequence, IteratorProtocol { … }
//          print(Count().map(String.init).joined())
//      => 123                                     one `=>` line per line printed
//
//  - The id before `::` names what the entry checks (the symbol and its form).
//  - One line of code that doesn't call `print` is printed: `print(<code>)`.
//  - Flags in brackets after the id: `[ios]` (UIKit, so Tools/corpus/oracle.py
//    can't run it on the Mac: the value is written by hand), `[gap]` (doesn't
//    work in Kiln yet: listed as missing, and its test expects it to fail).
//  - `prelude ::` is code every entry in its file starts with.
//  - Every entry runs with the time zone America/New_York and the en_US
//    locale, as the oracle runs compiled Swift.
//

import Foundation

@_spi(KilnTesting) public struct KilnCorpusEntry: Sendable {
    public let family: String
    public let section: String
    public let id: String
    public let code: String
    public let expected: [String]
    public let flags: Set<String>
    public let line: Int

    public var isGap: Bool { flags.contains("gap") }

    /// The entry's code as an app: a view to show, and the code at the top level.
    public var source: String {
        KilnCorpus.imports + code + "\n\nstruct ContentView: View { var body: some View { Text(\"corpus\") } }\n"
    }
}

@_spi(KilnTesting) public enum KilnCorpus {
    public static let imports = "import SwiftUI\nimport Foundation\nimport Combine\nimport CryptoKit\nimport OSLog\n\n"
    public static let timeZone = "America/New_York"

    /// The entries of one `.corpus` file; `family` is its name.
    public static func parse(_ text: String, family: String) -> [KilnCorpusEntry] {
        var out: [KilnCorpusEntry] = []
        var section = ""
        let lines = text.components(separatedBy: "\n")
        var i = 0
        func header(_ s: Substring) -> (String, Set<String>) {
            var id = s.trimmingCharacters(in: .whitespaces)
            var flags = Set<String>()
            while id.hasSuffix("]"), let open = id.lastIndex(of: "[") {
                flags.insert(String(id[id.index(after: open)..<id.index(before: id.endIndex)]))
                id = id[..<open].trimmingCharacters(in: .whitespaces)
            }
            return (id, flags)
        }
        while i < lines.count {
            let raw = lines[i]
            let t = raw.trimmingCharacters(in: .whitespaces)
            i += 1
            if t.isEmpty || (t.hasPrefix("#") && !t.hasPrefix("##")) { continue }
            if t.hasPrefix("##") { section = t.dropFirst(2).trimmingCharacters(in: .whitespaces); continue }
            guard let sep = raw.range(of: " ::") else { continue }
            let (id, flags) = header(raw[..<sep.lowerBound])
            let start = i
            var rest = raw[sep.upperBound...].trimmingCharacters(in: .whitespaces)
            var expected: [String] = []
            var code: String
            if rest.isEmpty {
                var body: [String] = []
                while i < lines.count, lines[i].hasPrefix("    ") || lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    if lines[i].hasPrefix("=>") { break }
                    body.append(String(lines[i].dropFirst(min(4, lines[i].count))))
                    i += 1
                }
                while body.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { body.removeLast() }
                code = body.joined(separator: "\n")
            } else {
                if let arrow = rest.range(of: " => ", options: .backwards) ?? (rest.hasSuffix(" =>") ? rest.range(of: " =>", options: .backwards) : nil) {
                    expected.append(String(rest[arrow.upperBound...]))
                    rest = String(rest[..<arrow.lowerBound])
                }
                code = rest.contains("print(") ? rest : "print(\(rest))"
            }
            while i < lines.count, lines[i].hasPrefix("=>") {
                var e = String(lines[i].dropFirst(2))
                if e.hasPrefix(" ") { e.removeFirst() }
                expected.append(e)
                i += 1
            }
            out.append(KilnCorpusEntry(family: family, section: section, id: id, code: code, expected: expected,
                                       flags: flags, line: start))
        }
        // `prelude ::` is code every entry in the file starts with (a reference date).
        if let prelude = out.first(where: { $0.id == "prelude" }) {
            out = out.filter { $0.id != "prelude" }.map { e in
                KilnCorpusEntry(family: e.family, section: e.section, id: e.id, code: prelude.code + "\n" + e.code,
                                expected: e.expected, flags: e.flags, line: e.line)
            }
        }
        return out
    }

    /// Every `.corpus` file in `folder`, by name.
    public static func load(_ folder: URL) -> [KilnCorpusEntry] {
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "corpus" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return files.flatMap { url in
            parse((try? String(contentsOf: url, encoding: .utf8)) ?? "", family: url.deletingPathExtension().lastPathComponent)
        }
    }

    /// What an entry prints in Kiln: its console lines, then `error: …` for
    /// each error (the check's, or the run's).
    @MainActor public static func run(_ entry: KilnCorpusEntry) -> [String] {
        let saved = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: timeZone)!
        defer { NSTimeZone.default = saved }
        let source = entry.source
        let check = Kiln.check(source)
        let context = KilnContext.stub()
        var errors: [String] = check.errors.map { "check: " + $0.message }
        context.onError = { errors.append($0.message) }
        Kiln.randomSeed = 1
        let result = Kiln.run(source, context: context)
        defer { result.tearDown(); Kiln.randomSeed = nil }
        var lines = result.consoleOutput.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        var seen = Set<String>()
        for e in result.errors + errors where seen.insert(e).inserted { lines.append("error: " + e) }
        return lines
    }

    /// Whether an entry prints what compiled Swift prints.
    @MainActor public static func passes(_ entry: KilnCorpusEntry) -> Bool {
        run(entry) == entry.expected
    }
}
