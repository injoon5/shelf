// The interim manifest: what Kiln 0.2.1's engine handles, read from its switch
// statements by EngineScanner. It's the Round 1 baseline until §1.4's registry
// exports the real kiln-manifest.json.
//
// Every symbol found is `partial` (a case exists, which says nothing about which
// overloads work), or `stub` when the case only returns the view unchanged.
// Overloads are never enumerated (`overloads: null`).

import Foundation

public enum InterimManifest {
    public static let generator = "coverage/interim-switch-scan"

    /// Where each kind of name lives in the 0.2.1 engine. File names are matched
    /// by suffix, functions by name.
    struct Where {
        var file: String
        var function: String? = nil
        var typeName: String? = nil
        var subjectContains: String? = nil
        var topLevelOnly = true
    }

    enum Raw: Hashable {
        /// A view, mark, toolbar item or gesture name: resolved against the SDK.
        case viewish(String)
        case modifier(String, owner: String?)
        case style(owner: String, member: String)
        case member(owner: String, name: String)
        case wrapper(String)
        case environment(String)
        case type(String)
    }

    struct Found {
        var stub: Bool
        var source: String
    }

    public static func scan(engineDirectory: URL) throws -> EngineFacts {
        var facts = EngineFacts()
        let names = try FileManager.default.contentsOfDirectory(atPath: engineDirectory.path).filter { $0.hasSuffix(".swift") }.sorted()
        for n in names {
            let text = try String(contentsOf: engineDirectory.appendingPathComponent(n), encoding: .utf8)
            facts.merge(EngineScanner.scan(text, file: n))
        }
        return facts
    }

    static func lowerFirst(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }
    static func upperFirst(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// What the facts say Kiln knows, before resolving names against the SDK.
    static func raw(_ facts: EngineFacts) -> [Raw: Found] {
        var out: [Raw: Found] = [:]
        func note(_ r: Raw, stub: Bool, _ source: String) {
            if let f = out[r] {
                // A real case anywhere beats a stub; the first real source is kept.
                if f.stub && !stub { out[r] = Found(stub: false, source: source) }
            } else {
                out[r] = Found(stub: stub, source: source)
            }
        }
        for c in facts.cases {
            let src = "\(c.file):\(c.line)"
            let top = c.path.isEmpty
            switch (c.file, c.function) {
            case ("KERenderer.swift", "primitive") where top:
                c.labels.forEach { note(.viewish($0), stub: c.isStub, src) }
            case ("KEModifiers.swift", "apply") where top:
                for l in c.labels {
                    note(.modifier(l, owner: nil), stub: c.isStub, src)
                    if l.hasSuffix("Style") {
                        // `view.pickerStyle(.segmented)` in the body names a member.
                        let owner = upperFirst(l)
                        for call in c.implicitCalls where call.hasPrefix(l + ".") {
                            note(.style(owner: owner, member: String(call.dropFirst(l.count + 1))), stub: false, src)
                        }
                    }
                }
            case ("KEModifiers.swift", "apply"):
                // Nested: `case "pickerStyle": switch n { case "segmented": ... }`.
                if let outer = c.path.last, outer.hasSuffix("Style"), !outer.contains("|") {
                    c.labels.forEach { note(.style(owner: upperFirst(outer), member: $0), stub: c.isStub, src) }
                }
            case ("KERenderer.swift", "modified") where top, ("KERenderer.swift", "shapeModifier") where top:
                c.labels.forEach { note(.modifier($0, owner: nil), stub: c.isStub, src) }
            case ("KERenderer.swift", "text") where c.subject.contains("m.name"):
                c.labels.forEach { note(.modifier($0, owner: nil), stub: c.isStub, src) }
            case ("KERenderer.swift", "shapeStyle") where !top:
                c.labels.forEach { note(.member(owner: "ShapeStyle", name: $0), stub: c.isStub, src) }
            case ("KERenderer.swift", "placement"):
                c.labels.forEach { note(.member(owner: "ToolbarItemPlacement", name: $0), stub: c.isStub, src) }
            case ("KERenderer.swift", "prepare") where top:
                c.labels.forEach { note(.wrapper($0), stub: c.isStub, src) }
            case ("KEBuiltins.swift", "animation"):
                c.labels.forEach { note(.member(owner: "Animation", name: $0), stub: c.isStub, src) }
            case ("KEModifiers.swift", "transition"):
                c.labels.forEach {
                    note(.member(owner: "AnyTransition", name: $0), stub: c.isStub, src)
                    note(.member(owner: "Transition", name: $0), stub: c.isStub, src)
                }
            case ("KEBuiltins.swift", "environmentDefault"):
                c.labels.forEach { note(.environment($0), stub: c.isStub, src) }
            case ("KEBuiltins.swift", "construct") where top:
                c.labels.forEach { note(.type($0), stub: c.isStub, src) }
            case ("KEBuiltins.swift", "staticMember") where top:
                c.labels.forEach { note(.type($0), stub: c.isStub, src) }
            case ("KEBuiltins.swift", "callStatic") where top:
                for l in c.labels {
                    let parts = l.split(separator: ".")
                    guard parts.count == 2 else { continue }
                    let (t, m) = (String(parts[0]), String(parts[1]))
                    note(.type(t), stub: false, src)
                    note(.member(owner: t, name: m), stub: c.isStub, src)
                }
            default: break
            }
        }
        for c in facts.collections {
            let src = "\(c.file):\(c.line)"
            switch c.name {
            case "viewNames": c.values.forEach { note(.viewish($0), stub: false, src) }
            // Listed as known modifiers, but `apply` ignores a name without a case.
            case "modifierNames": c.values.forEach { note(.modifier($0, owner: nil), stub: true, src) }
            case "colorNames":
                c.values.forEach {
                    note(.member(owner: "Color", name: $0), stub: false, src)
                    note(.member(owner: "ShapeStyle", name: $0), stub: false, src)
                }
            case "fontStyles": c.values.forEach { note(.member(owner: "Font", name: $0), stub: false, src) }
            default: break
            }
        }
        for c in facts.comparisons {
            let src = "\(c.file):\(c.line)"
            if c.lhs == "m.name" {
                // Chart marks read their own modifiers.
                let owner: String? = c.typeName == "KChartPoint" ? "ChartContent" : nil
                note(.modifier(c.value, owner: owner), stub: false, src)
            }
            if c.file == "KEBuiltins.swift" && c.function == "font" && c.lhs == "name" {
                note(.member(owner: "Font", name: c.value), stub: false, src)
            }
        }
        return out
    }

    /// Builds the interim manifest. Names are resolved against the SDK catalog
    /// (`BarMark` is `content:`, `DragGesture` would be `gesture:`); anything the SDK
    /// doesn't have keeps a plain id and shows up in the report as Kiln-only.
    public static func build(facts: EngineFacts, catalog: Catalog, families: FamilyRules) -> Manifest {
        let byID = Dictionary(catalog.symbols.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var symbols: [String: ManifestSymbol] = [:]

        func add(_ kind: SymbolKind, _ name: String, owner: String?, _ found: Found) {
            let id = SDKSymbol.makeID(kind: kind, name: name, owner: owner)
            let sdk = byID[id]
            let family = sdk.map { families.family(for: $0) } ?? "Kiln-only"
            let support: Support = found.stub ? .stub : .partial
            let notes = found.stub
                ? "Interim: accepted, but 0.2.1 ignores it."
                : "Interim: a case exists in the 0.2.1 engine; which overloads work isn't recorded."
            if var existing = symbols[id] {
                if existing.support == .stub && support == .partial {
                    existing.support = .partial; existing.notes = notes; existing.source = found.source
                    symbols[id] = existing
                }
                return
            }
            symbols[id] = ManifestSymbol(id: id, kind: kind, name: name, owner: owner, family: family, support: support,
                                         introduced: sdk?.introduced, overloads: nil, notes: notes, source: found.source)
        }

        // Sorted, so the same engine always gives the same file.
        for (r, found) in raw(facts).sorted(by: { "\($0.key)\($0.value.source)" < "\($1.key)\($1.value.source)" }) {
            switch r {
            case .viewish(let n):
                let kind = [SymbolKind.view, .content, .gesture].first { byID[SDKSymbol.makeID(kind: $0, name: n, owner: nil)] != nil } ?? .view
                add(kind, n, owner: nil, found)
            case .modifier(let n, let owner):
                // A name the SDK only has on another receiver (`annotation` on ChartContent).
                var o = owner
                if o == nil, byID[SDKSymbol.makeID(kind: .modifier, name: n, owner: nil)] == nil,
                   let other = catalog.symbols.first(where: { $0.kind == .modifier && $0.name == n }) {
                    o = other.owner
                }
                add(.modifier, n, owner: o, found)
            case .style(let owner, let member):
                add(.style, member, owner: owner, found)
            case .member(let owner, let n):
                // Only members the SDK lists as members; `Double.pi` and the like are Swift, not SwiftUI.
                if byID[SDKSymbol.makeID(kind: .member, name: n, owner: owner)] != nil || Catalog.memberOwners.contains(owner) {
                    add(.member, n, owner: owner, found)
                }
            case .wrapper(let n):
                add(.wrapper, n, owner: nil, found)
            case .environment(let n):
                add(.environment, n, owner: nil, found)
            case .type(let n):
                // A type the SDK lists under another kind (`Color` is a view) is already covered.
                if let k = [SymbolKind.type, .view, .gesture, .content].first(where: { byID[SDKSymbol.makeID(kind: $0, name: n, owner: nil)] != nil }) {
                    add(k, n, owner: nil, found)
                } else {
                    add(.type, n, owner: nil, found)
                }
            }
        }
        return Manifest(
            interim: true, generator: generator,
            description: "INTERIM. Derived by Tools/coverage from the string cases in Sources/Kiln/Engine "
                + "(KERenderer, KEModifiers, KEBuiltins). Replaced by the registry's export (§1.4); see Docs/manifest.md.",
            symbols: Array(symbols.values))
    }
}
