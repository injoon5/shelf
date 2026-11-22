import SwiftUI

/// The field the search pill turns into.
struct SearchField: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HomeModel.self) private var model
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var model = model
        HStack(spacing: HomeMetrics.bannerSpacing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $model.query)
                .focused($isFocused)
                .submitLabel(.go)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    // Return opens the best match.
                    guard let best = library.apps.matching(model.query).first else { return }
                    Task { await model.open(best.slug, in: library) }
                }
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: HomeMetrics.minimumHit, minHeight: HomeMetrics.minimumHit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.body)
        .padding(.leading, HomeMetrics.searchSideInset)
        .padding(.trailing, model.query.isEmpty ? HomeMetrics.searchSideInset : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular.interactive(), in: .capsule)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .onAppear { isFocused = true }
    }
}

/// Matching apps in the Home Screen's own four columns, best match first.
struct SearchResults: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HomeModel.self) private var model
    var geometry: HomeGeometry
    var labelSize: CGFloat

    var body: some View {
        let results = library.apps.matching(model.query)
        let top = geometry.safeTop + HomeMetrics.searchTopGap * 2 + HomeMetrics.searchFieldHeight
        ScrollView {
            if results.isEmpty {
                ContentUnavailableView.search(text: model.query)
                    .environment(\.colorScheme, .dark)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(geometry.labelWidth), spacing: geometry.columnPitch - geometry.labelWidth),
                                         count: HomeMetrics.columns),
                          spacing: geometry.rowPitch - geometry.cellHeight) {
                    ForEach(results) { app in
                        HomeIcon(app: app, geometry: geometry, labelSize: labelSize)
                            .frame(height: geometry.cellHeight, alignment: .top)
                    }
                }
                .padding(.top, HomeMetrics.topInset)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .scrollBounceBehavior(.always)
        // Pulling the results down past their top closes search.
        .onScrollGeometryChange(for: Bool.self) { scroll in
            scroll.contentOffset.y + scroll.contentInsets.top < -HomeMetrics.searchPull
        } action: { _, pulled in
            if pulled { model.endSearch() }
        }
        .padding(.top, top)
        .padding(.bottom, geometry.size.height - geometry.dockFrame.maxY)
        // Tapping anywhere that isn't a result closes search.
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
