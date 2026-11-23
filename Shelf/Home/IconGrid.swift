import SwiftUI

/// The pages of icons. Every icon is a sibling in one wide layer and is put
/// at an exact point, so a reorder is nothing more than points changing, and
/// the spring carries each icon to its new place, across pages too.
struct IconGrid: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HomeModel.self) private var model
    var geometry: HomeGeometry
    var labelSize: CGFloat

    private struct Placement: Identifiable {
        var item: HomeItem
        var page: Int
        var index: Int
        var id: String { item.id }
    }

    private var placements: [Placement] {
        library.layout.pages.enumerated().flatMap { page, ids in
            ids.enumerated().compactMap { index, id in
                library.item(id).map { Placement(item: $0, page: page, index: index) }
            }
        }
    }

    private var pageCount: Int { model.pageCount(library.layout.pages) }

    var body: some View {
        @Bindable var model = model
        let width = geometry.size.width
        ScrollView(.horizontal) {
            ZStack(alignment: .topLeading) {
                // Empty wallpaper: a tap leaves edit mode, a long press enters it.
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { if model.isEditing { model.stopEditing() } }
                    .onLongPressGesture { model.longPressedWallpaper() }

                ForEach(placements) { placement in
                    let center = geometry.iconCenter(placement.index)
                    HomeIcon(item: placement.item, geometry: geometry, labelSize: labelSize)
                        .frame(width: geometry.labelWidth, height: geometry.cellHeight, alignment: .top)
                        .position(x: CGFloat(placement.page) * width + center.x,
                                  y: center.y + (geometry.cellHeight - geometry.iconSize) / 2)
                }
            }
            .frame(width: CGFloat(pageCount) * width, height: geometry.size.height)
            // Inside the content, so the scroll view is one of its ancestors.
            .background(TouchesBeginAtOnce())
            .onDrop(of: [.text], delegate: GridDropDelegate(geometry: geometry, library: library, model: model, pageCount: pageCount))
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition($model.scroll)
        .scrollDisabled(model.isSearching)
        .onChange(of: width, initial: true) { model.pageWidth = width }
        .onScrollGeometryChange(for: Int.self) { scroll in
            Int((scroll.contentOffset.x / max(width, 1)).rounded())
        } action: { _, page in
            model.page = page
        }
        .onScrollPhaseChange { _, phase in
            if pageCount > 1 { model.pagesMoved(phase != .idle) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.snaps)
    }
}

/// A scroll view waits a moment before passing a touch to its content, in case
/// it turns into a scroll. That wait would delay an icon's pressed state, and
/// Springboard darkens an icon the instant it is touched.
private struct TouchesBeginAtOnce: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async {
            var ancestor = view.superview
            while let current = ancestor {
                if let scroll = current as? UIScrollView {
                    scroll.delaysContentTouches = false
                    return
                }
                ancestor = current.superview
            }
        }
    }
}
