import SwiftUI

/// Matching apps in the Home Screen's own four columns, best match first,
/// between the status bar and the search field (`SearchBar`).
struct SearchResults: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HomeModel.self) private var model
    var geometry: HomeGeometry
    var labelSize: CGFloat
    /// From the bottom of the screen to just above the field.
    var bottom: CGFloat

    var body: some View {
        let results = library.items.matching(model.query)
        ScrollView {
            Group {
                if results.isEmpty {
                    // The title alone: the system's version adds a line of advice.
                    ContentUnavailableView("No Results for “\(model.query)”", systemImage: "magnifyingglass")
                        .environment(\.colorScheme, .dark)
                        .dynamicTypeSize(...ShelfMetrics.textSizeCap)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(geometry.labelWidth), spacing: geometry.columnPitch - geometry.labelWidth),
                                             count: Layout.columns),
                              spacing: geometry.rowPitch - geometry.cellHeight) {
                        ForEach(results) { item in
                            HomeIcon(item: item, geometry: geometry, labelSize: labelSize)
                                .frame(height: geometry.cellHeight, alignment: .top)
                                .environment(\.iconPlace, .result)
                        }
                    }
                    .padding(.top, HomeMetrics.topInset)
                }
            }
            // The content fills what is visible, so a tap anywhere that
            // isn't a result reaches it (the scroll view would take one
            // aimed at anything behind it) and closes search.
            .frame(maxWidth: .infinity, minHeight: geometry.size.height - geometry.safeTop - bottom, alignment: .top)
            .contentShape(.rect)
            .onTapGesture { model.endSearch() }
        }
        .scrollDismissesKeyboard(.immediately)
        .scrollBounceBehavior(.always)
        // Pulling the results down past their top closes search.
        .onScrollGeometryChange(for: Bool.self) { scroll in
            scroll.contentOffset.y + scroll.contentInsets.top < -HomeMetrics.searchPull
        } action: { _, pulled in
            if pulled { model.endSearch() }
        }
        .padding(.top, geometry.safeTop)
        .padding(.bottom, bottom)
        // Above and below the scroll view too.
        .background {
            Color.clear.contentShape(.rect).onTapGesture { model.endSearch() }
        }
    }
}
