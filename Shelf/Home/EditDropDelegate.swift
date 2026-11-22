import SwiftUI

/// Follows a dragged icon across the pages and slides the others aside.
struct GridDropDelegate: DropDelegate {
    var geometry: HomeGeometry
    var library: LibraryStore
    var model: HomeModel
    var pageCount: Int

    func validateDrop(info: DropInfo) -> Bool { model.dragging != nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let slug = model.dragging else { return DropProposal(operation: .cancel) }
        let width = geometry.size.width
        let page = min(max(Int(info.location.x / width), 0), pageCount - 1)
        let local = CGPoint(x: info.location.x - CGFloat(page) * width, y: info.location.y)

        let pages = library.layout.pages
        let others = page < pages.count ? pages[page].filter { $0 != slug }.count : 0
        let target = Layout.Slot.page(page, index: geometry.gridIndex(at: local, count: others))
        if library.layout.slot(of: slug) != target {
            withAnimation(Motion.reorder) { _ = library.move(slug, to: target) }
        }

        // Holding at a screen edge flips the page.
        let x = info.location.x - CGFloat(model.page) * width
        if x < HomeMetrics.pageFlipEdge, model.page > 0 {
            model.holdAtEdge(toward: model.page - 1, pageWidth: width)
        } else if x > width - HomeMetrics.pageFlipEdge, model.page < pageCount - 1 {
            model.holdAtEdge(toward: model.page + 1, pageWidth: width)
        } else {
            model.cancelFlip()
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        model.cancelFlip()
    }

    func performDrop(info: DropInfo) -> Bool {
        model.endDrag()
        library.commitLayout()
        return true
    }
}

/// Dragging an icon into the dock pins it; dragging it out unpins it.
struct DockDropDelegate: DropDelegate {
    var geometry: HomeGeometry
    var library: LibraryStore
    var model: HomeModel

    func validateDrop(info: DropInfo) -> Bool { model.dragging != nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let slug = model.dragging else { return DropProposal(operation: .cancel) }
        let dock = library.layout.dock
        let isPinned = dock.contains(slug)
        guard isPinned || dock.count < HomeMetrics.dockApps else { return DropProposal(operation: .forbidden) }

        // Settings keeps the last place, so an app can take any place before it.
        let apps = isPinned ? dock.count : dock.count + 1
        let x = info.location.x + geometry.dockFrame.minX
        let target = Layout.Slot.dock(index: min(geometry.dockIndex(at: x, of: apps + 1), apps - 1))
        if library.layout.slot(of: slug) != target {
            withAnimation(Motion.reorder) { _ = library.move(slug, to: target) }
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.endDrag()
        library.commitLayout()
        return true
    }
}
