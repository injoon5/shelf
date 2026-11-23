import Foundation
import Testing
import UIKit
@testable import Shelf

/// The app's launch screen (plan §0.8): its snapshot and when it is fresh,
/// the surface read from the source when there is none, and how the card
/// crosses from its icon to it.
struct LaunchSnapshotTests {
    private let key = LaunchSnapshots.Key(revision: LaunchSnapshots.revision(of: "struct ContentView: View {}"),
                                          dark: false, textSize: UIContentSizeCategory.large.rawValue)

    @Test func theFileNameHoldsEverythingFreshnessNeeds() throws {
        #expect(key.fileName == "\(key.revision)-light-L.jpg")
        let read = try #require(LaunchSnapshots.Key(fileName: key.fileName))
        #expect(read.matches(key))
        #expect(key.matches(read))
        let accessibility = LaunchSnapshots.Key(revision: "abc", dark: true,
                                                textSize: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue)
        #expect(accessibility.fileName == "abc-dark-AccessibilityXXXL.jpg")
        for junk in ["abc-dark-L.png", "abc-dim-L.jpg", "abc-dark.jpg", "-dark-L.jpg", ".DS_Store"] {
            #expect(LaunchSnapshots.Key(fileName: junk) == nil)
        }
    }

    @Test func freshMeansTheSameSourceAppearanceAndTextSize() {
        var otherSource = key
        otherSource.revision = LaunchSnapshots.revision(of: "struct ContentView: View { }")
        var otherAppearance = key
        otherAppearance.dark = true
        var otherSize = key
        otherSize.textSize = UIContentSizeCategory.extraLarge.rawValue
        #expect(key.matches(key))
        #expect(!key.matches(otherSource))
        #expect(!key.matches(otherAppearance))
        #expect(!key.matches(otherSize))
    }

    @Test func theRevisionIsTheSourcesAlone() {
        let a = LaunchSnapshots.revision(of: "let x = 1")
        #expect(a == LaunchSnapshots.revision(of: "let x = 1"))
        #expect(a != LaunchSnapshots.revision(of: "let x = 2"))
        #expect(a.count == 16)
        #expect(!a.contains("-"))
    }

    @Test func theKeyComesFromTheTraits() {
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = .dark
            traits.preferredContentSizeCategory = .unspecified
        }
        let key = LaunchSnapshots.Key(source: "x", traits: traits)
        #expect(key.dark)
        // No text size yet is the default one.
        #expect(key.matches(LaunchSnapshots.Key(revision: key.revision, dark: true, textSize: UIContentSizeCategory.large.rawValue)))
    }

    @Test func onlyAFreshSnapshotIsFound() throws {
        let snapshots = LaunchSnapshots(root: temporaryFolder())
        defer { snapshots.removeAll() }
        #expect(snapshots.fresh("habits", key) == nil)
        try snapshots.write(Data([1, 2, 3]), for: "habits", key)
        let found = try #require(snapshots.fresh("habits", key))
        #expect(found.deletingLastPathComponent().lastPathComponent == "habits")
        #expect(found.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false)
                    .trimmingCharacters(in: ["/"]) == snapshots.root.standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: ["/"]))
        #expect(try Data(contentsOf: found) == Data([1, 2, 3]))

        var dark = key
        dark.dark = true
        var bigger = key
        bigger.textSize = UIContentSizeCategory.extraExtraLarge.rawValue
        #expect(snapshots.fresh("habits", dark) == nil)
        #expect(snapshots.fresh("habits", bigger) == nil)
        #expect(snapshots.fresh("todos", key) == nil)
    }

    @Test func aNewSourceDeletesTheOldOnesPictures() throws {
        let snapshots = LaunchSnapshots(root: temporaryFolder())
        defer { snapshots.removeAll() }
        var dark = key
        dark.dark = true
        try snapshots.write(Data([1]), for: "habits", key)
        try snapshots.write(Data([2]), for: "habits", dark)
        // Both appearances of one source sit side by side.
        #expect(snapshots.fresh("habits", key) != nil)
        #expect(snapshots.fresh("habits", dark) != nil)

        var next = key
        next.revision = LaunchSnapshots.revision(of: "something else")
        try snapshots.write(Data([3]), for: "habits", next)
        let folder = try #require(snapshots.folder(for: "habits"))
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(names == [next.fileName])
        #expect(snapshots.fresh("habits", key) == nil)
    }

    @Test func theCachePathIsCachesSnapshotsSlug() throws {
        let folder = try #require(LaunchSnapshots.standard.folder(for: "habits"))
        #expect(folder.lastPathComponent == "habits")
        #expect(folder.deletingLastPathComponent().lastPathComponent == "Snapshots")
        #expect(folder.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
                == URL.cachesDirectory.standardizedFileURL)
        // A slug that could leave the folder has none, and nothing is written.
        let snapshots = LaunchSnapshots(root: temporaryFolder())
        #expect(snapshots.folder(for: "../habits") == nil)
        try snapshots.write(Data([1]), for: "../habits", key)
        #expect(!FileManager.default.fileExists(atPath: snapshots.root.path(percentEncoded: false)))
    }

    @Test func deletingAnAppOrSigningOutClearsIt() throws {
        let snapshots = LaunchSnapshots(root: temporaryFolder())
        defer { snapshots.removeAll() }
        try snapshots.write(Data([1]), for: "habits", key)
        try snapshots.write(Data([1]), for: "todos", key)
        snapshots.remove("habits")
        #expect(snapshots.fresh("habits", key) == nil)
        #expect(snapshots.fresh("todos", key) != nil)
        snapshots.removeAll()
        #expect(snapshots.fresh("todos", key) == nil)
    }

    /// A picture kept in memory is shown only while its file is there:
    /// after Sign Out clears the files, an app opens on its launch surface.
    @MainActor
    @Test func theMemoryCopyGoesWithTheFiles() async throws {
        let store = LaunchSnapshotStore(files: LaunchSnapshots(root: temporaryFolder()))
        defer { store.files.removeAll() }
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 8))
        }
        store.save(picture, for: "habits", key)
        #expect(store.cached("habits", key) != nil)
        let files = store.files, key = key
        let written = await eventually { files.fresh("habits", key) != nil }
        #expect(written)
        // The file can be there a moment before the store hears the write
        // finished; until then a picture on its way counts as fresh.
        let settled = await eventually { await MainActor.run { !store.isWriting } }
        #expect(settled)
        var dark = key
        dark.dark = true
        #expect(store.cached("habits", dark) == nil)
        let loaded = await store.load("habits", key, scale: 2)
        #expect(loaded != nil)

        store.files.removeAll()
        #expect(store.cached("habits", key) == nil)
        let gone = await store.load("habits", key, scale: 2)
        #expect(gone == nil)
    }
}

@MainActor
struct LaunchLayoutTests {
    @Test func aListInANavigationStack() {
        #expect(LaunchLayout(source: Demo.source) == LaunchLayout(grouped: true, navigationBar: true))
    }

    @Test func aFormWithoutNavigation() {
        let source = """
        struct ContentView: View {
            @State private var on = false
            var body: some View {
                Form { Toggle("On", isOn: $on) }
            }
        }
        """
        #expect(LaunchLayout(source: source) == LaunchLayout(grouped: true, navigationBar: false))
    }

    @Test func anythingElseIsPlain() {
        let source = """
        struct ContentView: View {
            var body: some View {
                NavigationStack {
                    VStack {
                        Text("Hello")
                        List { Text("Row") }
                    }
                    .navigationTitle("Hi")
                }
            }
        }
        """
        #expect(LaunchLayout(source: source) == LaunchLayout(grouped: false, navigationBar: true))
        #expect(LaunchLayout(source: "struct ContentView: View { var body: some View { Text(\"Hi\") } }") == .plain)
        #expect(LaunchLayout(source: "") == .plain)
        #expect(LaunchLayout(source: "not swift at all {{{") == .plain)
    }

    @Test func aPlainListHasNoGroupedBackground() {
        let source = """
        struct ContentView: View {
            var body: some View {
                NavigationView {
                    List(items) { Text($0) }
                        .listStyle(.plain)
                }
            }
        }
        """
        #expect(LaunchLayout(source: source) == LaunchLayout(grouped: false, navigationBar: true))
    }

    @Test func tabsAndGroupsAreLookedThrough() {
        let source = """
        struct ContentView: View {
            @State private var tab = 0
            var body: some View {
                TabView(selection: $tab) {
                    Tab("Home", systemImage: "house") {
                        NavigationSplitView {
                            Form { Text("x") }
                        } detail: { Text("y") }
                    }
                }
            }
        }
        """
        #expect(LaunchLayout(source: source) == LaunchLayout(grouped: true, navigationBar: true))
    }

    @Test func commentsAndStringsAreNotCode() {
        let source = """
        struct ContentView: View {
            var body: some View {
                // NavigationStack { List {
                /* Form { */
                Text("List { NavigationStack {")
            }
        }
        """
        #expect(LaunchLayout(source: source) == .plain)
    }

    @Test func theRootIsContentViewOrTheViewNoOtherUses() {
        let named = """
        struct Row: View { var body: some View { NavigationStack { Text("") } } }
        struct ContentView: View { var body: some View { List { Row() } } }
        """
        #expect(LaunchLayout(source: named) == LaunchLayout(grouped: true, navigationBar: false))
        let unnamed = """
        struct Row: View { var body: some View { NavigationStack { Text("") } } }
        struct Screen: View { var body: some View { Form { Row() } } }
        """
        #expect(LaunchLayout(source: unnamed) == LaunchLayout(grouped: true, navigationBar: false))
    }

    @Test func aForcedAppearanceIsKept() {
        let source = """
        struct ContentView: View {
            var body: some View { List { Text("") }.preferredColorScheme(.dark) }
        }
        """
        #expect(LaunchLayout(source: source).dark == true)
        #expect(LaunchLayout(source: Demo.source).dark == nil)
    }
}

struct LaunchMotionTests {
    @Test func theIconGivesWayEarlyInTheOpen() {
        // Measured on Springboard: all icon at 0.14, about a fifth left at
        // 0.31, under a tenth at 0.38, none by half way.
        #expect(CardMotion.launchOpacity(progress: 0) == 0)
        #expect(CardMotion.launchOpacity(progress: 0.12) == 0)
        #expect(CardMotion.launchOpacity(progress: 0.14) < 0.15)
        #expect(abs(CardMotion.launchOpacity(progress: 0.31) - 0.75) < 0.1)
        #expect(CardMotion.launchOpacity(progress: 0.38) > 0.85)
        #expect(CardMotion.launchOpacity(progress: 0.5) == 1)
        var last: CGFloat = 0
        for step in 0...100 {
            let value = CardMotion.launchOpacity(progress: CGFloat(step) / 100)
            #expect(value >= last)
            last = value
        }
    }

    @Test func theOpenIsNotTheCloseInReverse() {
        let opening = CardMotion.look(progress: 0.3, opening: true)
        let closing = CardMotion.look(progress: 0.3, opening: false)
        // Growing: the surface is already most of the way in, and the Home
        // Screen hardly blurred yet.
        #expect(opening.content > 0.6)
        #expect(opening.blur < 3)
        // Shrinking: the app has nearly given way to the icon, over a Home
        // Screen still well blurred.
        #expect(closing.content < 0.2)
        #expect(closing.blur > 10)
        // Both are the Home Screen itself at the icon and fully behind at full screen.
        for opening in [true, false] {
            #expect(CardMotion.look(progress: 0, opening: opening).blur == 0)
            #expect(CardMotion.look(progress: 0, opening: opening).dim == 0)
            #expect(CardMotion.look(progress: 1, opening: opening).blur == RunnerMetrics.backdropBlurRadius)
            #expect(CardMotion.look(progress: 1, opening: opening).dim == RunnerMetrics.backdropDim)
        }
    }

    @Test func turningBackNeverJumps() {
        // Caught growing at 0.4 and swiped away.
        let growing = CardMotion.look(progress: 0.4, opening: true)
        let handoff = LookHandoff(from: growing, at: 0.4, opening: false)
        let atTurn = handoff.look(at: 0.4)
        #expect(abs(atTurn.content - growing.content) < 1e-9)
        #expect(abs(atTurn.blur - growing.blur) < 1e-9)
        #expect(abs(atTurn.dim - growing.dim) < 1e-9)
        // Every small step changes it a little.
        var last = atTurn
        for step in 1...40 {
            let look = handoff.look(at: 0.4 - CGFloat(step) * 0.01)
            #expect(abs(look.content - last.content) < 0.1)
            #expect(abs(look.blur - last.blur) < 2)
            last = look
        }
        // And past the handoff it is the close's own.
        #expect(handoff.look(at: 0.1) == CardMotion.look(progress: 0.1, opening: false))
    }

    @Test func aGrowingCardLeansAwayFromItsIcon() {
        // Centred on its icon it doesn't lean, and full screen it doesn't either.
        #expect(CardMotion.openingLean(centerY: 523, height: 64, iconY: 523, progress: 0) == 0)
        #expect(CardMotion.openingLean(centerY: 437, height: 874, iconY: 523, progress: 1) == 0)
        // From an icon below, its bottom goes away (negative); from above, its top.
        let below = CardMotion.openingLean(centerY: 462, height: 402, iconY: 523, progress: 0.5)
        let above = CardMotion.openingLean(centerY: 300, height: 402, iconY: 122, progress: 0.5)
        #expect(below < 0)
        #expect(above > 0)
        // The cold Developer open: about 0.1 radians at half the screen's width.
        #expect(abs(below + 0.1) < 0.03)
        // Less as it grows, and never past the most a card leans.
        #expect(abs(CardMotion.openingLean(centerY: 462, height: 402, iconY: 523, progress: 0.8)) < abs(below))
        #expect(abs(CardMotion.openingLean(centerY: 0, height: 100, iconY: 874, progress: 0)) <= RunnerMetrics.maxLean)
    }

    @Test func itTurnsSidewaysByWhereItsIconIsAcross() {
        // Photos, top right: the icon 0.28 card widths to the right, the
        // right side forward (negative), about 0.086 radians that close.
        let right = CardMotion.sideLean(centerX: 288, width: 197, iconX: 343, amount: 0.46)
        #expect(right < 0)
        #expect(abs(right + 0.086) < 0.02)
        #expect(CardMotion.sideLean(centerX: 288, width: 197, iconX: 233, amount: 0.46) == -right)
        // Level with its icon, or not moving yet, it doesn't turn.
        #expect(CardMotion.sideLean(centerX: 201, width: 300, iconX: 201, amount: 1) == 0)
        #expect(CardMotion.sideLean(centerX: 201, width: 300, iconX: 340, amount: 0) == 0)
        #expect(abs(CardMotion.sideLean(centerX: 0, width: 10, iconX: 400, amount: 1)) <= RunnerMetrics.maxLean)
    }

    @Test func anOpenFromTheIconStartsAsTheIcon() {
        let look = LookHandoff.fromIcon.look(at: 0)
        #expect(look.content == 0)
        #expect(look.blur == 0)
        #expect(look.dim == 0)
    }
}
