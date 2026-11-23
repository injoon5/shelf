import XCTest
import SwiftUI
@testable import Kiln

/// Round 1, Layout: subviews and sections, container values, scrolling,
/// geometry, alignment guides, frames relative to the container.
@MainActor
final class LayoutBridgeTests: XCTestCase {
    private func assertClean(_ body: String, state: String = "", extra: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(BridgeTest.problems(BridgeTest.app(body, state: state, extra: extra)), [], file: file, line: line)
    }

    func testGroupAndForEachSubviewsWithContainerValues() {
        let extra = """
        extension ContainerValues { @Entry var icon: String = "star" }
        struct Stack<Content: View>: View {
            @ViewBuilder var content: Content
            var body: some View {
                Group(subviews: content) { subviews in
                    VStack {
                        ForEach(subviews) { s in Label("Row", systemImage: s.containerValues.icon) }
                        Text("\\(subviews.count) rows")
                        if let first = subviews.first { first.bold() }
                        ForEach(subviews.dropFirst()) { s in s.opacity(0.5) }
                    }
                }
            }
        }
        struct Pages<Content: View>: View {
            @ViewBuilder var content: Content
            var body: some View {
                ScrollView(.horizontal) { HStack { ForEach(subviews: content) { s in s.frame(width: 100) } } }
            }
        }
        """
        assertClean("""
        VStack {
            Stack { Text("A").containerValue(\\.icon, "heart"); Text("B"); ForEach(0..<2) { Text("\\($0)") } }
            Pages { Text("1"); Text("2") }
            Group(sections: VStack { Section("One") { Text("a"); Text("b") } }) { sections in
                ForEach(sections, id: \\.id) { s in s.header; Text("\\(s.content.count)") }
            }
            ForEach(sections: VStack { Section("Two") { Text("c") } }) { s in s.header }
        }
        """, extra: extra)
    }

    func testScrollPositionPagingTransitionsAndEvents() throws {
        let body = """
        VStack {
            ScrollView(.horizontal) {
                LazyHStack { ForEach(0..<10) { i in Text("\\(i)").id(i).scrollTransition(.animated, axis: .horizontal) { content, phase in
                    content.opacity(phase.isIdentity ? 1 : 0.3).offset(y: phase.value * 10).rotationEffect(.degrees(phase.value * 5))
                } } }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition($position)
            .scrollPosition(id: $current)
            .onScrollGeometryChange(for: Double.self) { $0.contentOffset.x } action: { _, new in x = new }
            .onScrollPhaseChange { _, new in moving = new.isScrolling }
            .onScrollVisibilityChange(threshold: 0.2) { moving = $0 }
            .onScrollTargetVisibilityChange(idType: Int.self) { ids in print(ids) }
            .scrollBounceBehavior(.basedOnSize).scrollClipDisabled().scrollDisabled(false).scrollIndicatorsFlash(onAppear: true)
            .defaultScrollAnchor(.center).scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            Button("Top") { position.scrollTo(edge: .leading) }
            Button("Third") { position.scrollTo(id: 3); current = 3 }
            Text(position.isPositionedByUser ? "user" : "app")
        }
        """
        let state = "@State private var position = ScrollPosition(edge: .leading)\n@State private var current: Int? = nil\n@State private var x = 0.0\n@State private var moving = false"
        assertClean(body, state: state)
        let picked = try BridgeTest.bound(BridgeTest.app(body, state: state))
        XCTAssertTrue(picked.contains(".scrollPosition(_:anchor:)") && picked.contains(".scrollPosition(id:anchor:)"), "\(picked)")
        XCTAssertTrue(picked.contains(".scrollTransition(_:axis:transition:)"), "\(picked)")
    }

    func testGeometryAlignmentAndFrames() {
        assertClean("""
        VStack(alignment: .leading) {
            GeometryReader { proxy in
                Text("\\(Int(proxy.size.width)) \\(Int(proxy.frame(in: .global).minY)) \\(Int(proxy.safeAreaInsets.top))")
            }
            .coordinateSpace(.named("box"))
            Text("Guide").alignmentGuide(.leading) { d in d[.trailing] - d.width / 2 }
            Rectangle().containerRelativeFrame(.horizontal) { length, axis in length * 0.8 }
            Rectangle().containerRelativeFrame([.horizontal, .vertical], count: 3, span: 2, spacing: 8)
            Circle().size(width: 20, height: 20)
            Text("Pad").safeAreaPadding(.horizontal, 12).contentMargins(10, for: .scrollIndicators)
            Grid { GridRow { Text("a").gridCellColumns(2).gridCellAnchor(.top); Text("b").gridCellUnsizedAxes(.horizontal) } }
            Text("Metric").frame(width: metric)
            ViewThatFits(in: .vertical) { Text("long"); Text("s") }
            EquatableView(content: Text("same"))
            RoundedRectangle(cornerRadius: 12).fill(.blue).containerShape(RoundedRectangle(cornerRadius: 20))
        }
        .layoutDirectionBehavior(.mirrors)
        .geometryGroup()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in print(w) }
        .safeAreaInset(edge: .leading, spacing: 4) { Color.red.frame(width: 4) }
        """, state: "@ScaledMetric private var metric: CGFloat = 40")
    }

    func testArrangementViewOnIOS27Point1() {
        assertClean("""
        ArrangementView { Text("Main") } secondary: { Text("Side").splitArrangementLayoutRatio(0.3).overlayArrangementEdge(.trailing) }
            .arrangementViewStyle(.split)
        """)
    }

    func testAWrongCallSaysWhichFormsThereAre() {
        let v = Kiln.validate(BridgeTest.app(#"Text("x").containerRelativeFrame(.horizontal, cnt: 2)"#))
        XCTAssertEqual(v.errors.count, 1)
        XCTAssertTrue(v.errors.first?.contains("Kiln has no .containerRelativeFrame(_:cnt:)") == true, "\(v.errors)")
    }
}
