import XCTest
import SwiftUI
import Observation
@testable import Kiln

/// The bridge registry (PLAN.md §1.4): overloads, argument kinds, errors,
/// availability, host bridges, and SwiftUI's observation of native objects.
@MainActor
final class RegistryTests: XCTestCase {

    /// A view's description from `body`, evaluated headless.
    private func body(_ source: String) throws -> (KInterpreter, [KView]) {
        let c = try KilnEngine.compile(source, headless: true)
        let views = try KilnEngine.rootViews(c.root, c.interp)
        guard case .custom(let s)? = views.first?.kind, let b = s.type.computed["body"] else { return (c.interp, views) }
        let env = KEnv(parent: c.interp.globalEnv, selfContext: KSelfContext(type: s.type, location: .box(KBox(.structV(s))), storage: nil))
        let v = try c.interp.entry { try c.interp.runAccessor(b.getter ?? [], env: env, returns: b.type) }
        return (c.interp, KBuiltins.asViews(v, c.interp))
    }

    private func app(_ body: String, state: String = "@State private var on = false") -> String {
        """
        import SwiftUI
        struct ContentView: View {
            \(state)
            var body: some View {
                \(body)
            }
        }
        """
    }

    // MARK: Signatures and overloads

    func testSignaturesParse() {
        let p = KSignature.parse("_:title isOn:binding spacing:number? items:any... colors:[Color] alignment:HorizontalAlignment?")
        XCTAssertEqual(p.map(\.label), [nil, "isOn", "spacing", "items", "colors", "alignment"])
        XCTAssertEqual(p.map(\.kind), [.title, .binding, .number, .any, .typedArray("Color"), .typed("HorizontalAlignment")])
        XCTAssertEqual(p.map(\.optional), [false, false, true, true, false, true])
        XCTAssertTrue(p[3].variadic)
    }

    func testOverloadsResolveByLabelsAndArgumentSyntax() throws {
        let (interp, views) = try body(app(#"""
        VStack {
            Toggle("Wi-Fi", isOn: $on)
            Toggle(isOn: $on) { Text("Wi-Fi") }
            Button("Save") { }
            Button { } label: { Text("Save") }
            Button(action: {}) { Text("Save") }
        }
        """#))
        guard case .primitive("VStack", let args, _, _)? = views.first?.kind, case .function(let content)? = args.last else {
            return XCTFail("no VStack: \(views)")
        }
        let rows = try interp.callBuilder(content)
        XCTAssertEqual(rows.compactMap { $0.bound?.overload.display($0.primitiveName ?? "") },
                       ["Toggle(_:isOn:)", "Toggle(isOn:label:)", "Button(_:action:)", "Button(action:label:)", "Button(action:label:)"])
    }

    func testATrailingClosureSkipsAnOptionalClosureBeforeARequiredOne() {
        let sheet = KOverload(params: KSignature.parse("isPresented:binding onDismiss:action? content:content"))
        XCTAssertEqual(sheet.bind(["isPresented", nil], [.other, .closureLiteral]), [0, 2])
        XCTAssertEqual(sheet.bind(["isPresented", "onDismiss", nil], [.other, .closureLiteral, .closureLiteral]), [0, 1, 2])
        let appear = KOverload(params: KSignature.parse("perform:action?"))
        XCTAssertEqual(appear.bind([nil], [.closureLiteral]), [0])
        XCTAssertNil(appear.bind([nil], [.stringLiteral]))
    }

    func testNoOverloadSaysWhichThereAre() {
        let v = Kiln.validate(app(#"Toggle("x", isOn: $on, tint: .red)"#))
        XCTAssertEqual(v.errors, ["Line 5: Kiln has no Toggle(_:isOn:tint:); it has Toggle(_:isOn:), Toggle(_:systemImage:isOn:), Toggle(isOn:label:), Toggle(_:image:isOn:) and Toggle(_:)"])
    }

    // MARK: Unknown names

    func testAnUnknownModifierIsAnErrorWithItsLine() {
        let v = Kiln.validate(app("""
        VStack {
                    Text("x")
                        .sparkle(3)
                }
        """))
        XCTAssertEqual(v.errors, ["Line 7: Kiln doesn't support the .sparkle() modifier"])
    }

    func testAnUnknownViewIsAnErrorWithItsLine() {
        let v = Kiln.validate(app(#"SparkleView("x")"#))
        XCTAssertEqual(v.errors, ["Line 5: Cannot find 'SparkleView' in scope"])
    }

    func testAStubIsAcceptedAndListedAsOne() {
        XCTAssertEqual(Kiln.validate(app(#"Text("x").sensoryFeedback(.success, trigger: on)"#)).errors, [])
        let m = KRegistry.shared.manifest().symbols.first { $0.id == "modifier:sensoryFeedback" }
        XCTAssertEqual(m?.support, "stub")
    }

    // MARK: Argument kinds

    func testArgumentsAreEvaluatedAgainstTheirKinds() throws {
        let (_, views) = try body(app(#"""
        Text("\(1400) pages")
            .font(.title)
            .foregroundStyle(.secondary)
        """#))
        guard case .modified(let styled, let style)? = views.first?.kind, case .modified(let text, let font) = styled.kind,
              case .primitive("Text", let args, let labels, _) = text.kind else { return XCTFail("\(views)") }
        // A title literal is a LocalizedStringKey, so its number is grouped.
        XCTAssertEqual(args.first?.asString, "1,400 pages")
        XCTAssertEqual(labels, ["_literal"])
        // `.title` evaluated against Font; `.secondary` stays a style for the renderer.
        guard case .native(.font)? = font.args.first else { return XCTFail("\(font.args)") }
        guard case .native(.color)? = style.args.first else { return XCTFail("\(style.args)") }
    }

    func testABindingParameterNeedsABinding() {
        XCTAssertEqual(Kiln.validate(app(#"Toggle("x", isOn: on)"#)).errors,
                       ["Line 5: Toggle(_:isOn:): 'isOn' needs a binding such as $value, not Bool"])
        XCTAssertEqual(Kiln.validate(app(#"Toggle("x", isOn: .constant(true))"#)).errors, [])
    }

    // MARK: Availability

    func testAnOverloadTheOSDoesntHaveIsAnError() throws {
        let r = KRegistry.shared
        let b = KViewBridge(name: "KilnTestFuture", family: .host, support: .full, introduced: nil, notes: nil, source: "test")
        b.forms = [.init(overload: KOverload(params: [], availability: KilnAvailability(iOS: "99.0", macOS: "99.0")), render: { _ in AnyView(EmptyView()) })]
        r.removeClaim("view:KilnTestFuture")
        r.add(b)
        XCTAssertEqual(Kiln.validate(app("KilnTestFuture()")).errors, ["Line 5: KilnTestFuture() needs iOS 99.0"])
    }

    // MARK: Host bridges

    func testTheHostRegistersATypeThroughThePublicAPI() {
        var saved: [String: String] = [:]
        Kiln.registerType("KilnTestStore") { t in
            t.staticMethod("save", "_:string forKey:string") { call in
                saved[try call.string("forKey")] = try call.string(0)
                return .void
            }
            t.staticMethod("load", "_:string") { call in saved[try call.string(0)].map { KilnValue(string: $0) } ?? .nil }
        }
        let v = Kiln.validate(app(#"""
        Button("Save") {
                    KilnTestStore.save("hello", forKey: "greeting")
                    print(KilnTestStore.load("greeting") ?? "none")
                }
        """#))
        XCTAssertEqual(v.errors, [])
        XCTAssertEqual(saved, ["greeting": "hello"])
        let wrong = Kiln.validate(app(#"Button("Save") { KilnTestStore.save(1, forKey: "n") }"#))
        XCTAssertEqual(wrong.errors, ["Line 5: KilnTestStore.save(_:forKey:): the first argument should be String, not Int"])
    }

    // MARK: Observation

    /// A native `@Observable` object read by the app's `body` refreshes the
    /// view when it changes: the read happens inside SwiftUI's real `body`
    /// call, so SwiftUI's own observation tracking sees it.
    func testNativeObservableReadsAreTrackedBySwiftUI() throws {
        let model = KilnObservationProbe()
        var reads = 0
        Kiln.registerType("KilnTestModel") { t in
            t.staticProperty("shared") { _ in KilnValue(object: model, type: "KilnTestModel") }
            t.property("count") { call in
                reads += 1
                return KilnValue(int: (call.receiver.object as! KilnObservationProbe).count)
            }
        }
        let result = Kiln.run(app(#"Text("Count \(KilnTestModel.shared.count)")"#, state: ""))
        let view = try XCTUnwrap(result.view)
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        let host = NSHostingView(rootView: view.frame(width: 200, height: 100))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        #else
        let host = UIHostingController(rootView: view.frame(width: 200, height: 100))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.rootViewController = host
        window.isHidden = false
        #endif
        func settle() {
            for _ in 0..<10 {
                #if canImport(AppKit) && !targetEnvironment(macCatalyst)
                host.layoutSubtreeIfNeeded()
                #else
                host.view.layoutIfNeeded()
                #endif
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
        }
        settle()
        let first = reads
        XCTAssertGreaterThan(first, 0, "body never read the model")
        settle()
        XCTAssertEqual(reads, first, "body ran again with nothing changed")
        model.count = 5
        settle()
        XCTAssertGreaterThan(reads, first, "SwiftUI didn't re-run body when the native object changed")
        _ = window
    }

    // MARK: Families

    /// Each folder under Bridges/ is a family, and registers through its class.
    func testEveryBridgeFolderIsAFamilyThatRegisters() throws {
        let bridges = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources/Kiln/Bridges").standardized
        let folders = try FileManager.default.contentsOfDirectory(atPath: bridges.path).filter { !$0.hasPrefix(".") }
        let registered = Set(KRegistry.shared.allBridges.map(\.family.folder))
        for folder in folders {
            XCTAssertNotNil(KilnFamily.allCases.first { $0.folder == folder }, "\(folder) isn't a KilnFamily")
            XCTAssertTrue(registered.contains(folder), "\(folder) registers nothing: is its class named KilnBridges_\(folder)?")
        }
    }

    // MARK: The manifest

    /// `Packages/Kiln/kiln-manifest.json` is what the registry exports.
    /// `KILN_WRITE_MANIFEST=1 swift test --filter RegistryTests/testManifestIsCurrent`
    /// (or `Tools/manifest.sh`) rewrites it.
    func testManifestIsCurrent() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../kiln-manifest.json").standardized
        let wontDo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Tools/coverage/wont-do.json").standardized
        let data = try KRegistry.shared.completeManifest(wontDo: wontDo).encoded()
        if ProcessInfo.processInfo.environment["KILN_WRITE_MANIFEST"] == "1" {
            try data.write(to: url)
            return
        }
        let committed = try Data(contentsOf: url)
        XCTAssertEqual(String(decoding: committed, as: UTF8.self), String(decoding: data, as: UTF8.self),
                       "kiln-manifest.json is stale: run Tools/manifest.sh")
    }

    func testTheManifestListsEveryViewAndModifierWithOverloads() throws {
        let symbols = KRegistry.shared.manifest(includeHost: false).symbols
        XCTAssertEqual(Set(symbols.map(\.id)).count, symbols.count)
        // What SwiftUI hands the app and it never writes as a call (`Subview`) has no initializers.
        let handedOver = Set(KRegistry.shared.views.values.filter { !$0.constructible }.map { "view:" + $0.name })
        for s in symbols where (s.kind == "view" || s.kind == "modifier" || s.kind == "content") && !handedOver.contains(s.id) {
            XCTAssertNotNil(s.overloads, s.id)
            XCTAssertFalse(s.overloads?.isEmpty ?? true, s.id)
        }
        XCTAssertTrue(symbols.contains { $0.id == "view:Toggle" && $0.overloads?.contains { $0.labels == ["_", "isOn"] } == true })
        XCTAssertTrue(symbols.contains { $0.id == "modifier:ChartContent.annotation" && $0.support == "full" })
        XCTAssertTrue(symbols.contains { $0.id == "style:PickerStyle.segmented" })
        XCTAssertTrue(symbols.contains { $0.id == "member:Color.red" })
    }
}

@Observable
final class KilnObservationProbe {
    var count = 0
}
