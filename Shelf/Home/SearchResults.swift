import SwiftUI

/// Search's results, hosted by the stage. Search is rebuilt as App
/// Library's list in UIKit next (PLAN.md §0.3), which replaces this file;
/// until then it draws its icons with the Home Screen's renderer.
struct ResultsLayer: View {
    var model: HomeModel
    var library: LibraryStore
    var layout: ResultsLayout

    var body: some View {
        // The results carry the Home Screen's cap, "No Results" the app's.
        SearchResults(geometry: layout.geometry, labelSize: layout.labelSize, bottom: layout.resultsBottom)
            .frame(width: layout.geometry.size.width, height: layout.geometry.size.height)
            .ignoresSafeArea()
            .environment(model)
            .environment(library)
            .environment(layout)
            .coordinateSpace(.named(ResultsLayout.space))
    }
}

extension ResultsLayout {
    /// The coordinate space results report their frames in: the stage's own.
    nonisolated static let space = "stage"
}

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
                            ResultIcon(item: item, geometry: geometry, labelSize: labelSize)
                                .frame(height: geometry.cellHeight, alignment: .top)
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

/// One result: the icon, its name, a tap to open it and the icon's menu.
private struct ResultIcon: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HomeModel.self) private var model
    @Environment(ResultsLayout.self) private var layout
    var item: HomeItem
    var geometry: HomeGeometry
    var labelSize: CGFloat

    var body: some View {
        let size = geometry.iconSize
        Button {
            Task { await model.open(item.id, in: library) }
        } label: {
            VStack(spacing: HomeMetrics.labelGap) {
                ResultArt(face: item.face, size: size)
                    .opacity(layout.cardIcons.contains(item.id) ? 0 : 1)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(ResultsLayout.space))
                    } action: { frame in
                        layout.frames[item.id] = frame
                    }
                    .onDisappear { layout.frames[item.id] = nil }
                Text(item.name)
                    .font(.system(size: labelSize, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(HomeMetrics.labelShadowOpacity), radius: HomeMetrics.labelShadowRadius,
                            y: HomeMetrics.labelShadowY)
                    .frame(width: geometry.labelWidth)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressStyle())
        .contentShape(.contextMenuPreview, HomeMetrics.iconShape(size).offset(y: 0))
        .contextMenu {
            ForEach(Array(item.menu(model: model, library: library).enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(Array(group.enumerated()), id: \.offset) { _, action in
                        Button(action.title, systemImage: action.symbol, role: action.isDestructive ? .destructive : nil) {
                            action.perform()
                        }
                        .disabled(!action.isEnabled)
                    }
                }
            }
        }
        .accessibilityLabel(item.name)
        .dynamicTypeSize(...HomeMetrics.textSizeCap)
    }
}

/// The icon in a result, pressed while the finger is down.
private struct ResultArt: View {
    @Environment(\.isResultPressed) private var isPressed
    var face: IconFace
    var size: CGFloat

    var body: some View {
        IconImage(face: face, size: size, isPressed: isPressed)
            .frame(width: size, height: size)
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.isResultPressed, configuration.isPressed)
    }
}

extension EnvironmentValues {
    @Entry fileprivate var isResultPressed = false
}
