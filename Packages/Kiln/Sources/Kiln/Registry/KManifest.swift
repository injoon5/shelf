//
//  KManifest.swift
//  Kiln's bridge registry
//
//  `kiln-manifest.json`: every symbol the registry has, in the schema of
//  `Docs/manifest.md` (the coverage tool's `Manifest.swift`). The coverage
//  report, Shelf's prompt and the checker read it. `ManifestTests` writes it
//  to `Packages/Kiln/kiln-manifest.json` and fails when the file is stale.
//

import Foundation

struct KManifest: Codable, Equatable {
    struct Overload: Codable, Equatable {
        var labels: [String]
        var receiver: String?
        var introduced: String?
        var notes: String?
    }

    struct Symbol: Codable, Equatable {
        var id: String
        var kind: String
        var name: String
        var owner: String?
        var family: String
        var support: String
        var introduced: String?
        var overloads: [Overload]?
        var notes: String?
        var source: String?
        /// A protocol's requirements as the app writes them (`path(in:)`;
        /// `animatableData?` has a default; `async perform()` waits), and
        /// whether native code can use the app's value through a proxy (§1.5).
        var requirements: [String]?
        var proxy: Bool?
    }

    var schemaVersion = 1
    var interim = false
    var generator = "kiln-registry"
    var description: String?
    var symbols: [Symbol]

    func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self) + Data("\n".utf8)
    }
}

extension KRegistry {
    /// Receivers whose modifiers the coverage report keeps apart (`modifier:ChartContent.annotation`).
    static let contentReceivers: Set<String> = ["ChartContent", "ToolbarContent", "TabContent", "Gesture", "Scene", "Chart3DContent"]

    /// The manifest of everything registered: Kiln's own bridges, and the
    /// host's unless `includeHost` is false (the checked-in file has Kiln's).
    func manifest(includeHost: Bool = true) -> KManifest {
        var symbols: [KManifest.Symbol] = []

        func symbol(_ kind: String, _ name: String, owner: String?, _ b: KBridge, overloads: [KManifest.Overload]?,
                    support: KilnSupport? = nil, notes: String? = nil) {
            if !includeHost && b.family == .host { return }
            let id = kind + ":" + (owner.map { $0 + "." } ?? "") + name
            symbols.append(.init(id: id, kind: kind, name: name, owner: owner, family: b.family.rawValue,
                                 support: (support ?? b.support).rawValue, introduced: b.introduced,
                                 overloads: overloads, notes: notes ?? b.notes, source: b.source))
        }
        func overloads(_ os: [KOverload], receiver: String? = nil) -> [KManifest.Overload]? {
            let listed = os.filter { !$0.lenient }
            if listed.isEmpty { return os.isEmpty ? [] : nil }
            var seen = Set<[String]>()
            return listed.compactMap { o in
                guard seen.insert(o.manifestLabels + [o.receiver ?? receiver ?? ""]).inserted else { return nil }
                return .init(labels: o.manifestLabels, receiver: o.receiver ?? receiver,
                             introduced: o.availability?.iOSString, notes: o.notes)
            }
        }

        for b in views.values where !b.isInternal {
            symbol(b.manifestKind, b.name, owner: b.owner, b, overloads: overloads(b.forms.map(\.overload)))
        }
        for b in modifiers.values where !b.isInternal {
            // Forms on content that isn't a view (`ChartContent`) are that receiver's modifier.
            let byReceiver = Dictionary(grouping: b.forms.map(\.overload)) { o in o.receiver.flatMap { Self.contentReceivers.contains($0) ? $0 : nil } }
            for (receiver, os) in byReceiver where receiver != nil && receiver != b.owner {
                symbol("modifier", b.name, owner: receiver, b, overloads: overloads(os))
            }
            symbol("modifier", b.name, owner: b.owner, b, overloads: overloads(byReceiver[nil] ?? b.forms.map(\.overload)))
            if let styles = b.styles {
                for s in styles.names { symbol("style", s, owner: styles.owner, b, overloads: [], support: .full, notes: "") }
            }
        }
        for t in types.values where !t.isInternal {
            symbol(t.manifestKind, t.name, owner: nil, t, overloads: t.inits.isEmpty ? [] : overloads(t.inits.map(\.overload)))
            for (name, p) in t.staticProperties {
                symbol("member", name, owner: t.name, t, overloads: [], support: p.support, notes: p.notes ?? "")
            }
            for (name, ms) in t.staticMethods where t.staticProperties[name] == nil {
                symbol("member", name, owner: t.name, t, overloads: overloads(ms.map(\.overload)), notes: ms.first?.overload.notes ?? "")
            }
            for (name, p) in t.properties where t.staticProperties[name] == nil && t.staticMethods[name] == nil {
                symbol("member", name, owner: t.name, t, overloads: [], support: p.support, notes: p.notes ?? "")
            }
            for (name, ms) in t.methods where t.staticProperties[name] == nil && t.staticMethods[name] == nil && t.properties[name] == nil {
                symbol("member", name, owner: t.name, t, overloads: overloads(ms.map(\.overload)), notes: ms.first?.overload.notes ?? "")
            }
        }
        // Another name for a type (`CGFloat` is `Double` here).
        for (alias, target) in aliases {
            guard let t = types[target], !t.isInternal, types[alias] == nil, !hiddenAliases.contains(alias) else { continue }
            symbol("type", alias, owner: nil, t, overloads: nil, notes: "The same as `\(target)` in Kiln.")
        }
        for f in functions.values {
            symbol("member", f.name, owner: f.owner, f, overloads: overloads(f.forms.map(\.overload)))
        }
        for p in protocols.values {
            let before = symbols.count
            symbol("protocol", p.name, owner: nil, p, overloads: nil)
            guard symbols.count > before else { continue }
            if !p.members.isEmpty { symbols[before].requirements = p.members.map { ($0.isStatic ? "static " : "") + ($0.isAsync ? "async " : "") + $0.declared } }
            if p.proxy != nil { symbols[before].proxy = true }
        }
        for e in environment.values { symbol("environment", e.name, owner: nil, e, overloads: []) }
        for w in wrappers.values { symbol("wrapper", w.name, owner: nil, w, overloads: []) }

        // One entry per id: a name registered as a property and a method
        // (`first`, `first(where:)`) is one member.
        var byID: [String: KManifest.Symbol] = [:]
        for s in symbols {
            if var prior = byID[s.id] {
                if let o = s.overloads { prior.overloads = (prior.overloads ?? []) + o.filter { !(prior.overloads ?? []).contains($0) } }
                byID[s.id] = prior
            } else {
                byID[s.id] = s
            }
        }
        for (id, var s) in byID {
            if s.notes == "" { s.notes = nil }
            s.overloads = s.overloads?.sorted { $0.labels.joined(separator: ",") + ($0.receiver ?? "") < $1.labels.joined(separator: ",") + ($1.receiver ?? "") }
            byID[id] = s
        }
        return KManifest(description: "Kiln \(Kiln.version), Shelf's copy", symbols: byID.values.sorted { $0.id < $1.id })
    }
}
