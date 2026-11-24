// Joins the SDK catalog, the manifest, the family rules and the won't-do list.

import Foundation

public enum Status: String, Codable, Sendable {
    /// In the manifest as `full`.
    case supported
    /// In the manifest as `partial`.
    case partial
    /// In the manifest as `stub`: accepted, no effect. Counts as missing.
    case stub
    case wontDo
    /// On PLAN.md's Later list. Not missing for the round it's deferred out of.
    case later
    case missing
    /// Compiler plumbing nobody writes (`TupleView`); left out of every count.
    case plumbing

    public var isSupported: Bool { self == .supported || self == .partial }
    public var isDecidedOut: Bool { self == .wontDo || self == .later }
    public var isMissing: Bool { self == .missing || self == .stub }
}

public struct CoverageEntry: Codable, Equatable, Sendable {
    public var symbol: SDKSymbol
    public var family: String
    public var round: Int?
    public var status: Status
    /// Won't-do entry id, or the plumbing reason.
    public var wontDo: String?
    /// For supported symbols whose manifest lists overloads: how many SDK overloads match.
    public var overloadsCovered: Int?
    public var notes: String?
}

public struct FamilyCount: Codable, Equatable, Sendable {
    public var family: String
    public var round: Int?
    public var total = 0
    public var supported = 0
    public var wontDo = 0
    public var missing = 0
    /// Missing symbols added in iOS 26 or later.
    public var missingNew = 0

    /// Share of what's in scope (total less won't-do) that's supported.
    public var percent: Int {
        let scope = total - wontDo
        return scope == 0 ? 100 : Int((Double(supported) / Double(scope) * 100).rounded(.down))
    }
}

public struct Conflict: Codable, Equatable, Sendable {
    public var id: String
    public var wontDo: String
}

public struct CoverageResult: Sendable {
    public var entries: [CoverageEntry]
    public var families: [FamilyCount]
    /// Manifest symbols the SDK doesn't list (Kiln-only helpers, Swift types, typos).
    public var extras: [ManifestSymbol]
    /// Won't-do entries that matched nothing.
    public var staleWontDo: [String]
    /// Supported symbols a won't-do entry also matches (supported wins).
    public var conflicts: [Conflict]
    public var manifest: Manifest

    public func entries(in family: String) -> [CoverageEntry] { entries.filter { $0.family == family } }
}

public enum Coverage {
    public static func compute(catalog: Catalog, manifest: Manifest, families: FamilyRules, wontDo: WontDoList) -> CoverageResult {
        let manifestByID = Dictionary(manifest.symbols.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var entries: [CoverageEntry] = []
        var conflicts: [Conflict] = []
        var used: Set<String> = []

        for s in catalog.symbols {
            let family = families.family(for: s)
            var e = CoverageEntry(symbol: s, family: family, round: families.round(of: family), status: .missing)
            let w = wontDo.entry(for: s, family: family)
            if let w { used.insert(w.id) }
            if let reason = families.ignoreReason(for: s), manifestByID[s.id] == nil {
                e.status = .plumbing
                e.notes = reason
            } else if let m = manifestByID[s.id], m.support != .stub {
                e.status = m.support == .full ? .supported : .partial
                e.notes = m.notes
                if let w { conflicts.append(Conflict(id: s.id, wontDo: w.id)) }
                if let mo = m.overloads {
                    e.overloadsCovered = s.overloads.filter { o in
                        mo.contains { $0.labels == o.labels && ($0.receiver == nil || $0.receiver == o.receiver) }
                    }.count
                }
            } else if let w {
                e.status = w.status == .later ? .later : .wontDo
                e.wontDo = w.id
            } else if let m = manifestByID[s.id], m.support == .stub {
                e.status = .stub
                e.notes = m.notes
            }
            entries.append(e)
        }

        let sdkIDs = Set(catalog.symbols.map(\.id))
        let extras = manifest.symbols.filter { !sdkIDs.contains($0.id) }

        var counts: [String: FamilyCount] = [:]
        for f in families.families { counts[f.name] = FamilyCount(family: f.name, round: f.round) }
        for e in entries where e.status != .plumbing {
            var c = counts[e.family] ?? FamilyCount(family: e.family, round: e.round)
            c.total += 1
            if e.status.isSupported { c.supported += 1 }
            if e.status.isDecidedOut { c.wontDo += 1 }
            if e.status.isMissing {
                c.missing += 1
                if let v = e.symbol.introduced, Version(v) >= Version("26.0") { c.missingNew += 1 }
            }
            counts[e.family] = c
        }
        // Declared order, then anything else (Unsorted last).
        var ordered = families.families.compactMap { counts[$0.name] }
        let declared = Set(families.families.map(\.name))
        ordered += counts.values.filter { !declared.contains($0.family) }.sorted { $0.family < $1.family }

        return CoverageResult(entries: entries, families: ordered, extras: extras.sorted { $0.id < $1.id },
                              staleWontDo: wontDo.entries.filter { !$0.outsideSDK }.map(\.id).filter { !used.contains($0) },
                              conflicts: conflicts, manifest: manifest)
    }
}
