import XCTest
import SwiftUI
@testable import Kiln

/// Round 1, Navigation: split views, paths, zoom transitions, tabs, toolbars,
/// search, and every presentation modifier.
@MainActor
final class NavigationBridgeTests: XCTestCase {
    private func assertClean(_ body: String, state: String = "", extra: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(BridgeTest.problems(BridgeTest.app(body, state: state, extra: extra)), [], file: file, line: line)
    }

    private let item = "struct Item: Identifiable, Hashable { let id: Int; var name: String }"

    func testSplitViewPathsAndZoomTransitions() throws {
        let state = """
        @Namespace private var zoom
        @State private var path = NavigationPath()
        @State private var stack: [Item] = []
        @State private var visibility = NavigationSplitViewVisibility.all
        @State private var column = NavigationSplitViewColumn.sidebar
        @State private var shown: Item? = nil
        let items = [Item(id: 1, name: "One"), Item(id: 2, name: "Two")]
        """
        let body = """
        VStack {
            NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $column) {
                List(items) { item in NavigationLink(item.name, value: item) }
            } detail: {
                Text("Detail")
            }
            .navigationSplitViewStyle(.balanced)
            NavigationStack(path: $path) {
                List(items) { item in
                    NavigationLink(value: item) { Text(item.name) }.matchedTransitionSource(id: item.id, in: zoom)
                }
                .navigationDestination(for: Item.self) { item in
                    Text(item.name).navigationTransition(.zoom(sourceID: item.id, in: zoom))
                }
                .navigationDestination(item: $shown) { item in Text(item.name).navigationTransition(.crossFade) }
                .navigationTitle("Items").navigationSubtitle("Two").toolbarTitleDisplayMode(.inlineLarge)
                Button("Push") { path.append(items[0]); if !path.isEmpty { path.removeLast() } }
                Text("\\(path.count)")
            }
            NavigationStack(path: $stack) { Button("Go") { stack.append(items[1]) } }
        }
        """
        assertClean(body, state: state, extra: item)
        let picked = try BridgeTest.bound(BridgeTest.app(body, state: state, extra: item))
        XCTAssertTrue(picked.contains("NavigationSplitView(columnVisibility:preferredCompactColumn:sidebar:detail:)"), "\(picked)")
        XCTAssertTrue(picked.contains("NavigationStack(path:root:)"), "\(picked)")
        XCTAssertTrue(picked.contains(".navigationDestination(item:destination:)"), "\(picked)")
    }

    func testTabsWithRolesSectionsAndModifiers() {
        assertClean("""
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: 0) { Text("Home") }
                .badge(3)
                .accessibilityLabel("Home tab")
                .customizationID("home")
            TabSection("Library") {
                Tab("Songs", systemImage: "music.note", value: 1) { Text("Songs") }
                Tab("Albums", systemImage: "square.stack", value: 2) { Text("Albums") }.hidden(false).disabled(false)
            }
            .sectionActions { Button("Add") { } }
            Tab(value: 9, role: .search) { Text("Search") }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { Text("Now playing") }
        .tabViewSearchActivation(.searchTabSelection)
        .tabViewSidebarHeader { Text("Header") }
        """, state: "@State private var tab = 0")
        assertClean("""
        TabView {
            Text("A").tabItem { Label("A", systemImage: "a.circle") }
            Text("B").tabItem { Label("B", systemImage: "b.circle") }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        """)
    }

    func testToolbarsWithSpacersPrioritiesAndEveryPlacement() {
        assertClean("""
        NavigationStack {
            Text("Body")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Edit") { } }
                    ToolbarSpacer(.flexible)
                    ToolbarItemGroup(placement: .bottomBar) { Button("A") { }; Button("B") { } }
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItem(placement: .topBarTrailing) { Button("Add") { } }
                        .visibilityPriority(.high)
                        .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .secondaryAction) { Button("More") { } }
                    ToolbarItem(placement: .status) { Text("Ready") }
                    ToolbarItem(placement: .principal) { Text("Title") }
                    ToolbarItem(placement: .largeSubtitle) { Text("Sub") }
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarTitleMenu { Button("Rename") { } }
                    ToolbarOverflowMenu { Button("Archive") { } }
                }
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Color.blue, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
                .toolbarRole(.editor)
                .toolbarMinimizationBehavior(.onScrollDown, for: .bottomBar)
                .navigationBarTitle("Old", displayMode: .inline)
                .navigationBarItems(trailing: Button("Done") { })
        }
        """)
    }

    func testSearchScopesSuggestionsAndTokens() {
        let extra = """
        \(item)
        struct Probe: View {
            @Environment(\\.isSearching) private var searching
            @Environment(\\.dismissSearch) private var dismissSearch
            var body: some View { Button(searching ? "Searching" : "Idle") { dismissSearch() } }
        }
        """
        assertClean("""
        NavigationStack {
            Probe()
                .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find")
                .searchSuggestions { Text("Apple").searchCompletion("Apple") }
                .searchScopes($scope) { Text("All").tag("all"); Text("Mine").tag("mine") }
                .searchToolbarBehavior(.minimize)
                .searchPresentationToolbarBehavior(.avoidHidingContent)
            List { Text("x") }.searchable(text: $query, tokens: $tokens) { token in Text(token.name) }
        }
        """, state: """
        @State private var query = ""
        @State private var searching = false
        @State private var scope = "all"
        @State private var tokens: [Item] = []
        """, extra: extra)
    }

    func testPresentationsAndEditMode() {
        let extra = """
        struct Editor: View {
            @Environment(\\.editMode) private var editMode
            @Environment(\\.isPresented) private var isPresented
            var body: some View {
                Button(editMode?.wrappedValue.isEditing == true ? "Done" : "Edit") {
                    editMode?.wrappedValue = editMode?.wrappedValue == .active ? .inactive : .active
                }
            }
        }
        """
        assertClean("""
        VStack {
            Button("Sheet") { sheet = true }
                .sheet(isPresented: $sheet) {
                    Editor()
                        .presentationDetents([.medium, .large, .fraction(0.3), .height(200)], selection: $detent)
                        .presentationDragIndicator(.visible)
                        .presentationBackground(.thinMaterial)
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                        .presentationCornerRadius(24)
                        .presentationContentInteraction(.scrolls)
                        .presentationCompactAdaptation(.popover)
                        .presentationSizing(.form)
                        .interactiveDismissDisabled()
                        .dismissalConfirmationDialog("Discard?", shouldPresent: true) { Button("Discard", role: .destructive) { } }
                }
                .popover(isPresented: $pop, arrowEdge: .top) { Text("Popover") }
                .fullScreenCover(isPresented: $cover) { Text("Cover") }
                .inspector(isPresented: $inspect) { Text("Inspector").inspectorColumnWidth(min: 200, ideal: 300, max: 400) }
                .actionSheet(isPresented: $sheet) {
                    ActionSheet(title: Text("Pick"), message: Text("One"), buttons: [.default(Text("A")) { }, .destructive(Text("B")), .cancel()])
                }
                .confirmationDialog("Sure?", isPresented: $pop) { Button("Yes") { } }.dialogIcon(Image(systemName: "trash"))
            Editor().environment(\\.editMode, $mode)
            RenameButton().renameAction { pop = true }
        }
        .statusBarHidden()
        .menuActionDismissBehavior(.disabled)
        """, state: """
        @State private var sheet = false
        @State private var pop = false
        @State private var cover = false
        @State private var inspect = false
        @State private var detent = PresentationDetent.medium
        @State private var mode = EditMode.inactive
        """, extra: extra)
    }

    func testAWrongCallSaysWhichFormsThereAre() {
        let v = Kiln.validate(BridgeTest.app(#"NavigationStack(route: $r) { Text("a") }"#, state: "@State private var r: [Int] = []"))
        XCTAssertTrue(v.errors.first?.contains("Kiln has no NavigationStack(route:_:); it has NavigationStack(root:) and NavigationStack(path:root:)") == true, "\(v.errors)")
    }
}
