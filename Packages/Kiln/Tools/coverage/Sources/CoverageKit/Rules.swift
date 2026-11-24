// The checked-in rules: families.json (which family each symbol belongs to, and
// which symbols are compiler plumbing nobody writes) and wont-do.json (what Kiln
// deliberately leaves out, each with a one-line reason).

import Foundation

/// Picks symbols. Every field given must match; within a field, any value may.
public struct SymbolMatcher: Codable, Equatable, Sendable {
    public var ids: [String]?
    /// Regular expressions over the id (`^modifier:Scene\.`).
    public var idPatterns: [String]?
    public var kinds: [SymbolKind]?
    public var modules: [String]?
    /// Exact names (`padding`, `DatePicker`).
    public var names: [String]?
    /// Regular expressions over the name (`^accessibility`).
    public var patterns: [String]?
    public var owners: [String]?
    public var conformsTo: [String]?
    /// Modifiers whose every overload is on one of these receivers (`Scene`, `Commands`).
    public var receiversOnly: [String]?
    /// Families from families.json. Only won't-do entries can use this (families are decided first).
    public var families: [String]?
    /// Ids never matched, even if the rest does.
    public var except: [String]?

    public init(ids: [String]? = nil, idPatterns: [String]? = nil, kinds: [SymbolKind]? = nil, modules: [String]? = nil,
                names: [String]? = nil, patterns: [String]? = nil, owners: [String]? = nil, conformsTo: [String]? = nil,
                receiversOnly: [String]? = nil, families: [String]? = nil, except: [String]? = nil) {
        self.ids = ids; self.idPatterns = idPatterns; self.kinds = kinds; self.modules = modules; self.names = names
        self.patterns = patterns; self.owners = owners; self.conformsTo = conformsTo; self.receiversOnly = receiversOnly
        self.families = families; self.except = except
    }

    public var isEmpty: Bool {
        ids == nil && idPatterns == nil && kinds == nil && modules == nil && names == nil && patterns == nil
            && owners == nil && conformsTo == nil && receiversOnly == nil && families == nil
    }

    public func matches(_ s: SDKSymbol, family: String? = nil) -> Bool {
        if isEmpty { return false }
        if let v = families, !v.contains(family ?? "") { return false }
        if let e = except, e.contains(s.id) { return false }
        if let v = ids, !v.contains(s.id) { return false }
        if let v = idPatterns, !v.contains(where: { Regex.matches($0, s.id) }) { return false }
        if let v = kinds, !v.contains(s.kind) { return false }
        if let v = modules, !v.contains(s.module) { return false }
        if let v = names, !v.contains(s.name) { return false }
        if let v = patterns, !v.contains(where: { Regex.matches($0, s.name) }) { return false }
        if let v = owners, !v.contains(s.owner ?? "") { return false }
        if let v = conformsTo, !v.contains(s.conformsTo ?? "") { return false }
        if let v = receiversOnly {
            let rs = s.overloads.compactMap(\.receiver)
            if rs.isEmpty || !rs.allSatisfy({ v.contains($0) }) { return false }
        }
        return true
    }
}

enum Regex {
    nonisolated(unsafe) static var cache: [String: NSRegularExpression] = [:]
    static let lock = NSLock()

    static func matches(_ pattern: String, _ s: String) -> Bool {
        lock.lock()
        let re: NSRegularExpression
        if let r = cache[pattern] { re = r } else {
            re = (try? NSRegularExpression(pattern: pattern)) ?? NSRegularExpression()
            cache[pattern] = re
        }
        lock.unlock()
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
}

// MARK: - Families

public struct FamilyRules: Codable, Sendable {
    public struct Family: Codable, Equatable, Sendable {
        public var name: String
        /// The PLAN.md round that brings it in: 1–5, or `nil` for families outside the plan.
        public var round: Int?
        public var summary: String
    }

    public struct Rule: Codable, Equatable, Sendable {
        public var family: String
        public var match: SymbolMatcher
    }

    /// Symbols the report leaves out: types the compiler builds (`TupleView`,
    /// `ModifiedContent`) that no author writes.
    public struct Ignore: Codable, Equatable, Sendable {
        public var reason: String
        public var match: SymbolMatcher
    }

    public var families: [Family]
    public var rules: [Rule]
    public var ignore: [Ignore]

    public static let unsorted = "Unsorted"

    public init(families: [Family], rules: [Rule], ignore: [Ignore] = []) {
        self.families = families; self.rules = rules; self.ignore = ignore
    }

    public static func load(_ url: URL) throws -> FamilyRules {
        try JSONDecoder().decode(FamilyRules.self, from: Data(contentsOf: url))
    }

    /// The family for a symbol. Rules that name exact `ids` win; then the first
    /// matching rule in file order; then "Unsorted".
    public func family(for s: SDKSymbol) -> String {
        for r in rules where r.match.ids != nil && r.match.matches(s) { return r.family }
        for r in rules where r.match.ids == nil && r.match.matches(s) { return r.family }
        return FamilyRules.unsorted
    }

    public func ignoreReason(for s: SDKSymbol) -> String? {
        ignore.first { $0.match.matches(s) }?.reason
    }

    public func round(of family: String) -> Int? {
        families.first { $0.name == family }?.round
    }

    /// Rules naming a family that isn't declared.
    public func undeclaredFamilies() -> [String] {
        let names = Set(families.map(\.name))
        return Array(Set(rules.map(\.family)).subtracting(names)).sorted()
    }
}

// MARK: - Won't do

public struct WontDoList: Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// Left out for good, for the reason given.
        case wontDo
        /// On PLAN.md's Later list: out of Rounds 1–5, not ruled out.
        case later
    }

    public struct Entry: Codable, Equatable, Sendable {
        /// A short stable key (`mapkit-views`).
        public var id: String
        /// What's left out, as the report heads it.
        public var what: String
        /// One line: why.
        public var reason: String
        public var status: Status
        /// Where the decision is written down (`PLAN.md Won't do`).
        public var source: String?
        /// Any of these. The file may give one matcher or a list.
        public var match: [SymbolMatcher]
        /// About an API that isn't SwiftUI's (`AVAudioSourceNode`): it reaches
        /// the manifest and the prompt, and matches no SDK symbol.
        public var outsideSDK = false

        public init(id: String, what: String, reason: String, status: Status, source: String? = nil, match: [SymbolMatcher]) {
            self.id = id; self.what = what; self.reason = reason; self.status = status; self.source = source; self.match = match
        }

        enum CodingKeys: String, CodingKey { case id, what, reason, status, source, match, outsideSDK }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            what = try c.decode(String.self, forKey: .what)
            reason = try c.decode(String.self, forKey: .reason)
            status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .wontDo
            source = try c.decodeIfPresent(String.self, forKey: .source)
            outsideSDK = try c.decodeIfPresent(Bool.self, forKey: .outsideSDK) ?? false
            if outsideSDK, !c.contains(.match) { match = [] }
            else if let one = try? c.decode(SymbolMatcher.self, forKey: .match) { match = [one] }
            else { match = try c.decode([SymbolMatcher].self, forKey: .match) }
        }

        public func matches(_ s: SDKSymbol, family: String?) -> Bool {
            match.contains { $0.matches(s, family: family) }
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry]) { self.entries = entries }

    public static func load(_ url: URL) throws -> WontDoList {
        try JSONDecoder().decode(WontDoList.self, from: Data(contentsOf: url))
    }

    /// The first entry that covers the symbol.
    public func entry(for s: SDKSymbol, family: String? = nil) -> Entry? {
        entries.first { $0.matches(s, family: family) }
    }

    /// Entries with duplicate ids, or a matcher that can match nothing.
    public func problems() -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for e in entries {
            if !seen.insert(e.id).inserted { out.append("duplicate id \(e.id)") }
            if !e.outsideSDK, e.match.isEmpty || e.match.contains(where: \.isEmpty) { out.append("\(e.id) has an empty matcher") }
        }
        return out
    }
}
