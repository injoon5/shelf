import Foundation
import Testing
@testable import CoverageKit

let modifiersSample = """
enum KModifiers {
    static func apply(_ m: KModifier, to view: AnyView) -> AnyView {
        let first = m.args.first
        switch m.name {
        case "padding":
            if case .native(.implicit("horizontal", _))? = first { return AnyView(view.padding(.horizontal)) }
            return AnyView(view.padding())
        case "gesture", "simultaneousGesture":
            return view
        case "pickerStyle":
            guard case .native(.implicit(let n, _))? = first else { return view }
            switch n {
            case "segmented": return AnyView(view.pickerStyle(.segmented))
            #if os(iOS)
            case "wheel": return AnyView(view.pickerStyle(.wheel))
            #endif
            #if os(macOS)
            case "radioGroup": return AnyView(view.pickerStyle(.radioGroup))
            #endif
            default: return view
            }
        case "labelStyle":
            if case .native(.implicit(let n, _))? = first, n == "iconOnly" { return AnyView(view.labelStyle(.iconOnly)) }
            return AnyView(view.labelStyle(.titleAndIcon))
        default:
            return view
        }
    }

    static func transition(_ v: KV?) -> AnyTransition {
        switch name {
        case "scale": return .scale
        case "slide": return .slide
        default: return .opacity
        }
    }
}
"""

let builtinsSample = """
enum KBuiltins {
    static let viewNames: Set<String> = [
        "Text", "Image", "BarMark",
    ]
    static let modifierNames: Set<String> = ["padding", "annotation", "focused"]
    static let colorNames: [String: Color] = ["red": .red, "grey": .gray]
    static func callStatic(_ typeName: String, _ name: String) -> KV {
        switch (typeName, name) {
        case ("Timer", "publish"), ("Animation", "spring"): return .void
        default: return .void
        }
    }
    static func font(_ name: String) -> Font? {
        if name == "system" { return .body }
        return nil
    }
}

struct KChartPoint {
    init(_ modifiers: [KModifier]) {
        for m in modifiers { if m.name == "foregroundStyle" { } }
    }
}
"""

@Suite struct EngineScannerTests {
    @Test func casesWithFunctionAndPath() {
        let f = EngineScanner.scan(modifiersSample, file: "KEModifiers.swift")
        let top = f.cases.filter { $0.function == "apply" && $0.path.isEmpty }
        #expect(top.map(\.labels) == [["padding"], ["gesture", "simultaneousGesture"], ["pickerStyle"], ["labelStyle"]])
        #expect(top.map(\.subject) == Array(repeating: "m.name", count: 4))
        let nested = f.cases.filter { $0.function == "apply" && !$0.path.isEmpty }
        #expect(nested.map(\.labels) == [["segmented"], ["wheel"]], "os(macOS) is skipped; `if case` isn't a label")
        #expect(nested.allSatisfy { $0.path == ["pickerStyle"] })
        #expect(f.cases.filter { $0.function == "transition" }.flatMap(\.labels) == ["scale", "slide"])
    }

    @Test func stubsAndImplicitCalls() throws {
        let f = EngineScanner.scan(modifiersSample, file: "KEModifiers.swift")
        let gesture = try #require(f.cases.first { $0.labels.contains("gesture") })
        #expect(gesture.isStub)
        let padding = try #require(f.cases.first { $0.labels == ["padding"] })
        #expect(!padding.isStub)
        let label = try #require(f.cases.first { $0.labels == ["labelStyle"] })
        // `.native(.implicit(` matches the pattern too; the builder keeps only `<case name>.` calls.
        #expect(label.implicitCalls.filter { $0.hasPrefix("labelStyle.") } == ["labelStyle.iconOnly", "labelStyle.titleAndIcon"])
    }

    @Test func collectionsTuplesAndComparisons() {
        let f = EngineScanner.scan(builtinsSample, file: "KEBuiltins.swift")
        #expect(f.collections.map(\.name) == ["viewNames", "modifierNames", "colorNames"])
        #expect(f.collections[0].values == ["Text", "Image", "BarMark"])
        #expect(f.collections[2].values == ["red", "grey"], "dictionary keys")
        #expect(f.cases.first { $0.function == "callStatic" }?.labels == ["Timer.publish", "Animation.spring"])
        #expect(f.comparisons.contains { $0.function == "font" && $0.lhs == "name" && $0.value == "system" })
        #expect(f.comparisons.contains { $0.typeName == "KChartPoint" && $0.lhs == "m.name" && $0.value == "foregroundStyle" })
    }

    @Test func interimManifestResolvesAgainstTheSDK() throws {
        var facts = EngineScanner.scan(modifiersSample, file: "KEModifiers.swift")
        facts.merge(EngineScanner.scan(builtinsSample, file: "KEBuiltins.swift"))
        let catalog = Catalog(symbols: [
            symbol(.view, "Text"), symbol(.content, "BarMark", module: "Charts", conformsTo: "ChartContent"),
            symbol(.modifier, "padding", receivers: ["View"]),
            symbol(.modifier, "annotation", owner: "ChartContent", module: "Charts", receivers: ["ChartContent"]),
            symbol(.modifier, "foregroundStyle", owner: "ChartContent", module: "Charts", receivers: ["ChartContent"]),
            symbol(.style, "segmented", owner: "PickerStyle"), symbol(.style, "iconOnly", owner: "LabelStyle"),
            symbol(.style, "titleAndIcon", owner: "LabelStyle"),
            symbol(.member, "red", owner: "Color"), symbol(.member, "spring", owner: "Animation"),
            symbol(.member, "system", owner: "Font"),
        ], modules: ["SwiftUI"])
        let families = FamilyRules(families: [.init(name: "Layout", round: 1, summary: "")],
                                   rules: [.init(family: "Layout", match: SymbolMatcher(kinds: [.modifier]))])
        let m = InterimManifest.build(facts: facts, catalog: catalog, families: families)
        #expect(m.interim)
        let ids = Set(m.symbols.map(\.id))
        for id in ["view:Text", "view:Image", "content:BarMark", "modifier:padding", "modifier:ChartContent.annotation",
                   "modifier:ChartContent.foregroundStyle", "style:PickerStyle.segmented", "style:PickerStyle.wheel",
                   "style:LabelStyle.iconOnly", "style:LabelStyle.titleAndIcon", "member:Color.red", "member:ShapeStyle.red",
                   "member:Color.grey", "member:Animation.spring", "member:AnyTransition.slide", "member:Font.system"] {
            #expect(ids.contains(id), "\(id)")
        }
        #expect(!ids.contains("member:Timer.publish"), "not a SwiftUI member")
        let by = Dictionary(uniqueKeysWithValues: m.symbols.map { ($0.id, $0) })
        #expect(by["modifier:padding"]?.support == .partial, "a real case beats the name list's stub")
        #expect(by["modifier:gesture"]?.support == .stub)
        #expect(by["modifier:focused"]?.support == .stub, "listed, but no case")
        #expect(by["modifier:padding"]?.family == "Layout")
        #expect(by["view:Image"]?.family == "Kiln-only", "not in this catalog")
        #expect(by["modifier:padding"]?.overloads == nil, "interim manifests don't enumerate overloads")
    }

    @Test func scansTheRealEngineIfPresent() throws {
        let engine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Kiln/Engine")
        // The engine is being rebuilt (§1.3); once the switch files are gone this has nothing to read.
        guard FileManager.default.fileExists(atPath: engine.appendingPathComponent("KEModifiers.swift").path) else { return }
        let facts = try InterimManifest.scan(engineDirectory: engine)
        let raw = InterimManifest.raw(facts)
        #expect(raw.keys.contains(.viewish("DatePicker")))
        #expect(raw.keys.contains(.modifier("padding", owner: nil)))
        #expect(raw.keys.contains(.style(owner: "PickerStyle", member: "segmented")))
        #expect(raw[.modifier("gesture", owner: nil)]?.stub == true)
    }
}
