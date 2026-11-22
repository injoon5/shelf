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
        var app: CachedApp
        var page: Int
        var index: Int
        var id: String { app.slug }
    }

    private var placements: [Placement] {
        library.layout.pages.enumerated().flatMap { page, slugs in
            slugs.enumerated().compactMap { index, slug in
                library.app(slug).map { Placement(app: $0, page: page, index: index) }
            }
        }
    }

    /// While editing there is always an empty page at the end to drop onto.
    private var pageCount: Int {
        let pages = library.layout.pages
        let spare = model.isEditing && pages.last?.isEmpty == false && pages.count > 0
        return max(pages.count + (spare ? 1 : 0), 1)
    }

    var body: some View {
        @Bindable var model = model
        let width = geometry.size.width
        ScrollView(.horizontal) {
            ZStack(alignment: .topLeading) {
                // Empty wallpaper: a tap leaves edit mode, a long press enters it.
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { if model.isEditing { model.stopEditing() } }
                    .onLongPressGesture { model.startEditing() }

                ForEach(placements) { placement in
                    let center = geometry.iconCenter(placement.index)
                    HomeIcon(app: placement.app, geometry: geometry, labelSize: labelSize)
                        .frame(width: geometry.labelWidth, height: geometry.cellHeight, alignment: .top)
                        .position(x: CGFloat(placement.page) * width + center.x,
                                  y: center.y + (geometry.cellHeight - geometry.iconSize) / 2)
                }
            }
            .frame(width: CGFloat(pageCount) * width, height: geometry.size.height)
            .onDrop(of: [.text], delegate: GridDropDelegate(geometry: geometry, library: library, model: model, pageCount: pageCount))
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition($model.scroll)
        .scrollDisabled(model.isSearching)
        .onScrollGeometryChange(for: Int.self) { scroll in
            Int((scroll.contentOffset.x / max(width, 1)).rounded())
        } action: { _, page in
            model.page = page
        }
        .onScrollPhaseChange { _, phase in
            if pageCount > 1 { model.pagesMoved(phase != .idle) }
        }
        .background(TouchesBeginAtOnce())
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
                if let scroll = current.subviews.compactMap({ $0 as? UIScrollView }).first ?? current as? UIScrollView {
                    scroll.delaysContentTouches = false
                    return
                }
                ancestor = current.superview
            }
        }
    }
}
