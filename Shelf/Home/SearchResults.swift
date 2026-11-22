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
        let results = library.apps.matching(model.query)
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
                        ForEach(results) { app in
                            HomeIcon(app: app, geometry: geometry, labelSize: labelSize)
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

extension [CachedApp] {
    /// Apps whose name matches `query`: names that start with it first, then
    /// names that contain it, each in alphabetical order. An empty query
    /// matches everything.
    func matching(_ query: String) -> [CachedApp] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let sorted = sorted { $0.meta.name.localizedStandardCompare($1.meta.name) == .orderedAscending }
        guard !needle.isEmpty else { return sorted }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let starts = sorted.filter { $0.meta.name.range(of: needle, options: options.union(.anchored)) != nil }
        let contains = sorted.filter { app in
            app.meta.name.range(of: needle, options: options) != nil && !starts.contains(app)
        }
        return starts + contains
    }
}
