import Foundation
import Testing
@testable import CoverageKit

func symbol(_ kind: SymbolKind, _ name: String, owner: String? = nil, module: String = "SwiftUI",
            receivers: [String] = [], conformsTo: String? = nil, introduced: String? = "13.0") -> SDKSymbol {
    SDKSymbol(id: SDKSymbol.makeID(kind: kind, name: name, owner: owner), kind: kind, name: name, owner: owner, module: module,
              introduced: introduced, deprecated: false, deprecationMessage: nil, conformsTo: conformsTo,
              overloads: receivers.map { SymbolOverload(labels: [], receiver: $0, module: module, introduced: introduced, deprecated: false, signature: "f() on \($0)") })
}

@Suite struct FamilyRulesTests {
    let rules = FamilyRules(
        families: [.init(name: "Lists", round: 1, summary: ""), .init(name: "Navigation", round: 1, summary: ""),
                   .init(name: "Web", round: 2, summary: ""), .init(name: "Scenes", round: 1, summary: "")],
        rules: [
            .init(family: "Web", match: SymbolMatcher(modules: ["_WebKit_SwiftUI"])),
            .init(family: "Navigation", match: SymbolMatcher(kinds: [.modifier], patterns: ["^navigation", "^toolbar"])),
            .init(family: "Scenes", match: SymbolMatcher(receiversOnly: ["Scene"])),
            .init(family: "Lists", match: SymbolMatcher(kinds: [.modifier], patterns: ["^list", "^swipe"])),
            // Exact ids win over earlier rules.
            .init(family: "Lists", match: SymbolMatcher(ids: ["modifier:toolbarListThing"])),
        ],
        ignore: [.init(reason: "plumbing", match: SymbolMatcher(idPatterns: ["^view:Tuple"]))])

    @Test func firstMatchingRuleInOrder() {
        #expect(rules.family(for: symbol(.modifier, "navigationTitle")) == "Navigation")
        #expect(rules.family(for: symbol(.modifier, "listRowBackground")) == "Lists")
        #expect(rules.family(for: symbol(.modifier, "navigationThing", module: "_WebKit_SwiftUI")) == "Web", "module rule comes first")
    }

    @Test func exactIdsWin() {
        #expect(rules.family(for: symbol(.modifier, "toolbarListThing")) == "Lists")
    }

    @Test func unmatchedIsUnsorted() {
        #expect(rules.family(for: symbol(.modifier, "padding")) == FamilyRules.unsorted)
        #expect(rules.family(for: symbol(.view, "listLike")) == FamilyRules.unsorted, "kind must match too")
    }

    @Test func receiversOnly() {
        #expect(rules.family(for: symbol(.modifier, "defaultSize", owner: "Scene", receivers: ["Scene"])) == "Scenes")
        #expect(rules.family(for: symbol(.modifier, "onChangeX", receivers: ["Scene", "View"])) == FamilyRules.unsorted)
    }

    @Test func ignoreAndRounds() {
        #expect(rules.ignoreReason(for: symbol(.view, "TupleView")) == "plumbing")
        #expect(rules.ignoreReason(for: symbol(.view, "Text")) == nil)
        #expect(rules.round(of: "Web") == 2)
        #expect(rules.undeclaredFamilies().isEmpty)
    }

    @Test func checkedInRulesLoadAndCoverTheirFamilies() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let f = try FamilyRules.load(dir.appendingPathComponent("families.json"))
        #expect(f.undeclaredFamilies().isEmpty)
        let names = Set(f.families.map(\.name))
        // PLAN.md §1.4's families are all declared.
        for n in ["Controls", "Layout", "Lists", "Navigation", "Gestures", "Drawing", "Charts", "Haptics", "Sharing", "Text",
                  "Units", "Audio", "Web", "Files", "Photos", "Camera", "Motion", "Location", "Vision", "Intelligence", "Widgets"] {
            #expect(names.contains(n), "\(n)")
        }
        let w = try WontDoList.load(dir.appendingPathComponent("wont-do.json"))
        #expect(w.problems().isEmpty)
        #expect(w.entries.contains { $0.id == "mapkit-views" })
        #expect(w.entries.contains { $0.id == "metal-shaders" })
        #expect(w.entries.contains { $0.id == "documents-windows-scenes" })
    }
}

@Suite struct WontDoMergeTests {
    let families = FamilyRules(
        families: [.init(name: "Drawing", round: 1, summary: ""), .init(name: "Maps", round: nil, summary: ""),
                   .init(name: "Translation", round: nil, summary: "")],
        rules: [
            .init(family: "Maps", match: SymbolMatcher(modules: ["_MapKit_SwiftUI"])),
            .init(family: "Translation", match: SymbolMatcher(patterns: ["^translation"])),
            .init(family: "Drawing", match: SymbolMatcher(kinds: [.modifier, .view, .type])),
        ],
        ignore: [.init(reason: "plumbing", match: SymbolMatcher(ids: ["view:TupleView"]))])

    let wontDo = WontDoList(entries: [
        .init(id: "maps", what: "MapKit", reason: "Too much.", status: .wontDo, match: [SymbolMatcher(families: ["Maps"])]),
        .init(id: "shaders", what: "Shaders", reason: "Metal.", status: .wontDo,
              match: [SymbolMatcher(ids: ["modifier:colorEffect", "type:ShaderLibrary"]), SymbolMatcher(patterns: ["^layerEffect$"])]),
        .init(id: "translation", what: "Translation", reason: "Later.", status: .later, match: [SymbolMatcher(families: ["Translation"])]),
        .init(id: "nothing", what: "Nothing", reason: "Stale.", status: .wontDo, match: [SymbolMatcher(ids: ["view:Gone"])]),
    ])

    let catalog = Catalog(symbols: [
        symbol(.view, "Map", module: "_MapKit_SwiftUI"),
        symbol(.modifier, "colorEffect", receivers: ["View"]),
        symbol(.modifier, "layerEffect", receivers: ["View"]),
        symbol(.type, "ShaderLibrary"),
        symbol(.modifier, "translationTask", receivers: ["View"]),
        symbol(.modifier, "padding", receivers: ["View"]),
        symbol(.modifier, "blur", receivers: ["View"]),
        symbol(.modifier, "glassEffect", receivers: ["View"], introduced: "26.0"),
        symbol(.modifier, "focused", receivers: ["View"]),
        symbol(.view, "TupleView"),
    ], modules: ["SwiftUI"])

    func run(_ m: [ManifestSymbol]) -> CoverageResult {
        Coverage.compute(catalog: catalog, manifest: Manifest(interim: false, generator: "test", symbols: m), families: families, wontDo: wontDo)
    }

    func status(_ r: CoverageResult, _ id: String) -> Status? { r.entries.first { $0.symbol.id == id }?.status }

    @Test func eachSymbolGetsOneStatus() {
        let r = run([
            ManifestSymbol(id: "modifier:padding", kind: .modifier, name: "padding", family: "Drawing", support: .full),
            ManifestSymbol(id: "modifier:blur", kind: .modifier, name: "blur", family: "Drawing", support: .partial),
            ManifestSymbol(id: "modifier:focused", kind: .modifier, name: "focused", family: "Drawing", support: .stub),
        ])
        #expect(status(r, "modifier:padding") == .supported)
        #expect(status(r, "modifier:blur") == .partial)
        #expect(status(r, "modifier:focused") == .stub)
        #expect(status(r, "view:Map") == .wontDo)
        #expect(status(r, "modifier:colorEffect") == .wontDo)
        #expect(status(r, "modifier:layerEffect") == .wontDo, "any matcher in the list")
        #expect(status(r, "modifier:translationTask") == .later)
        #expect(status(r, "modifier:glassEffect") == .missing)
        #expect(status(r, "view:TupleView") == .plumbing)
        #expect(r.entries.first { $0.symbol.id == "view:Map" }?.wontDo == "maps")
    }

    @Test func supportedBeatsWontDoAndIsReported() {
        let r = run([ManifestSymbol(id: "modifier:colorEffect", kind: .modifier, name: "colorEffect", family: "Drawing", support: .partial)])
        #expect(status(r, "modifier:colorEffect") == .partial)
        #expect(r.conflicts == [Conflict(id: "modifier:colorEffect", wontDo: "shaders")])
    }

    @Test func staleEntriesAndExtras() {
        let r = run([ManifestSymbol(id: "view:UserShape", kind: .view, name: "UserShape", family: "Kiln-only", support: .partial)])
        #expect(r.staleWontDo == ["nothing"])
        #expect(r.extras.map(\.id) == ["view:UserShape"])
    }

    /// An entry about an API that isn't SwiftUI's reaches the prompt and is never stale.
    @Test func entriesOutsideTheSDKAreNeverStale() throws {
        let json = #"{"entries": [{"id": "rt", "what": "Render callbacks", "reason": "Audio thread.", "outsideSDK": true}]}"#
        let list = try JSONDecoder().decode(WontDoList.self, from: Data(json.utf8))
        #expect(list.entries.first?.outsideSDK == true)
        #expect(list.entries.first?.match.isEmpty == true)
        #expect(list.problems().isEmpty)
    }

    @Test func counts() throws {
        let r = run([
            ManifestSymbol(id: "modifier:padding", kind: .modifier, name: "padding", family: "Drawing", support: .full),
            ManifestSymbol(id: "modifier:focused", kind: .modifier, name: "focused", family: "Drawing", support: .stub),
        ])
        let d = try #require(r.families.first { $0.family == "Drawing" })
        // colorEffect, layerEffect, ShaderLibrary (won't do), padding (supported), blur, glassEffect, focused (missing). TupleView is plumbing.
        #expect(d.total == 7)
        #expect(d.supported == 1)
        #expect(d.wontDo == 3)
        #expect(d.missing == 3)
        #expect(d.missingNew == 1)
        #expect(d.percent == 25)
        let maps = try #require(r.families.first { $0.family == "Maps" })
        #expect(maps.total == 1 && maps.wontDo == 1 && maps.percent == 100)
    }

    @Test func decodesOneMatcherOrAList() throws {
        let json = """
        { "entries": [
          { "id": "a", "what": "A", "reason": "r", "status": "wontDo", "match": { "ids": ["view:A"] } },
          { "id": "b", "what": "B", "reason": "r", "match": [ { "ids": ["view:B"] }, { "names": ["C"] } ] }
        ] }
        """
        let w = try JSONDecoder().decode(WontDoList.self, from: Data(json.utf8))
        #expect(w.entries[0].match.count == 1)
        #expect(w.entries[1].match.count == 2)
        #expect(w.entries[1].status == .wontDo, "status defaults to wontDo")
        #expect(w.entry(for: symbol(.view, "C"))?.id == "b")
    }

    @Test func problemsAreFound() {
        let w = WontDoList(entries: [
            .init(id: "x", what: "", reason: "", status: .wontDo, match: [SymbolMatcher()]),
            .init(id: "x", what: "", reason: "", status: .wontDo, match: [SymbolMatcher(ids: ["view:A"])]),
        ])
        #expect(w.problems() == ["x has an empty matcher", "duplicate id x"])
    }
}

@Suite struct ManifestTests {
    @Test func roundTripsAndSorts() throws {
        let m = Manifest(interim: false, generator: "kiln-registry", symbols: [
            ManifestSymbol(id: "view:DatePicker", kind: .view, name: "DatePicker", family: "Controls", support: .partial,
                           introduced: "13.0", overloads: [ManifestOverload(labels: ["_", "selection", "displayedComponents"])],
                           notes: "Every style but `.field`.", source: "Bridges/Controls/DatePicker.swift"),
            ManifestSymbol(id: "modifier:padding", kind: .modifier, name: "padding", family: "Layout", support: .full),
        ])
        #expect(m.symbols.map(\.id) == ["modifier:padding", "view:DatePicker"])
        let back = try JSONDecoder().decode(Manifest.self, from: m.encoded())
        #expect(back == m)
        #expect(back.schemaVersion == 1)
    }

    @Test func rejectsAnotherSchemaVersion() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("manifest-v9-\(UUID()).json")
        try Data(#"{"schemaVersion": 9, "interim": false, "generator": "x", "symbols": []}"#.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: CoverageError.self) { try Manifest.load(url) }
    }

    @Test func overloadCoverageCountsMatchingLabels() {
        let s = SDKSymbol(id: "view:Gadget", kind: .view, name: "Gadget", owner: nil, module: "SwiftUI", introduced: nil, deprecated: false,
                          deprecationMessage: nil, conformsTo: nil, overloads: [
                              SymbolOverload(labels: ["_", "selection"], receiver: nil, module: "SwiftUI", introduced: nil, deprecated: false, signature: "a"),
                              SymbolOverload(labels: ["_", "isOn"], receiver: nil, module: "SwiftUI", introduced: nil, deprecated: false, signature: "b"),
                          ])
        let r = Coverage.compute(
            catalog: Catalog(symbols: [s], modules: ["SwiftUI"]),
            manifest: Manifest(interim: false, generator: "t", symbols: [
                ManifestSymbol(id: "view:Gadget", kind: .view, name: "Gadget", family: "Controls", support: .partial,
                               overloads: [ManifestOverload(labels: ["_", "selection"])])]),
            families: FamilyRules(families: [], rules: []), wontDo: WontDoList(entries: []))
        #expect(r.entries[0].overloadsCovered == 1)
    }
}
