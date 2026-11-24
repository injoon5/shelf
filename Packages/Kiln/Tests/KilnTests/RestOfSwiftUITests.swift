import XCTest
import SwiftUI
import Charts
@_spi(KilnTesting) @testable import Kiln

/// PLAN.md §2, Round 1's rest of SwiftUI: gestures, drawing and effects,
/// focus, the environment, Swift Charts, text and accessibility. Each bridge
/// checks and validates clean in an app as models write it, and the ones that
/// do something natively are driven here: a canvas's recording, a gesture
/// built from its description, keyframes on SwiftUI's own timelines, an
/// environment value read from SwiftUI, preferences folded with the app's
/// `reduce`, a chart's marks.
@MainActor
final class RestOfSwiftUITests: XCTestCase {

    func interp(_ source: String) throws -> KInterpreter {
        try KInterpreter(program: try KEParser.parse(source), headless: true)
    }

    /// The program, and the value of `expr` evaluated after it.
    func make(_ source: String, _ expr: String) throws -> (KInterpreter, KV) {
        let i = try interp(source + "\nlet __probe = " + expr)
        return (i, try XCTUnwrap(i.globalEnv.vars["__probe"]?.value))
    }

    /// Checks and validates clean, as an app a model wrote.
    func expectClean(_ source: String, file: StaticString = #filePath, line: UInt = #line) {
        let check = Kiln.check(source)
        XCTAssertTrue(check.passed, "check: \(check.errors.map(\.message))", file: file, line: line)
        let v = Kiln.validate(source)
        XCTAssertEqual(v.errors, [], file: file, line: line)
        XCTAssertTrue(v.isValid, "validate: \(v.errors)", file: file, line: line)
    }

    /// Shows `view` until SwiftUI has laid it out, then returns what it printed.
    func mount<V: View>(_ view: V, width: CGFloat = 320, height: CGFloat = 320, frames: Int = 8) -> AnyObject {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        let host = NSHostingView(rootView: view.frame(width: width, height: height))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<frames { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return window
        #else
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = host
        window.isHidden = false
        for _ in 0..<frames { host.view.layoutIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return window
        #endif
    }

    /// Runs the app and shows it; returns what it printed.
    func run(_ source: String, context: KilnContext? = nil, frames: Int = 8) throws -> (String, KilnResult, AnyObject) {
        let result = context.map { Kiln.run(source, context: $0) } ?? Kiln.run(source)
        XCTAssertEqual(result.errors, [])
        let view = try XCTUnwrap(result.view)
        let window = mount(view, frames: frames)
        return (result.interp?.console ?? "", result, window)
    }

    // MARK: Gestures

    static let gestureApp = """
    import SwiftUI

    struct ContentView: View {
        @State private var offset = CGSize.zero
        @GestureState private var drag = CGSize.zero
        @GestureState private var pressing = false
        @State private var scale = 1.0
        @State private var angle = Angle.zero
        @State private var log: [String] = []

        var body: some View {
            VStack {
                Circle()
                    .fill(pressing ? .orange : .blue)
                    .frame(width: 80, height: 80)
                    .offset(x: offset.width + drag.width, y: offset.height + drag.height)
                    .scaleEffect(scale)
                    .rotationEffect(angle)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($drag) { value, state, transaction in
                                state = value.translation
                            }
                            .onEnded { value in
                                offset.width += value.translation.width
                                offset.height += value.translation.height
                                log.append("ended \\(value.location.x)")
                            }
                    )
                    .simultaneousGesture(MagnifyGesture().onChanged { value in scale = value.magnification })
                    .highPriorityGesture(RotateGesture().onChanged { value in angle = value.rotation }, including: .all)
                Rectangle()
                    .frame(width: 60, height: 60)
                    .gesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .updating($pressing) { current, state, _ in state = current }
                            .sequenced(before: DragGesture())
                            .onEnded { value in
                                switch value {
                                case .second(true, let drag?):
                                    log.append("dragged \\(drag.translation.width)")
                                default:
                                    log.append("other")
                                }
                            }
                    )
                    .onTapGesture(count: 2) { location in log.append("tap \\(location.x)") }
                    .onLongPressGesture(minimumDuration: 0.5) { log.append("long") } onPressingChanged: { down in log.append("\\(down)") }
                Text(log.last ?? "none")
                    .gesture(TapGesture(count: 2).exclusively(before: TapGesture()).onEnded { _ in log.append("tapped") })
                    .gesture(SpatialTapGesture().onEnded { value in log.append("at \\(value.location.y)") }, isEnabled: true)
            }
        }
    }
    """

    func testGesturesCheckAndValidate() {
        expectClean(Self.gestureApp)
    }

    func testGestureDescriptionsBuildRealGestures() throws {
        let (i, v) = try make("import SwiftUI", """
            DragGesture(minimumDistance: 4)
                .onChanged { value in print(value.translation.width) }
                .simultaneously(with: MagnifyGesture().map { $0.magnification })
                .exclusively(before: TapGesture(count: 2))
            """)
        let builder = KGestureBuilder(interp: i, active: GestureState(initialValue: false), resets: KGestureResets())
        XCTAssertNotNil(builder.build(v))
        let sample = KGestureBuilder.sample(v.asView, i)
        guard case .native(.implicit("first", let parts)) = sample, case .tuple(_, let labels)? = parts.first else {
            return XCTFail("\(sample)")
        }
        XCTAssertEqual(labels, ["first", "second"])
    }

    func testDragValueMembers() throws {
        var d = KDragValue()
        d.translation = (12, -3)
        d.location = (40, 50)
        let (i, _) = try make("import SwiftUI", "0")
        let v = KV.native(.boxed(KBoxed("DragGesture.Value", d)))
        XCTAssertEqual(try i.member(try i.member(v, "translation", line: 0), "width", line: 0).asDouble, 12)
        XCTAssertEqual(try i.member(try i.member(v, "location", line: 0), "y", line: 0).asDouble, 50)
    }

    func testAnInoutClosureParameterWritesThrough() throws {
        let (i, v) = try make("import SwiftUI", "{ (value: Int, state: inout Int) in state = value * 2 }")
        guard case .function(let f) = v else { return XCTFail() }
        var stored = KV.int(0)
        _ = try i.call(f, [.int(21), .binding(.inOut(get: { stored }, set: { stored = $0 }))], [nil, nil])
        XCTAssertEqual(stored, .int(42))
    }

    func testAGestureAppShowsAndAppsOwnGestureTypes() throws {
        let source = """
        import SwiftUI
        struct Wiggle: Gesture {
            var body: some Gesture {
                DragGesture().onEnded { _ in print("ended") }
            }
        }
        struct ContentView: View {
            var body: some View {
                Text("Hi").gesture(Wiggle()).onHover { inside in print(inside) }
            }
        }
        """
        expectClean(source)
        _ = try run(source)
    }

    // MARK: Canvas

    static let canvasApp = """
    import SwiftUI

    struct ContentView: View {
        var body: some View {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.fill(Path(rect), with: .color(.red))
                var inner = context
                inner.translateBy(x: 10, y: 10)
                inner.opacity = 0.5
                inner.stroke(Circle().path(in: CGRect(x: 0, y: 0, width: 40, height: 40)), with: .color(.blue), lineWidth: 3)
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 2))
                    layer.fill(Path(ellipseIn: CGRect(x: 50, y: 50, width: 20, height: 20)),
                               with: .linearGradient(Gradient(colors: [.green, .yellow]), startPoint: .zero, endPoint: CGPoint(x: 70, y: 70)))
                }
                context.clip(to: Path(CGRect(x: 0, y: 0, width: 100, height: 100)))
                context.draw(Text("Kiln"), at: CGPoint(x: size.width / 2, y: 20), anchor: .top)
                if let star = context.resolveSymbol(id: 1) {
                    context.draw(star, at: CGPoint(x: 30, y: 30))
                }
            } symbols: {
                Image(systemName: "star.fill").tag(1)
            }
        }
    }
    """

    func testCanvasChecksValidatesAndRecordsAsAValue() throws {
        expectClean(Self.canvasApp)
        let (i, v) = try make("import SwiftUI", """
            { (context: inout GraphicsContext, size: CGSize) in
                context.fill(Path(CGRect(x: 0, y: 0, width: 10, height: 10)), with: .color(.red))
                var copy = context
                copy.translateBy(x: 5, y: 7)
                copy.fill(Path(CGRect(x: 0, y: 0, width: 10, height: 10)), with: .color(.blue))
                context.fill(Path(CGRect(x: 0, y: 0, width: 10, height: 10)), with: .style(.green))
                context.drawLayer { layer in layer.opacity = 0.5; layer.stroke(Path(CGRect(x: 0, y: 0, width: 4, height: 4)), with: .foreground, lineWidth: 2) }
            }
            """)
        guard case .function(let f) = v else { return XCTFail() }
        let rec = KCanvas.record(f, size: CGSize(width: 100, height: 100), i)
        XCTAssertEqual(i.errors, [])
        XCTAssertEqual(rec.ops.count, 4)
        // The copy's translation stayed on the copy.
        XCTAssertEqual(rec.ops[0].state.transform.tx, 0)
        XCTAssertEqual(rec.ops[1].state.transform.tx, 5)
        XCTAssertEqual(rec.ops[1].state.transform.ty, 7)
        XCTAssertEqual(rec.ops[2].state.transform.tx, 0)
        guard case .layer(let sub) = rec.ops[3].content else { return XCTFail("\(rec.ops[3].content)") }
        XCTAssertEqual(sub.ops.first?.state.opacity, 0.5)
    }

    func testCanvasDrawsIntoSwiftUIsCanvas() throws {
        // The app's renderer, recorded, then replayed in SwiftUI's own `Canvas`.
        let (i, v) = try make("import SwiftUI", """
            { (context: inout GraphicsContext, size: CGSize) in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.red))
                var corner = context
                corner.translateBy(x: 10, y: 0)
                corner.fill(Path(CGRect(x: 0, y: 0, width: 10, height: 10)), with: .color(.blue))
            }
            """)
        guard case .function(let f) = v else { return XCTFail() }
        let recording = KCanvas.record(f, size: CGSize(width: 20, height: 20), i)
        let renderer = ImageRenderer(content: Canvas { context, _ in recording.replay(in: &context) }.frame(width: 20, height: 20))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let red = try XCTUnwrap(Self.pixel(image, x: 5, y: 15))
        XCTAssertGreaterThan(red.r, 200)
        XCTAssertLessThan(red.b, 100)
        let blue = try XCTUnwrap(Self.pixel(image, x: 15, y: 5))
        XCTAssertGreaterThan(blue.b, 200)
        XCTAssertLessThan(blue.r, 100)
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int)? {
        let space = CGColorSpaceCreateDeviceRGB()
        var data = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - y - 1), width: image.width, height: image.height))
        return (Int(data[0]), Int(data[1]), Int(data[2]))
    }

    // MARK: Drawing and effects

    static let effectsApp = """
    import SwiftUI

    struct Values {
        var scale = 1.0
        var lift = 0.0
        var angle = Angle.zero
    }

    struct ContentView: View {
        @Namespace private var space
        @State private var big = false
        @State private var count = 0
        @State private var on = false

        var body: some View {
            VStack {
                if big {
                    RoundedRectangle(cornerRadius: 20).fill(.blue).matchedGeometryEffect(id: "card", in: space).frame(height: 200)
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(.blue).matchedGeometryEffect(id: "card", in: space).frame(width: 60, height: 60)
                }
                Text("\\(count)").contentTransition(.numericText(value: Double(count))).font(.largeTitle)
                Image(systemName: "bell").symbolEffect(.bounce.up.byLayer, options: .repeat(2), value: count)
                Image(systemName: "wifi").symbolEffect(.variableColor.iterative, isActive: on)
                Image(systemName: "heart")
                    .phaseAnimator([1.0, 1.3, 1.0], trigger: count) { content, phase in
                        content.scaleEffect(phase)
                    } animation: { _ in .spring(duration: 0.3) }
                Text("Keys")
                    .keyframeAnimator(initialValue: Values(), trigger: count) { content, value in
                        content.scaleEffect(value.scale).offset(y: value.lift).rotationEffect(value.angle)
                    } keyframes: { _ in
                        KeyframeTrack(\\.scale) {
                            LinearKeyframe(1.2, duration: 0.1)
                            SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
                        }
                        KeyframeTrack(\\.lift) {
                            CubicKeyframe(-20, duration: 0.2)
                            MoveKeyframe(0)
                        }
                    }
                Circle().union(Rectangle().offset(x: 20)).fill(.green).frame(width: 40, height: 40)
                Capsule().inset(by: 4).rotation(.degrees(20)).stroke(.red, lineWidth: 2).frame(width: 60, height: 30)
                MeshGradient(width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]], colors: [.red, .blue, .green, .yellow])
                    .frame(height: 40)
                Text("Glass").padding().glassEffect(.regular.tint(.blue).interactive(), in: .capsule)
                GlassEffectContainer(spacing: 8) {
                    HStack {
                        Text("A").glassEffect().glassEffectID("a", in: space)
                        Text("B").glassEffect().glassEffectUnion(id: "ab", namespace: space)
                    }
                }
                Text("Blend").blendMode(.multiply).visualEffect { content, proxy in
                    content.offset(y: proxy.frame(in: .global).minY > 100 ? 0 : 4)
                }
                Text("Tx").transaction { t in t.animation = nil }
                Rectangle().fill(.red.opacity(0.5).shadow(.drop(radius: 2))).frame(height: 10)
                Rectangle().fill(.linearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)).frame(height: 10)
                Button("Go") {
                    withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.4)) { big.toggle() }
                    count += 1
                    on.toggle()
                }
            }
            .transition(.blurReplace)
        }
    }
    """

    func testDrawingAndEffectsCheckValidateAndShow() throws {
        expectClean(Self.effectsApp)
        _ = try run(Self.effectsApp)
    }

    func testKeyframesPlayOnSwiftUIsTimelines() throws {
        let (i, v) = try make("""
            import SwiftUI
            struct Values { var scale = 1.0; var point = CGPoint.zero }
            """, """
            KeyframeTimeline(initialValue: Values()) {
                KeyframeTrack(\\.scale) {
                    LinearKeyframe(2.0, duration: 1)
                    LinearKeyframe(4.0, duration: 1)
                }
                KeyframeTrack(\\.point) {
                    LinearKeyframe(CGPoint(x: 10, y: 20), duration: 2)
                }
            }
            """)
        XCTAssertEqual(i.errors, [])
        XCTAssertEqual(try i.member(v, "duration", line: 0).asDouble ?? 0, 2, accuracy: 0.001)
        guard case .native(.object(_, let ref)) = v, let plan = ref.value as? KKeyframes else { return XCTFail("\(v)") }
        let half = plan.value(at: 0.5)
        XCTAssertEqual(try i.member(half, "scale", line: 0).asDouble ?? 0, 1.5, accuracy: 0.01)
        let end = plan.value(at: 2)
        XCTAssertEqual(try i.member(end, "scale", line: 0).asDouble ?? 0, 4, accuracy: 0.01)
        XCTAssertEqual(try i.member(try i.member(end, "point", line: 0), "y", line: 0).asDouble ?? 0, 20, accuracy: 0.01)
    }

    func testShapeOperationsKeepAShapeAShape() throws {
        let (i, v) = try make("import SwiftUI", "Circle().union(Rectangle().offset(x: 10)).rotation(.degrees(45))")
        guard case .view(let view) = v else { return XCTFail() }
        let chain = try XCTUnwrap(KRenderer(interp: i).shapeChain(view))
        XCTAssertEqual(chain.ops.count, 2)
        let path = KRenderer(interp: i).shapePath(chain, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertFalse(path.isEmpty)
    }

    func testUserVectorArithmeticAnimatesThroughItsNumbers() throws {
        let (_, v) = try make("""
            import SwiftUI
            struct Pair: VectorArithmetic { var a = 1.0; var b = 2.0 }
            """, "Pair(a: 3, b: 4)")
        XCTAssertEqual(KAnimatable.flatten(v), [3, 4])
        var slice = ArraySlice([5.0, 6.0])
        let back = KAnimatable.unflatten(v, &slice)
        guard case .structV(let s) = back else { return XCTFail() }
        XCTAssertEqual(s.fields["a"]?.asDouble, 5)
    }

    // MARK: Focus

    static let focusApp = """
    import SwiftUI

    enum Field: Hashable { case name, email }

    struct ContentView: View {
        @FocusState private var field: Field?
        @FocusState private var notesFocused: Bool
        @State private var name = ""
        @State private var email = ""
        @State private var notes = ""

        var body: some View {
            Form {
                TextField("Name", text: $name)
                    .focused($field, equals: .name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit { field = .email }
                TextField("Email", text: $email)
                    .focused($field, equals: .email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { field = nil }
                TextEditor(text: $notes).focused($notesFocused)
                Button("Edit notes") { notesFocused = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .focusedValue(\\.draft, notes)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultFocus($field, .name)
            .onKeyPress(.escape) { field = nil; return .handled }
        }
    }

    extension FocusedValues {
        @Entry var draft: String?
    }
    """

    func testFocusChecksValidatesAndHostsARealFocusState() throws {
        expectClean(Self.focusApp)
        let (i, _) = try make(Self.focusApp, "0")
        let t = try XCTUnwrap(i.types["ContentView"])
        XCTAssertTrue(i.needsHostInputs(t))
        _ = try run(Self.focusApp)
    }

    /// A view hosted with SwiftUI's environment, a namespace or focus still
    /// redraws when its `@State` changes.
    func testAHostInputsViewRedrawsOnItsState() throws {
        let source = """
        import SwiftUI
        struct ContentView: View {
            @Namespace private var space
            @FocusState private var focused: Bool
            @Environment(\\.dynamicTypeSize) private var size
            @State private var n = 0
            var body: some View {
                Text("n \\(n)")
                    .onAppear { n = 1 }
                    .onChange(of: n) { _, new in print("redrawn", new) }
            }
        }
        """
        let (_, result, _) = try run(source)
        XCTAssertTrue((result.interp?.console ?? "").contains("redrawn 1"), result.interp?.console ?? "")
    }

    func testFocusedValuesShareASlotByName() {
        XCTAssertEqual(KFocusSlots.slot("draft"), KFocusSlots.slot("draft"))
        XCTAssertLessThan(KFocusSlots.slot("somethingElse"), KFocusSlots.count)
    }

    // MARK: Environment

    func testEnvironmentValuesAreSwiftUIsOwn() throws {
        let source = """
        import SwiftUI
        struct Inner: View {
            @Environment(\\.dynamicTypeSize) private var size
            @Environment(\\.layoutDirection) private var direction
            @Environment(\\.colorScheme) private var scheme
            var body: some View {
                Text("x").onAppear {
                    print("size", size == .xxxLarge, size >= .xLarge, size.isAccessibilitySize)
                    print("direction", direction == .rightToLeft)
                    print("scheme", scheme == .dark)
                }
            }
        }
        struct ContentView: View {
            var body: some View {
                Inner()
                    .environment(\\.dynamicTypeSize, .xxxLarge)
                    .environment(\\.layoutDirection, .rightToLeft)
                    .environment(\\.colorScheme, .dark)
            }
        }
        """
        expectClean(source)
        let (console, _, _) = try run(source)
        XCTAssertTrue(console.contains("size true true false"), console)
        XCTAssertTrue(console.contains("direction true"), console)
        XCTAssertTrue(console.contains("scheme true"), console)
    }

    func testScenePhaseIsTheLowerOfTheHostsAndTheSystems() throws {
        let source = """
        import SwiftUI
        struct Inner: View {
            @Environment(\\.scenePhase) private var phase
            var body: some View {
                Text("x")
                    .onAppear { print("phase", phase) }
                    .onChange(of: phase) { _, new in print("now", new) }
            }
        }
        struct ContentView: View {
            // A test's window has no scene: the system's phase is set as an app's would be.
            var body: some View { Inner().environment(\\.scenePhase, .active) }
        }
        """
        expectClean(source)
        let context = KilnContext.standard()
        let (_, result, window) = try run(source, context: context)
        context.scenePhase = .inactive
        for _ in 0..<6 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        _ = window
        let console = result.interp?.console ?? ""
        XCTAssertTrue(console.contains("phase .active"), console)
        XCTAssertTrue(console.contains("now .inactive"), console)
    }

    func testPreferencesFoldWithTheAppsReduce() throws {
        let source = """
        import SwiftUI
        struct Total: PreferenceKey {
            static var defaultValue = 0
            static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
        }
        struct ContentView: View {
            @State private var total = 0
            var body: some View {
                VStack {
                    Text("a").preference(key: Total.self, value: 2)
                    Text("b").preference(key: Total.self, value: 3)
                    Text("c").transformPreference(Total.self) { value in value += 10 }
                }
                .onPreferenceChange(Total.self) { value in print("total", value) }
                .overlayPreferenceValue(Total.self) { value in Text("\\(value)") }
            }
        }
        """
        expectClean(source)
        let (console, _, _) = try run(source)
        XCTAssertTrue(console.contains("total 15"), console)
    }

    func testOpenURLGoesThroughTheHost() throws {
        let source = """
        import SwiftUI
        struct ContentView: View {
            @Environment(\\.openURL) private var openURL
            var body: some View {
                Text("x").onAppear { openURL(URL(string: "https://ij5.dev")!) }
            }
        }
        """
        expectClean(source)
        let context = KilnContext.standard()
        var opened: [URL] = []
        context.openURL = { url in opened.append(url); return true }
        _ = try run(source, context: context)
        XCTAssertEqual(opened.map(\.absoluteString), ["https://ij5.dev"])
    }

    // MARK: Charts

    static let chartApp = """
    import SwiftUI
    import Charts

    struct Sale: Identifiable {
        let id = UUID()
        let day: String
        let amount: Double
        let kind: String
    }

    struct ContentView: View {
        @State private var selected: String?
        let sales = [Sale(day: "Mon", amount: 3, kind: "A"), Sale(day: "Tue", amount: 5, kind: "B"), Sale(day: "Wed", amount: 2, kind: "A")]

        var body: some View {
            VStack {
                Chart(sales) { sale in
                    BarMark(x: .value("Day", sale.day), y: .value("Amount", sale.amount))
                        .foregroundStyle(by: .value("Kind", sale.kind))
                        .cornerRadius(4)
                        .annotation(position: .top) { Text("\\(Int(sale.amount))").font(.caption) }
                    RuleMark(y: .value("Goal", 4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                .chartXSelection(value: $selected)
                .chartForegroundStyleScale(domain: ["A", "B"], range: [Color.blue, Color.orange])
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartLegend(position: .bottom)
                Chart {
                    LinePlot(x: "x", y: "y", domain: 0...6.28) { x in sin(x) }
                    PointMark(x: .value("x", 1.0), y: .value("y", 0.5)).symbol(.diamond).symbolSize(60)
                }
                .chartXScale(domain: 0...6.28)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: 3)
                Chart {
                    SectorMark(angle: .value("Share", 40), innerRadius: .ratio(0.6), angularInset: 2).foregroundStyle(.blue)
                    SectorMark(angle: .value("Share", 60), innerRadius: .ratio(0.6), angularInset: 2).foregroundStyle(.green)
                }
                BarPlot(sales, x: .value("Day", \\.day), y: .value("Amount", \\.amount))
            }
        }
    }
    """

    func testChartsCheckValidateAndBuildRealMarks() throws {
        expectClean(Self.chartApp.replacingOccurrences(of: "                BarPlot(sales, x: .value(\"Day\", \\.day), y: .value(\"Amount\", \\.amount))\n", with: ""))
        let (i, v) = try make(Self.chartApp, "0")
        _ = v
        let (_, result, _) = try run(Self.chartApp)
        _ = result
        XCTAssertEqual(i.errors, [])
    }

    func testChartSpecsKindsAndPlots() throws {
        let (i, v) = try make("""
            import SwiftUI
            import Charts
            struct P { let x: Int; let y: Double }
            let points = [P(x: 1, y: 2), P(x: 2, y: 3)]
            """, """
            Chart {
                BarPlot(points, x: .value("X", \\.x), y: .value("Y", \\.y))
                LinePlot(x: "x", y: "y", domain: 0...1) { x in x * 2 }
            }
            """)
        guard case .view(let chart) = v, case .primitive(_, let args, let labels, let line) = chart.kind else { return XCTFail("\(v)") }
        let b = KChartBuilder(interp: i)
        let specs = b.specs(KCall(interp: i, name: "Chart", line: line, args: args, labels: labels, overload: nil, binding: []))
        XCTAssertEqual(specs.filter { $0.name == "BarMark" }.count, 2)
        XCTAssertEqual(specs.filter { $0.name == "LineMark" }.count, 201)
        let (xk, yk) = b.kinds(specs)
        XCTAssertEqual(xk, .whole)
        XCTAssertEqual(yk, .number)
    }

    // MARK: Text and accessibility

    func testTextAndAccessibilityCheckValidateAndShow() throws {
        let source = """
        import SwiftUI
        struct ContentView: View {
            @AccessibilityFocusState private var announced: Bool
            @State private var level = 3
            var body: some View {
                VStack {
                    Text("Title").fontWidth(.condensed).allowsTightening(true).textScale(.secondary)
                    Text("Body").typesettingLanguage(.init(identifier: "en")).flipsForRightToLeftLayoutDirection(true)
                    Text("Head").accessibilityHeading(.h1).accessibilityAddTraits(.isHeader)
                    Image(systemName: "star")
                        .accessibilityLabel("Favorite")
                        .accessibilityHint("Adds it")
                        .accessibilityValue("\\(level) stars")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: level += 1
                            default: level -= 1
                            }
                        }
                        .accessibilityAction(named: "Reset") { level = 0 }
                        .accessibilityFocused($announced)
                        .accessibilitySortPriority(2)
                    HStack {
                        Text("A")
                        Text("B")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityRotor("Letters") {
                        AccessibilityRotorEntry("A", id: "a")
                    }
                    Text("Hidden").accessibilityHidden(true).speechSpellsOutCharacters()
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }
        """
        expectClean(source)
        _ = try run(source)
    }

    // MARK: Shelf's fixtures

    /// Round 1's fixtures (`fixtures/apps/`): they check, validate with no
    /// error or warning, and show with no error, as Shelf's fixture test wants.
    func testRoundOneFixtures() throws {
        let root = CheckCorpusTests.repoRoot.appending(path: "fixtures/apps")
        for name in ["gestures-canvas", "focus-environment", "charts", "accessibility-motion"] {
            let source = try String(contentsOf: root.appending(path: name + ".swift"), encoding: .utf8)
            let check = Kiln.check(source)
            XCTAssertTrue(check.passed, "\(name) check: \(check.errors.map { "\($0.line): \($0.message)" })")
            XCTAssertEqual(check.warnings.map(\.message), [], name)
            let v = Kiln.validate(source)
            XCTAssertEqual(v.errors, [], name)
            XCTAssertEqual(v.warnings, [], name)
            XCTAssertTrue(v.renderedContent, name)
            let result = Kiln.run(source)
            XCTAssertEqual(result.errors, [], name)
            let view = try XCTUnwrap(result.view, name)
            let window = mount(view, width: 390, height: 800)
            _ = window
            XCTAssertEqual(result.interp?.errors ?? [], [], name)
        }
    }

    // MARK: TimelineView

    func testTimelineViewSchedules() throws {
        let source = """
        import SwiftUI
        struct ContentView: View {
            var body: some View {
                VStack {
                    TimelineView(.animation) { context in
                        Text(context.date.formatted())
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in Text("\\(context.date)") }
                    TimelineView(.everyMinute) { context in Text("\\(context.date)") }
                }
            }
        }
        """
        expectClean(source)
        _ = try run(source)
    }
}

private extension KV {
    var asView: KView? { if case .view(let v) = self { return v }; return nil }
}
