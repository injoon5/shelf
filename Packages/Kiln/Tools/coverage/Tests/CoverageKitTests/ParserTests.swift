import Foundation
import Testing
@testable import CoverageKit

func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
    return try String(contentsOf: url, encoding: .utf8)
}

func sampleFile() throws -> InterfaceFile {
    InterfaceParser.parse(try fixture("Sample.swiftinterface"))
}

func sampleCatalog() throws -> Catalog {
    Catalog.build([try sampleFile()])
}

func find(_ decls: [Decl], _ kind: Decl.Kind, _ name: String) -> [Decl] {
    var out: [Decl] = []
    for d in decls {
        if d.kind == kind && d.name == name { out.append(d) }
        out += find(d.children, kind, name)
    }
    return out
}

@Suite struct LexerTests {
    @Test func stringsKeepTheirBraces() {
        let ts = Lexer.tokenize(#"f("{ \(a("}")) }") { }"#)
        #expect(ts.map(\.text) == ["f", "(", #""{ \(a("}")) }""#, ")", "{", "}"])
    }

    @Test func multiLineAndRawStrings() {
        let ts = Lexer.tokenize("let a = \"\"\"\n{\n\"\"\"\nlet b = #\"x\"y\"#")
        #expect(ts.filter { $0.kind == .string }.count == 2)
        #expect(ts.last?.line == 4)
    }

    @Test func angleBracketsStaySingle() {
        let ts = Lexer.tokenize("A<B<C>> -> D ... ..< :: ==")
        #expect(ts.map(\.text) == ["A", "<", "B", "<", "C", ">", ">", "->", "D", "...", "..<", "::", "=="])
    }

    @Test func firstBranchOfIf() {
        let ts = Lexer.tokenize("#if compiler(>=5.3) && $X\nnew\n#else\nold\n#endif\nafter")
        #expect(ts.map(\.text) == ["new", "after"])
    }

    @Test func iOSPolicyEvaluatesOS() {
        let src = "#if os(macOS)\nmac\n#elseif os(iOS)\nios\n#else\nother\n#endif\n#if !os(iOS)\nnope\n#endif\n#if canImport(UIKit)\nuikit\n#endif"
        #expect(Lexer.tokenize(src, policy: .iOS).map(\.text) == ["ios", "uikit"])
        #expect(Lexer.tokenize(src, policy: .firstBranch).map(\.text) == ["mac", "nope", "uikit"])
    }

    @Test func commentsAndBackticks() {
        let ts = Lexer.tokenize("/* a /* nested */ b */ `default` // tail\nx")
        #expect(ts.map(\.text) == ["default", "x"])
        #expect(ts[0].kind == .ident)
    }
}

@Suite struct InterfaceParserTests {
    @Test func readsModuleAndImports() throws {
        let f = try sampleFile()
        #expect(f.module == "SampleUI")
        #expect(f.imports.contains("SwiftUICore"))
    }

    @Test func dropsTheElseBranchDuplicate() throws {
        let f = try sampleFile()
        let gadgets = f.decls.filter { $0.kind == .struct && $0.name == "Gadget" }
        #expect(gadgets.count == 1)
        #expect(gadgets[0].inherits == ["View"])
        #expect(gadgets[0].generics == "<Label>")
    }

    @Test func stripsModuleQualifiersBothWays() throws {
        let f = try sampleFile()
        let swipe = try #require(find(f.decls, .func, "swipeThing").first)
        #expect(swipe.params.map(\.type) == ["Bool", "() -> some View"])
        #expect(swipe.returnType == "some View")
        let shape = try #require(f.decls.first { $0.kind == .protocol && $0.name == "Shape" })
        #expect(shape.inherits == ["Animatable", "View", "Sendable"])
    }

    @Test func extensionsKeepTheirWhereClause() throws {
        let f = try sampleFile()
        let ext = try #require(f.decls.first { $0.kind == .extension && $0.name == "Gadget" })
        #expect(ext.whereClause == "Label == Text")
        #expect(ext.children.filter { $0.kind == .initializer }.count == 2)
    }

    @Test func skipsInlinableBodies() throws {
        let f = try sampleFile()
        let ext = try #require(f.decls.first { $0.kind == .extension && $0.name == "View" })
        // gadgetPadding ×2, macOnlyModifier, oldPadding, softDeprecated, inlined, helper, _privateModifier, inlinableHelper.
        #expect(ext.children.map(\.name) == ["gadgetPadding", "gadgetPadding", "macOnlyModifier", "oldPadding", "softDeprecated",
                                             "inlined", "helper", "_privateModifier", "inlinableHelper"])
        // The style's static var has a `get { .init() }` body; the next declaration still parses.
        #expect(f.decls.contains { $0.kind == .struct && $0.name == "Animation" })
    }

    @Test func paramsAndLabels() throws {
        let f = try sampleFile()
        let pads = find(f.decls, .func, "gadgetPadding")
        #expect(pads.map(\.labels) == [["_"], ["_", "length"]])
        #expect(pads[1].params[0].hasDefault)
        let inits = find(f.decls, .initializer, "init").filter { $0.labels.first == "_" }
        #expect(inits.map(\.labels) == [["_", "selection"], ["_", "isOn"]])
        let entry = try #require(f.decls.first { $0.kind == .macro })
        #expect(entry.name == "Entry")
        let eq = try #require(f.decls.first { $0.kind == .func && $0.name == "==" })
        #expect(eq.labels == ["lhs", "rhs"])
    }

    @Test func attributesOnTheirOwnLines() throws {
        let f = try sampleFile()
        let mac = try #require(f.decls.first { $0.name == "MacOnlyView" })
        #expect(mac.attributes.filter { $0.name == "available" }.count == 2)
        let wrapper = try #require(f.decls.first { $0.name == "Remembered" })
        #expect(wrapper.has("propertyWrapper"))
    }
}

@Suite struct AvailabilityTests {
    func attrs(_ s: String) -> [Attribute] {
        let ts = Lexer.tokenize(s + "\npublic func f()")
        return InterfaceParser.attributes(ts, from: 0).0
    }

    @Test func shorthand() {
        let a = Availability.iOS(attrs("@available(iOS 17.0, macOS 14.0, *)"))
        #expect(a.introduced == Version("17.0"))
        #expect(!a.unavailable && !a.isDeprecated)
        #expect(Availability.iOS(attrs("@available(macOS 14.0, *)")).introduced == nil)
        #expect(Availability.iOS(attrs("@available(anyAppleOS 27, *)")).introduced == Version("27"))
    }

    @Test func longForm() {
        let a = Availability.iOS(attrs(#"@available(iOS, introduced: 13.0, deprecated: 17.0, message: "Use x")"#))
        #expect(a.introduced == Version("13"))
        #expect(a.isDeprecated)
        #expect(a.message == "Use x")
        #expect(Availability.iOS(attrs("@available(iOS, unavailable)")).unavailable)
        #expect(!Availability.iOS(attrs("@available(macOS, unavailable)")).unavailable)
        #expect(Availability.iOS(attrs(#"@available(*, deprecated, message: "x")"#)).isDeprecated)
        #expect(!Availability.iOS(attrs("@available(iOS, introduced: 15.0, deprecated: 100000.0)")).isDeprecated)
    }

    @Test func refinementTakesTheLaterVersion() {
        var outer = Availability(); outer.introduced = Version("15")
        var inner = Availability(); inner.introduced = Version("17.2")
        #expect(outer.refined(by: inner).introduced == Version("17.2"))
        #expect(inner.refined(by: outer).introduced == Version("17.2"))
        #expect(Version("17.2").description == "17.2")
        #expect(Version("26").description == "26.0")
    }
}

@Suite struct CatalogTests {
    @Test func viewsAndTheirInits() throws {
        let c = try sampleCatalog()
        let g = try #require(c.symbol("view:Gadget"))
        #expect(g.introduced == "16.0")
        // Sorted by signature: `init(_ titleKey:…` before `init<S>(_ title:…`.
        #expect(g.overloads.map(\.labels) == [["_", "selection"], ["_", "isOn"]])
        #expect(c.symbol("view:Wedge") != nil, "a Shape is a View")
        #expect(c.symbol("view:MacOnlyView") == nil, "unavailable on iOS")
        #expect(c.symbol("view:_HiddenView") == nil, "underscored")
    }

    @Test func modifiersGroupOverloadsByName() throws {
        let c = try sampleCatalog()
        let pad = try #require(c.symbol("modifier:gadgetPadding"))
        #expect(pad.overloads.count == 2)
        #expect(pad.introduced == "13.0", "the earliest overload")
        #expect(pad.overloads.map(\.introduced).contains("27.0"))
        #expect(c.symbol("modifier:macOnlyModifier") == nil)
        #expect(c.symbol("modifier:helper") == nil, "returns Int, not a view")
        #expect(c.symbol("modifier:_privateModifier") == nil)
        #expect(c.symbol("modifier:inlinableHelper") == nil, "@usableFromInline internal: no app can call it")
        #expect(c.symbol("modifier:inlined") != nil, "ModifiedContent counts")
        #expect(c.symbol("modifier:oldPadding")?.deprecated == true)
        #expect(c.symbol("modifier:softDeprecated")?.deprecated == false, "100000 is a placeholder")
        #expect(c.symbol("modifier:swipeThing")?.introduced == "27.0", "anyAppleOS")
    }

    @Test func shapeAndGestureAndToolbarModifiers() throws {
        let c = try sampleCatalog()
        #expect(c.symbol("modifier:rotation")?.overloads.first?.receiver == "Shape")
        #expect(c.symbol("modifier:fill") != nil)
        #expect(c.symbol("modifier:Gesture.onEnded") != nil)
        let p = try #require(c.symbol("modifier:ToolbarContent.priority"))
        #expect(p.introduced == "27.0")
        #expect(c.symbol("content:Spacer")?.conformsTo == "ToolbarContent")
        #expect(c.symbol("gesture:Swish")?.overloads.first?.labels == ["minimumDistance"])
    }

    @Test func stylesMembersEnvironmentWrappers() throws {
        let c = try sampleCatalog()
        let fancy = try #require(c.symbol("style:GadgetStyle.fancy"), "Primitive is dropped from the owner")
        #expect(fancy.introduced == "15.0")
        #expect(c.symbol("protocol:PrimitiveGadgetStyle") != nil)
        #expect(c.symbol("member:Animation.bouncy") != nil)
        #expect(c.symbol("member:Animation.spring")?.overloads.first?.labels == ["duration", "bounce"])
        #expect(c.symbol("environment:gadgetTint") != nil)
        #expect(c.symbol("wrapper:Remembered") != nil)
        #expect(c.symbol("macro:Entry") != nil)
    }

    @Test func idsAreStableAndSorted() throws {
        let c = try sampleCatalog()
        #expect(c.symbols.map(\.id) == c.symbols.map(\.id).sorted())
        #expect(Set(c.symbols.map(\.id)).count == c.symbols.count)
    }
}
