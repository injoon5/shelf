import XCTest
import SwiftUI
import UniformTypeIdentifiers
#if canImport(CoreLocation)
import CoreLocation
#endif
@_spi(KilnTesting) @testable import Kiln

/// PLAN.md §1.5: native code calling the app's code through protocol
/// proxies. One test (or more) per proxy: the requirement is called, its
/// result reaches SwiftUI, and a wrong declaration reads correctly.
@MainActor
final class ProxyTests: XCTestCase {

    func interp(_ source: String, headless: Bool = true) throws -> KInterpreter {
        try KInterpreter(program: try KEParser.parse(source), headless: headless)
    }

    /// The program, and the value of `expr` evaluated after it.
    func make(_ source: String, _ expr: String) throws -> (KInterpreter, KV) {
        let i = try interp(source + "\nlet __probe = " + expr)
        return (i, try XCTUnwrap(i.globalEnv.vars["__probe"]?.value))
    }

    /// Shows `view` in a real hosting view until SwiftUI has laid it out.
    func mount<V: View>(_ view: V, width: CGFloat = 300, height: CGFloat = 300, frames: Int = 10) -> AnyObject {
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

    func settle(_ window: AnyObject, frames: Int = 10) {
        for _ in 0..<frames {
            #if canImport(AppKit) && !targetEnvironment(macCatalyst)
            (window as? NSWindow)?.contentView?.layoutSubtreeIfNeeded()
            #else
            (window as? UIWindow)?.layoutIfNeeded()
            #endif
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    // MARK: Requirements

    func testRequirementsParse() {
        let a = KRequirement(parsing: "sizeThatFits(proposal:subviews:cache:)")
        XCTAssertEqual(a.name, "sizeThatFits")
        XCTAssertEqual(a.labels, ["proposal", "subviews", "cache"])
        XCTAssertEqual(a.display, "sizeThatFits(proposal:subviews:cache:)")
        XCTAssertFalse(a.isOptional)
        let b = KRequirement(parsing: "updateCache(_:subviews:)?")
        XCTAssertEqual(b.labels, [nil, "subviews"])
        XCTAssertTrue(b.isOptional)
        XCTAssertEqual(b.declared, "updateCache(_:subviews:)?")
        let c = KRequirement(parsing: "static transferRepresentation")
        XCTAssertTrue(c.isStatic)
        XCTAssertNil(c.labels)
        let d = KRequirement(parsing: "async perform()")
        XCTAssertTrue(d.isAsync)
        XCTAssertEqual(d.labels, [])
        XCTAssertEqual(KRegistry.shared.protocols["Layout"]?.requirements.first, "sizeThatFits(proposal:subviews:cache:)")
    }

    func testMissingNativeRequirementIsAnErrorWithTheTypesLine() throws {
        let i = try interp("""
        import SwiftUI

        struct Wave: Shape {
            var amplitude = 1.0
        }
        struct Flow: Layout {
            func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { .zero }
        }
        """)
        XCTAssertTrue(i.errors.contains("Line 3: 'Wave' doesn't conform to 'Shape': it has no path(in:)"), "\(i.errors)")
        XCTAssertTrue(i.errors.contains("Line 6: 'Flow' doesn't conform to 'Layout': it has no placeSubviews(in:proposal:subviews:cache:)"), "\(i.errors)")
    }

    func testOptionalRequirementsAndRepresentablesAreNotRequired() throws {
        let i = try interp("""
        struct Box: Shape {
            func path(in rect: CGRect) -> Path { Path(rect) }
        }
        struct Card: ViewModifier {
            func body(content: Content) -> some View { content.padding() }
        }
        """)
        XCTAssertEqual(i.errors, [])
    }

    // MARK: Shape and Animatable

    func shapePath(_ interp: KInterpreter, _ v: KV, in rect: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)) -> Path? {
        (interp.proxy(for: v, as: "Shape") as? AnyShape)?.path(in: rect)
    }

    func testShapeProxyDrawsTheAppsPath() throws {
        let (i, v) = try make("""
        struct Bar: Shape {
            var fraction: Double
            func path(in rect: CGRect) -> Path {
                Path(CGRect(x: 0, y: 0, width: rect.width * fraction, height: rect.height))
            }
        }
        """, "Bar(fraction: 0.25)")
        let path = try XCTUnwrap(shapePath(i, v))
        XCTAssertEqual(path.boundingRect.width, 25, accuracy: 0.001)
        XCTAssertEqual(i.errors, [])
    }

    func testHandWrittenAnimatableDataInterpolates() throws {
        let (i, v) = try make("""
        struct Bar: Shape {
            var fraction: Double
            var animatableData: Double {
                get { fraction }
                set { fraction = newValue }
            }
            func path(in rect: CGRect) -> Path {
                Path(CGRect(x: 0, y: 0, width: rect.width * fraction, height: rect.height))
            }
        }
        """, "Bar(fraction: 0.25)")
        var shape = KUserShape(app: try XCTUnwrap(KAppValue(v, i)))
        XCTAssertEqual(shape.animatableData, KAnimVector([0.25]))
        shape.animatableData = KAnimVector([0.75])
        XCTAssertEqual(shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 100)).boundingRect.width, 75, accuracy: 0.001)
        XCTAssertEqual(i.errors, [])
    }

    func testAnimatablePairNestsAndRoundTrips() throws {
        let (i, v) = try make("""
        struct Segment: Shape {
            var start: Double
            var end: Double
            var corner: CGPoint
            var animatableData: AnimatablePair<AnimatablePair<Double, Double>, CGPoint> {
                get { AnimatablePair(AnimatablePair(start, end), corner) }
                set {
                    start = newValue.first.first
                    end = newValue.first.second
                    corner = newValue.second
                }
            }
            func path(in rect: CGRect) -> Path {
                Path(CGRect(x: start, y: corner.y, width: end - start, height: corner.x))
            }
        }
        """, "Segment(start: 10, end: 20, corner: CGPoint(x: 5, y: 6))")
        var shape = KUserShape(app: try XCTUnwrap(KAppValue(v, i)))
        XCTAssertEqual(shape.animatableData, KAnimVector([10, 20, 5, 6]))
        // Halfway to (0, 40, (15, 6)), as SwiftUI would interpolate.
        var to = KAnimVector([0, 40, 15, 6])
        to -= shape.animatableData
        to.scale(by: 0.5)
        shape.animatableData += to
        let r = shape.path(in: .zero).boundingRect
        XCTAssertEqual(r.minX, 5, accuracy: 0.001)
        XCTAssertEqual(r.width, 25, accuracy: 0.001)
        XCTAssertEqual(r.height, 10, accuracy: 0.001)
        XCTAssertEqual(i.errors, [])
    }

    func testAnimatableMacroPropertiesInterpolate() throws {
        let (i, v) = try make("""
        @Animatable
        struct Ring: Shape {
            var progress: Double
            var width: CGFloat
            @AnimatableIgnored var label = "x"
            func path(in rect: CGRect) -> Path {
                Path(CGRect(x: 0, y: 0, width: progress * 100, height: width))
            }
        }
        """, "Ring(progress: 0.5, width: 4)")
        var shape = KUserShape(app: try XCTUnwrap(KAppValue(v, i)))
        XCTAssertEqual(shape.animatableData, KAnimVector([0.5, 4]))
        shape.animatableData = KAnimVector([0.1, 8])
        let r = shape.path(in: .zero).boundingRect
        XCTAssertEqual(r.width, 10, accuracy: 0.001)
        XCTAssertEqual(r.height, 8, accuracy: 0.001)
    }

    func testDefaultAnimatableDataIsEmpty() throws {
        let (i, v) = try make("""
        struct Box: Shape {
            var inset = 3.0
            func path(in rect: CGRect) -> Path { Path(rect.insetBy(dx: inset, dy: inset)) }
        }
        """, "Box()")
        let shape = KUserShape(app: try XCTUnwrap(KAppValue(v, i)))
        XCTAssertEqual(shape.animatableData, .zero)
    }

    func testShapeErrorIsReportedWithItsLine() throws {
        let (i, v) = try make("""
        struct Broken: Shape {
            func path(in rect: CGRect) -> Path {
                let xs: [Double] = []
                return Path(CGRect(x: xs[3], y: 0, width: 1, height: 1))
            }
        }
        """, "Broken()")
        let path = try XCTUnwrap(shapePath(i, v))
        XCTAssertTrue(path.isEmpty)
        XCTAssertTrue(i.errors.contains { $0.hasPrefix("Line 4: Index out of range") }, "\(i.errors)")
    }

    // MARK: ViewModifier

    func testViewModifierRunsWithSwiftUIsContent() throws {
        let source = """
        import SwiftUI
        struct Card: ViewModifier {
            var title: String
            func body(content: Content) -> some View {
                VStack {
                    Text(title)
                    content.padding()
                }
                .onAppear { print("card", title) }
            }
        }
        extension View {
            func card(_ title: String) -> some View { modifier(Card(title: title)) }
        }
        struct ContentView: View {
            var body: some View {
                Text("Inside").card("Hello")
            }
        }
        """
        let result = Kiln.run(source)
        let window = mount(try XCTUnwrap(result.view))
        settle(window)
        XCTAssertEqual(result.interp?.errors, [])
        XCTAssertTrue((result.interp?.console ?? "").contains("card Hello"), result.interp?.console ?? "")
        result.tearDown()
    }

    func testViewModifierKeepsItsOwnState() throws {
        let source = """
        import SwiftUI
        struct Counted: ViewModifier {
            @State private var appeared = 0
            func body(content: Content) -> some View {
                content
                    .overlay(Text("\\(appeared)"))
                    .onAppear { appeared += 1; print("appeared", appeared) }
            }
        }
        struct ContentView: View {
            var body: some View { Text("x").modifier(Counted()) }
        }
        """
        let result = Kiln.run(source)
        let window = mount(try XCTUnwrap(result.view))
        settle(window)
        XCTAssertEqual(result.interp?.errors, [])
        XCTAssertTrue((result.interp?.console ?? "").contains("appeared 1"), result.interp?.console ?? "")
        result.tearDown()
    }

    // MARK: Layout

    func testLayoutSizesAndPlacesSubviews() throws {
        let source = """
        import SwiftUI
        struct Diagonal: Layout {
            var step: CGFloat = 10
            func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
                let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
                print("fits", subviews.count, proposal.width ?? -1)
                return CGSize(width: sizes.reduce(0) { $0 + $1.width }, height: sizes.reduce(0) { $0 + $1.height })
            }
            func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
                var p = CGPoint(x: bounds.minX, y: bounds.minY)
                for subview in subviews {
                    let size = subview.sizeThatFits(.unspecified)
                    subview.place(at: p, proposal: ProposedViewSize(size))
                    print("place", Int(p.x - bounds.minX), Int(p.y - bounds.minY))
                    p.x += size.width + step
                    p.y += size.height
                }
            }
        }
        struct ContentView: View {
            var body: some View {
                Diagonal(step: 5) {
                    Color.red.frame(width: 20, height: 10)
                    Color.blue.frame(width: 30, height: 10)
                }
            }
        }
        """
        let result = Kiln.run(source)
        let window = mount(try XCTUnwrap(result.view))
        settle(window)
        XCTAssertEqual(result.interp?.errors, [])
        XCTAssertTrue((result.interp?.console ?? "").contains("fits 2"), result.interp?.console ?? "")
        XCTAssertTrue((result.interp?.console ?? "").contains("place 0 0\nplace 25 10"), result.interp?.console ?? "")
        result.tearDown()
    }

    func testLayoutCacheAndAnyLayout() throws {
        let source = """
        import SwiftUI
        struct Stacked: Layout {
            struct Cache { var heights: [CGFloat] }
            func makeCache(subviews: Subviews) -> Cache {
                print("make", subviews.count)
                return Cache(heights: subviews.map { $0.sizeThatFits(.unspecified).height })
            }
            func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
                CGSize(width: proposal.replacingUnspecifiedDimensions().width, height: cache.heights.reduce(0, +))
            }
            func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
                var y = bounds.minY
                for (i, s) in subviews.enumerated() {
                    s.place(at: CGPoint(x: bounds.midX, y: y), anchor: .top, proposal: .unspecified)
                    y += cache.heights[i]
                }
                print("placed", Int(y - bounds.minY))
            }
        }
        struct ContentView: View {
            @State private var fancy = true
            var body: some View {
                let layout = fancy ? AnyLayout(Stacked()) : AnyLayout(HStackLayout(spacing: 2))
                layout {
                    Color.red.frame(width: 20, height: 7)
                    Color.blue.frame(width: 20, height: 9)
                }
            }
        }
        """
        let result = Kiln.run(source)
        let window = mount(try XCTUnwrap(result.view))
        settle(window)
        XCTAssertEqual(result.interp?.errors, [])
        XCTAssertTrue((result.interp?.console ?? "").contains("make 2"), result.interp?.console ?? "")
        XCTAssertTrue((result.interp?.console ?? "").contains("placed 16"), result.interp?.console ?? "")
        result.tearDown()
    }

    func testProposedViewSize() throws {
        let i = try interp("""
        let p = ProposedViewSize(width: 10, height: nil)
        print(p.width ?? -1, p.height ?? -1, p == .unspecified, ProposedViewSize.unspecified == .unspecified)
        let s = p.replacingUnspecifiedDimensions(by: CGSize(width: 1, height: 2))
        print(s.width, s.height)
        """)
        XCTAssertEqual(i.errors, [])
        XCTAssertEqual(i.console, "10.0 -1 false true\n10.0 2.0\n")
    }

    // MARK: Transition

    func testTransitionProxyRunsBodyWithPhase() throws {
        let (i, v) = try make("""
        import SwiftUI
        struct Blur: Transition {
            var radius = 8.0
            func body(content: Content, phase: TransitionPhase) -> some View {
                print("phase", phase.isIdentity, phase.value, phase == .willAppear)
                return content.blur(radius: phase.isIdentity ? 0 : radius)
            }
        }
        extension Transition where Self == Blur {
            static var blurry: Blur { Blur(radius: 3) }
        }
        """, "Blur()")
        let proxy = try XCTUnwrap(i.proxy(for: v, as: "Transition") as? KTransitionProxy)
        let window = mount(KTransitionBody(app: proxy.app, content: AnyView(Text("x")), phase: .willAppear))
        settle(window)
        XCTAssertTrue(i.console.contains("phase false -1.0 true"), i.console)
        XCTAssertEqual(i.errors, [])
        // `.transition(.blurry)` finds the app's static member.
        XCTAssertNotNil(DrawingBridges.appTransition(.native(.implicit("blurry", [])), i))
    }

    func testTransitionsInAnApp() throws {
        let source = """
        import SwiftUI
        struct Dim: ViewModifier {
            var amount: Double
            func body(content: Content) -> some View { content.opacity(1 - amount) }
        }
        extension AnyTransition {
            static var dim: AnyTransition { .modifier(active: Dim(amount: 1), identity: Dim(amount: 0)) }
        }
        struct Slide: Transition {
            func body(content: Content, phase: TransitionPhase) -> some View {
                content.offset(x: phase.isIdentity ? 0 : 40)
            }
        }
        struct ContentView: View {
            @State private var shown = true
            var body: some View {
                VStack {
                    if shown {
                        Text("A").transition(.dim)
                        Text("B").transition(Slide())
                        Text("C").transition(.opacity.combined(with: .scale))
                        Text("D").transition(.asymmetric(insertion: .move(edge: .leading), removal: .dim))
                    }
                }
                .onAppear { withAnimation { shown.toggle() } }
            }
        }
        """
        let result = Kiln.run(source)
        let window = mount(try XCTUnwrap(result.view))
        settle(window, frames: 20)
        XCTAssertEqual(result.interp?.errors, [])
        result.tearDown()
    }

    // MARK: Animatable views and modifiers

    func testAnimatableViewInterpolates() throws {
        let source = """
        import SwiftUI
        struct Counter: View, Animatable {
            var value: Double
            var animatableData: Double {
                get { value }
                set { value = newValue }
            }
            var body: some View {
                Text("\\(Int(value))").onAppear { print("shown", Int(value)) }
            }
        }
        struct ContentView: View {
            var body: some View { Counter(value: 42) }
        }
        """
        let result = Kiln.run(source)
        let window = mount(try XCTUnwrap(result.view))
        settle(window)
        XCTAssertEqual(result.interp?.errors, [])
        XCTAssertTrue((result.interp?.console ?? "").contains("shown 42"), result.interp?.console ?? "")
        let interp = try XCTUnwrap(result.interp)
        let counter = try XCTUnwrap(interp.type(named: "Counter"))
        var view = KAnimatableView(app: KAppValue(type: counter, value: .structV(KStructValue(type: counter, fields: ["value": .double(1)])), interp))
        XCTAssertEqual(view.animatableData, KAnimVector([1]))
        view.animatableData = KAnimVector([7])
        XCTAssertEqual(view.app.structValue?.fields["value"], .double(7))
        result.tearDown()
    }

    func testAnimatableModifierInterpolates() throws {
        let (i, v) = try make("""
        import SwiftUI
        struct Shake: ViewModifier, Animatable {
            var phase: Double
            var animatableData: Double {
                get { phase }
                set { phase = newValue }
            }
            func body(content: Content) -> some View { content.offset(x: sin(phase * .pi * 2) * 6) }
        }
        """, "Shake(phase: 0)")
        var proxy = try XCTUnwrap(i.proxy(for: v, as: "ViewModifier") as? KModifierProxy)
        proxy.animatableData = KAnimVector([0.25])
        XCTAssertEqual(proxy.animatableData, KAnimVector([0.25]))
        XCTAssertEqual(i.errors, [])
    }

    // MARK: Delegates

    func testDelegateSelectorsFollowSwiftNames() {
        XCTAssertEqual(KDelegates.selector(for: KRequirement(parsing: "imagePickerController(_:didFinishPickingMediaWithInfo:)?"), spec: nil),
                       "imagePickerController:didFinishPickingMediaWithInfo:")
        XCTAssertEqual(KDelegates.selector(for: KRequirement(parsing: "imagePickerControllerDidCancel(_:)"), spec: nil), "imagePickerControllerDidCancel:")
        XCTAssertEqual(KDelegates.selector(for: KRequirement(parsing: "navigationController(_:willShow:animated:)"), spec: nil),
                       "navigationController:willShow:animated:")
        XCTAssertEqual(KDelegates.selector(for: KRequirement(parsing: "load(from:)"), spec: nil), "loadWithFrom:")
    }

    #if canImport(CoreLocation)
    func testDelegateProxyForwardsToTheAppsClass() throws {
        let (i, v) = try make("""
        import CoreLocation
        class Tracker: NSObject, CLLocationManagerDelegate {
            var seen = 0
            func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
                seen += locations.count
                print("locations", locations.count)
            }
            func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
                print("failed", error.localizedDescription)
            }
        }
        """, "Tracker()")
        XCTAssertEqual(i.errors, [])
        let proxy = try XCTUnwrap(KDelegates.proxy(for: v, i))
        // The same object every time, so a delegate set twice is one delegate.
        XCTAssertTrue(proxy === KDelegates.proxy(for: v, i))
        XCTAssertTrue(proxy.conforms(to: CLLocationManagerDelegate.self))
        let sel = NSSelectorFromString("locationManager:didUpdateLocations:")
        XCTAssertTrue(proxy.responds(to: sel))
        // Not implemented by the app: the framework sees it as absent.
        XCTAssertFalse(proxy.responds(to: NSSelectorFromString("locationManagerDidChangeAuthorization:")))
        let delegate = unsafeBitCast(proxy, to: CLLocationManagerDelegate.self)
        let manager = CLLocationManager()
        delegate.locationManager?(manager, didUpdateLocations: [CLLocation(latitude: 1, longitude: 2), CLLocation(latitude: 3, longitude: 4)])
        delegate.locationManager?(manager, didFailWithError: NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "No signal"]))
        XCTAssertEqual(i.console, "locations 2\nfailed No signal\n")
        if case .object(let o) = v { XCTAssertEqual(o.fields["seen"], .int(2)) }
        // After teardown the proxy answers nothing and calls nothing.
        i.context.tearDown()
        delegate.locationManager?(manager, didUpdateLocations: [CLLocation(latitude: 1, longitude: 2)])
        XCTAssertEqual(i.console, "locations 2\nfailed No signal\n")
        XCTAssertFalse(proxy.responds(to: sel))
    }
    #endif

    func testSwiftOnlyDelegateBaseForwards() throws {
        let (i, v) = try make("""
        class Listener {
            func scanner(_ name: String, didFind count: Int) { print("found", name, count) }
        }
        """, "Listener()")
        let d = KAppDelegateObject(try XCTUnwrap(KAppValue(v, i)))
        d.forward("scanner(_:didFind:)", [.string("text"), .int(3)])
        XCTAssertNil(d.forward("scanner(_:didLose:)", [.string("text"), .int(3)]))
        XCTAssertEqual(i.console, "found text 3\n")
    }

    // MARK: Transferable and FileDocument

    func testTransferableExportsAndImports() async throws {
        let (i, v) = try make("""
        import SwiftUI
        import UniformTypeIdentifiers
        struct Note: Codable, Transferable {
            var title: String
            var body: String
            static var transferRepresentation: some TransferRepresentation {
                CodableRepresentation(contentType: .json)
                DataRepresentation(exportedContentType: .commaSeparatedText) { note in
                    Data("\\(note.title),\\(note.body)".utf8)
                }
                ProxyRepresentation(exporting: \\.title)
            }
        }
        """, #"Note(title: "Hi", body: "There")"#)
        XCTAssertEqual(i.errors, [])
        let item = try XCTUnwrap(i.proxy(for: v, as: "Transferable") as? KTransferItem)
        XCTAssertEqual(item.string, "Hi")
        XCTAssertNil(item.url)
        XCTAssertTrue(item.exports(.json))
        XCTAssertTrue(item.exports(.commaSeparatedText))
        let json = try await item.data(.json)
        XCTAssertEqual(String(decoding: json, as: UTF8.self), #"{"body":"There","title":"Hi"}"#)
        let csv = try await item.data(.commaSeparatedText)
        XCTAssertEqual(String(decoding: csv, as: UTF8.self), "Hi,There")
        let note = try XCTUnwrap(i.type(named: "Note"))
        let back = try await KTransferables.importValue(note, data: json, contentType: .json, i)
        XCTAssertEqual(back, v)
    }

    func testShareLinkTakesTheAppsTransferable() throws {
        let source = """
        import SwiftUI
        struct Link: Transferable {
            var url: URL
            static var transferRepresentation: some TransferRepresentation { ProxyRepresentation(exporting: \\.url) }
        }
        struct ContentView: View {
            var body: some View {
                VStack {
                    ShareLink(item: Link(url: URL(string: "https://example.com")!), preview: SharePreview("Example"))
                    ShareLink("Text", item: "hello")
                }
            }
        }
        """
        let result = Kiln.run(source)
        let window = mount(try XCTUnwrap(result.view))
        settle(window)
        XCTAssertEqual(result.interp?.errors, [])
        let interp = try XCTUnwrap(result.interp)
        let link = try XCTUnwrap(interp.type(named: "Link"))
        let item = try XCTUnwrap(interp.proxy(for: .structV(KStructValue(type: link, fields: ["url": .native(.url(URL(string: "https://example.com")!))])),
                                              as: "Transferable") as? KTransferItem)
        XCTAssertEqual(item.url?.absoluteString, "https://example.com")
        result.tearDown()
    }

    func testFileDocumentWritesAndReads() throws {
        let (i, v) = try make("""
        import SwiftUI
        import UniformTypeIdentifiers
        struct TextFile: FileDocument {
            static var readableContentTypes: [UTType] { [.plainText] }
            var text = ""
            init(text: String) { self.text = text }
            init(configuration: ReadConfiguration) throws {
                if let data = configuration.file.regularFileContents {
                    text = String(decoding: data, as: UTF8.self)
                }
            }
            func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
                FileWrapper(regularFileWithContents: Data(text.utf8))
            }
        }
        """, #"TextFile(text: "Hello, file")"#)
        XCTAssertEqual(i.errors, [])
        let doc = try XCTUnwrap(KFileDocuments.document(for: v, i))
        let config = try XCTUnwrap(doc.app)
        _ = config
        let data = try KFileDocuments.data(of: v, contentType: .plainText, i)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "Hello, file")
        let type = try XCTUnwrap(i.type(named: "TextFile"))
        XCTAssertEqual(KFileDocuments.readableContentTypes(type, i), [.plainText])
        let back = try KFileDocuments.read(type, data: Data("Read back".utf8), contentType: .plainText, i)
        if case .structV(let s) = back { XCTAssertEqual(s.fields["text"], .string("Read back")) } else { XCTFail("\(back)") }
    }

    func testFileDocumentWithoutInitIsAnError() throws {
        let i = try interp("""
        import SwiftUI
        struct Broken: FileDocument {
            static var readableContentTypes: [UTType] { [.plainText] }
            func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data()) }
        }
        """)
        XCTAssertTrue(i.errors.contains("Line 2: 'Broken' doesn't conform to 'FileDocument': it has no init(configuration:)"), "\(i.errors)")
    }

    // MARK: Async requirements

    func testHostAwaitsAnAsyncRequirement() throws {
        Kiln.registerProtocol("KilnTestGreeter", requirements: ["async greet(name:)", "title?"])
        Kiln.registerFunction("kilnTestGreet", signature: "_:any") { call in
            guard let g = call.adopter(0, as: "KilnTestGreeter") else { throw call.error("needs a KilnTestGreeter") }
            return .async { try await g.callAsync("greet(name:)", [KilnValue(string: "Ann")]) }
        }
        let i = try interp("""
        struct Polite: KilnTestGreeter {
            func greet(name: String) async throws -> String {
                try await Task.sleep(for: .milliseconds(20))
                return "Hello, " + name
            }
        }
        struct Rude: KilnTestGreeter {
            struct Nope: Error {}
            func greet(name: String) async throws -> String { throw Nope() }
        }
        Task {
            let a = try await kilnTestGreet(Polite())
            print(a)
            do { _ = try await kilnTestGreet(Rude()) } catch { print("caught", error is Rude.Nope) }
        }
        """, headless: false)
        let deadline = Date().addingTimeInterval(3)
        while !i.console.contains("caught"), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertEqual(i.errors, [])
        XCTAssertEqual(i.console, "Hello, Ann\ncaught true\n")
        i.tearDown()
    }

    func testHostProtocolRequirementsAreChecked() throws {
        Kiln.registerProtocol("KilnTestTool", requirements: ["async call(arguments:)", "name"])
        let i = try interp("""
        struct Weather: KilnTestTool {
            let name = "weather"
        }
        """)
        XCTAssertTrue(i.errors.contains("Line 1: 'Weather' doesn't conform to 'KilnTestTool': it has no call(arguments:)"), "\(i.errors)")
    }

    // MARK: The Lab's examples

    /// §1.5's Lab examples, shown: `validate` never mounts a view, so a
    /// proxy's errors (in `path(in:)`, `placeSubviews`) only show up here.
    func testProxyExamplesRenderWithoutErrors() throws {
        let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Examples/Apps").standardized
        for name in ["WaveStudio", "TagCloud", "CardStyles"] {
            let source = try String(contentsOf: examples.appendingPathComponent(name + ".swift"), encoding: .utf8)
            let result = Kiln.run(source)
            let window = mount(try XCTUnwrap(result.view, name), width: 390, height: 700)
            settle(window)
            XCTAssertEqual(result.interp?.errors, [], name)
            XCTAssertEqual(result.interp?.warnings, [], name)
            result.tearDown()
        }
    }
}
