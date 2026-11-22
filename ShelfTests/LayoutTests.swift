import Testing
@testable import Shelf

struct LayoutTests {
    private let page = 4
    private let dock = 2

    @Test func newAppsFillTheLastPageThenStartAnother() {
        var layout = Layout()
        layout.reconcile(with: ["a", "b", "c", "d", "e"], pageSize: page)
        #expect(layout.pages == [["a", "b", "c", "d"], ["e"]])
        layout.reconcile(with: ["a", "b", "c", "d", "e", "f"], pageSize: page)
        #expect(layout.pages == [["a", "b", "c", "d"], ["e", "f"]])
    }

    @Test func removedAndUnknownSlugsLeave() {
        var layout = Layout(dock: ["gone", "a"], pages: [["b", "ghost"], ["c"]])
        layout.reconcile(with: ["a", "b", "c"], pageSize: page)
        #expect(layout.dock == ["a"])
        #expect(layout.pages == [["b"], ["c"]])
    }

    @Test func aSlugNeverAppearsTwice() {
        var layout = Layout(dock: ["a"], pages: [["a", "b", "b"]])
        layout.reconcile(with: ["a", "b"], pageSize: page)
        #expect(layout.dock == ["a"])
        #expect(layout.pages == [["b"]])
    }

    @Test func anEmptyLibraryKeepsOnePage() {
        var layout = Layout(dock: ["a"], pages: [["b"], ["c"]])
        layout.reconcile(with: [], pageSize: page)
        #expect(layout == Layout(dock: [], pages: [[]]))
    }

    @Test func movingWithinAPageSlidesTheOthers() {
        var layout = Layout(pages: [["a", "b", "c", "d"]])
        let moved1 = layout.move("a", to: .page(0, index: 2), pageSize: page, dockSize: dock)
        #expect(moved1)
        #expect(layout.pages == [["b", "c", "a", "d"]])
        #expect(layout.slot(of: "a") == .page(0, index: 2))
    }

    @Test func movingOntoAFullPagePushesItsLastIconOn() {
        var layout = Layout(pages: [["a", "b", "c", "d"], ["e"]])
        layout.move("e", to: .page(0, index: 0), pageSize: page, dockSize: dock)
        #expect(layout.pages == [["e", "a", "b", "c"], ["d"]])
    }

    @Test func aSpillCascadesThroughFullPages() {
        var layout = Layout(pages: [["a", "b", "c", "d"], ["e", "f", "g", "h"], ["i"]])
        layout.move("i", to: .page(0, index: 1), pageSize: page, dockSize: dock)
        #expect(layout.pages == [["a", "i", "b", "c"], ["d", "e", "f", "g"], ["h"]])
    }

    @Test func droppingOnANewPageCreatesIt() {
        var layout = Layout(pages: [["a", "b"]])
        layout.move("b", to: .page(1, index: 0), pageSize: page, dockSize: dock)
        #expect(layout.pages == [["a"], ["b"]])
    }

    @Test func emptiedPagesDisappear() {
        var layout = Layout(pages: [["a"], ["b"]])
        layout.move("b", to: .page(0, index: 1), pageSize: page, dockSize: dock)
        #expect(layout.pages == [["a", "b"]])
    }

    @Test func pinningAndUnpinning() {
        var layout = Layout(pages: [["a", "b", "c"]])
        let moved2 = layout.move("b", to: .dock(index: 0), pageSize: page, dockSize: dock)
        #expect(moved2)
        let moved3 = layout.move("c", to: .dock(index: 0), pageSize: page, dockSize: dock)
        #expect(moved3)
        #expect(layout.dock == ["c", "b"])
        // The dock is full: a third app is refused and stays where it was.
        let moved4 = layout.move("a", to: .dock(index: 1), pageSize: page, dockSize: dock)
        #expect(!moved4)
        #expect(layout.pages == [["a"]])
        // Reordering inside a full dock is still allowed.
        let moved5 = layout.move("b", to: .dock(index: 0), pageSize: page, dockSize: dock)
        #expect(moved5)
        #expect(layout.dock == ["b", "c"])
        let moved6 = layout.move("c", to: .page(0, index: 0), pageSize: page, dockSize: dock)
        #expect(moved6)
        #expect(layout.dock == ["b"])
        #expect(layout.pages == [["c", "a"]])
    }

    @Test func outOfRangeIndexesAreClamped() {
        var layout = Layout(pages: [["a", "b"]])
        layout.move("a", to: .page(0, index: 99), pageSize: page, dockSize: dock)
        #expect(layout.pages == [["b", "a"]])
    }

    @Test func movingToWhereItAlreadyIsChangesNothing() {
        var layout = Layout(pages: [["a", "b"]])
        let moved7 = layout.move("a", to: .page(0, index: 0), pageSize: page, dockSize: dock)
        #expect(!moved7)
        let moved8 = layout.move("zzz", to: .page(0, index: 0), pageSize: page, dockSize: dock)
        #expect(!moved8)
    }

    @Test func geometryRoundTripsSlots() {
        let geometry = HomeGeometry(size: .init(width: 402, height: 874), safeTop: 62, displayRadius: 62, labelHeight: 16)
        for index in 0..<Layout.pageSize {
            #expect(geometry.gridIndex(at: geometry.iconCenter(index), count: Layout.pageSize) == index)
        }
        // A point past the last icon lands after it, not in an empty slot beyond.
        #expect(geometry.gridIndex(at: geometry.iconCenter(23), count: 5) == 5)
        #expect(geometry.iconSize == 64)
        #expect(abs(geometry.rowPitch - 100.33) < 1.5)
        for index in 0..<4 {
            #expect(geometry.dockIndex(at: geometry.dockCenter(index, of: 4).x, of: 4) == index)
        }
    }
}
