import XCTest
import SwiftUI
@testable import Kiln

/// Round 1, Lists: selection, outlines, edit actions, iOS 27 reordering and
/// swipe actions outside `List`, and the row and section modifiers.
@MainActor
final class ListsBridgeTests: XCTestCase {
    private func assertClean(_ body: String, state: String = "", extra: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(BridgeTest.problems(BridgeTest.app(body, state: state, extra: extra)), [], file: file, line: line)
    }

    private let fruit = """
    struct Fruit: Identifiable, Hashable { let id: Int; var name: String }
    struct Node: Identifiable { let id: Int; var name: String; var children: [Node]? }
    """

    func testSingleAndMultipleSelection() throws {
        let state = """
        @State private var items = [Fruit(id: 1, name: "Apple"), Fruit(id: 2, name: "Pear")]
        @State private var picked: Int? = nil
        @State private var many = Set<Int>()
        """
        let body = """
        VStack {
            List(items, selection: $picked) { Text($0.name) }
            List(selection: $many) {
                ForEach(items) { item in Text(item.name) }
                Text("Static").tag(99)
            }
            .toolbar { EditButton() }
            Text("\\(picked ?? 0) \\(many.count)")
        }
        """
        assertClean(body, state: state, extra: fruit)
        let picks = try BridgeTest.bound(BridgeTest.app(body, state: state, extra: fruit))
        XCTAssertTrue(picks.contains("List(_:id:selection:rowContent:)") && picks.contains("List(selection:content:)"), "\(picks)")
    }

    func testOutlinesAndEditActions() {
        let state = """
        @State private var items = [Fruit(id: 1, name: "Apple"), Fruit(id: 2, name: "Pear")]
        let tree = [Node(id: 1, name: "Fruit", children: [Node(id: 2, name: "Apple", children: nil)]), Node(id: 3, name: "Nuts", children: nil)]
        """
        assertClean("""
        VStack {
            List(tree, children: \\.children) { node in Text(node.name) }
            List { OutlineGroup(tree, children: \\.children) { node in Label(node.name, systemImage: "leaf") } }
            List { ForEach($items, editActions: .all) { $item in TextField("Name", text: $item.name) } }
            List($items, editActions: .delete) { $item in Text(item.name).deleteDisabled(item.id == 1).moveDisabled(true) }
        }
        """, state: state, extra: fruit)
    }

    func testRowAndSectionModifiers() {
        assertClean("""
        List {
            Section("A") {
                Text("Row").listRowSeparatorTint(.red).listRowSeparator(.hidden, edges: .bottom).listItemTint(.green)
                Text("Row 2").listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20)).badge(3).badgeProminence(.increased)
                Text("Pick").selectionDisabled()
            }
            .sectionIndexLabel("A")
            .listSectionSeparatorTint(.blue)
            .listSectionSeparator(.visible)
            .headerProminence(.increased)
            Section("B", isExpanded: $open) { Text("x") }
        }
        .listSectionSpacing(.compact)
        .listRowSpacing(4)
        .listSectionIndexVisibility(.visible)
        .listSectionMargins(.horizontal, 12)
        .scrollContentBackground(.hidden)
        .environment(\\.defaultMinListRowHeight, 60)
        .environment(\\.headerProminence, .increased)
        """, state: "@State private var open = true")
    }

    func testReorderingAndSwipeActionsOutsideAList() {
        let state = "@State private var items = [Fruit(id: 1, name: \"Apple\"), Fruit(id: 2, name: \"Pear\")]"
        assertClean("""
        ScrollView {
            LazyVStack {
                ForEach(items) { item in
                    Text(item.name)
                        .swipeActions { Button("Delete", role: .destructive) { items.removeAll { $0.id == item.id } } }
                }
                .reorderable()
            }
        }
        .swipeActionsContainer()
        .reorderContainer(for: Fruit.self) { difference in
            let moving = items.filter { difference.sources.contains($0.id) }
            items.removeAll { difference.sources.contains($0.id) }
            switch difference.destination.position {
            case .before(let id):
                let at = items.firstIndex { $0.id == id } ?? items.count
                items.insert(contentsOf: moving, at: at)
            case .end:
                items.append(contentsOf: moving)
            }
        }
        """, state: state, extra: fruit)
    }

    func testFindAndEnvironmentValues() {
        let extra = """
        struct Probe: View {
            @Environment(\\.defaultMinListRowHeight) private var rowHeight
            @Environment(\\.isScrollEnabled) private var scrolls
            var body: some View { Text("\\(Int(rowHeight)) \\(scrolls ? "scrolls" : "fixed")") }
        }
        """
        assertClean("""
        VStack {
            TextEditor(text: $text).findNavigator(isPresented: $finding).findDisabled(false).replaceDisabled()
            Probe().scrollDisabled(true)
        }
        """, state: "@State private var text = \"\"\n@State private var finding = false", extra: extra)
    }

    func testAWrongCallSaysWhichFormsThereAre() {
        let v = Kiln.validate(BridgeTest.app(#"List(selected: $x) { Text("a") }"#, state: "@State private var x: Int? = nil"))
        XCTAssertTrue(v.errors.first?.contains("Kiln has no List(selected:_:); it has List(selection:content:)") == true, "\(v.errors)")
    }
}
