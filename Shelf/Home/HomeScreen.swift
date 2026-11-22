import SwiftUI

/// The Home Screen: icons on a wallpaper, a glass dock, and apps that zoom out
/// of their icon. There is no navigation stack here; an app gets its own
/// presentation, so its own stack never nests inside a launcher's.
struct HomeScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = HomeModel()
    @Namespace private var zoom
    @Namespace private var glass

    var body: some View {
        @Bindable var model = model
        GeometryReader { outer in
            let safeTop = outer.safeAreaInsets.top
            GeometryReader { inner in
                HomeContent(size: inner.size, safeTop: safeTop, glass: glass)
                    // Labels stop growing here, as Springboard's do, so the grid never breaks.
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard)
        .environment(model)
        .environment(\.zoomNamespace, zoom)
        .statusBarHidden(model.isEditing)
        .fullScreenCover(item: $model.run) { run in
            RunnerView(run: run)
                .navigationTransition(.zoom(sourceID: run.id, in: zoom))
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .settings: SettingsView()
            case .newApp: NewAppSheet(app: nil, source: nil)
            case .change(let app): NewAppSheet(app: app, source: library.source(for: app.slug))
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.launches)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.editStarts)
        .onChange(of: model.run) { _, run in
            // An app opened from search closes back onto the Home Screen.
            guard run != nil, model.isSearching else { return }
            Task {
                try? await Task.sleep(for: Motion.launchSettle)
                model.isSearching = false
            }
        }
        .onChange(of: library.isSignedIn) { model.stopEditing() }
        // A drag the system cancels never reaches a drop target, so nothing
        // else would bring its icon back.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.endDrag() }
        }
    }
}

private struct HomeContent: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HomeModel.self) private var model
    @Environment(ShelfSettings.self) private var settings
    @Environment(\.zoomNamespace) private var zoom
    @ScaledMetric(relativeTo: .caption2) private var labelSize = HomeMetrics.labelSize
    var size: CGSize
    var safeTop: CGFloat
    var glass: Namespace.ID

    private var geometry: HomeGeometry {
        HomeGeometry(size: size, safeTop: safeTop, displayRadius: Display.cornerRadius,
                     labelHeight: UIFont.systemFont(ofSize: labelSize, weight: .medium).lineHeight)
    }

    /// Light or dark content for the search field, after the wallpaper behind it.
    private var searchTone: ColorScheme {
        let top = (safeTop + HomeMetrics.searchTopGap) / max(size.height, 1)
        return Wallpaper.tone(settings, screen: size, band: top...(top + HomeMetrics.searchFieldHeight / max(size.height, 1)))
    }

    var body: some View {
        let geometry = geometry
        let isSearching = model.isSearching
        ZStack {
            Wallpaper(isPaused: model.run != nil)
            Color.black.opacity(isSearching ? HomeMetrics.searchDim : 0)

            Group {
                if library.apps.isEmpty {
                    EmptyLibrary(geometry: geometry)
                } else {
                    IconGrid(geometry: geometry, labelSize: labelSize)
                        // While search is up, its results are what apps zoom out of.
                        .environment(\.zoomNamespace, isSearching ? nil : zoom)
                }
            }
            .opacity(isSearching ? 0 : 1)
            .allowsHitTesting(!isSearching)

            // One container, so the dock and the pill refract as one surface
            // and the pill can become the search field.
            GlassEffectContainer(spacing: HomeMetrics.pageDotGap) {
                ZStack {
                    DockGlass(geometry: geometry)
                        .opacity(isSearching ? 0 : 1)
                    if isSearching {
                        SearchField(tone: searchTone)
                            .glassEffectID("search", in: glass)
                            .frame(width: size.width - 2 * HomeMetrics.searchSideInset, height: HomeMetrics.searchFieldHeight)
                            .position(x: size.width / 2, y: safeTop + HomeMetrics.searchTopGap + HomeMetrics.searchFieldHeight / 2)
                    } else {
                        SearchPill(pageCount: model.pageCount(library.layout.pages))
                            .glassEffectID("search", in: glass)
                            .position(x: geometry.pillFrame.midX, y: geometry.pillFrame.midY)
                    }
                }
            }

            DockIcons(geometry: geometry, labelSize: labelSize)
                .environment(\.zoomNamespace, isSearching ? nil : zoom)
                .opacity(isSearching ? 0 : 1)
                .allowsHitTesting(!isSearching)

            if isSearching {
                SearchResults(geometry: geometry, labelSize: labelSize)
                    .transition(.opacity)
            }

            if model.isEditing {
                EditControls()
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, HomeMetrics.editButtonTop)
                    .transition(.opacity)
            }

            if let banner = library.banner {
                SyncBanner(banner: banner) {
                    library.hideBanner()
                    if banner == .tokenExpired { model.sheet = .settings }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, safeTop + HomeMetrics.bannerTopGap)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.standard, value: library.banner)
        // Pulling down anywhere on the grid opens search.
        .simultaneousGesture(
            DragGesture(minimumDistance: HomeMetrics.pageFlipEdge).onEnded { drag in
                let down = drag.translation.height
                guard !isSearching, down > HomeMetrics.searchPull, abs(drag.translation.width) < down / 2 else { return }
                model.beginSearch()
            }
        )
    }
}

/// The two buttons edit mode adds, where Springboard puts its own and in the
/// same glass capsules: New App on the left, Done on the right.
private struct EditControls: View {
    @Environment(HomeModel.self) private var model

    var body: some View {
        HStack {
            EditButton(symbol: "plus", title: "New App") { model.sheet = .newApp }
            Spacer()
            EditButton(symbol: "checkmark", title: "Done") { model.stopEditing() }
        }
        .padding(.horizontal, HomeMetrics.editButtonInset)
    }
}

private struct EditButton: View {
    @Environment(\.colorScheme) private var scheme
    var symbol: String
    var title: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        let size = HomeMetrics.editButtonSize
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: size.width, height: size.height)
                .glassEffect(HomeMetrics.glass(scheme).interactive(), in: .capsule)
                // The capsule is shorter than a finger; the target isn't.
                .padding(.vertical, (HomeMetrics.minimumHit - size.height) / 2)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, -(HomeMetrics.minimumHit - size.height) / 2)
        .accessibilityLabel(title)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

/// What stands in for the grid when there are no apps: still loading, failed
/// to load, or really empty.
private struct EmptyLibrary: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HomeModel.self) private var model
    var geometry: HomeGeometry
    @State private var showsSpinner = false

    var body: some View {
        Group {
            if let failure = library.loadFailure {
                ContentUnavailableView {
                    Label(failure == .unauthorized ? "Token Expired" : "Can't Reach Server",
                          systemImage: failure == .unauthorized ? "key" : "wifi.slash")
                } actions: {
                    if failure == .unauthorized {
                        Button("Open Settings") { model.sheet = .settings }
                            .buttonStyle(.glassProminent)
                    } else {
                        Button("Try Again") { Task { await library.sync() } }
                            .buttonStyle(.glassProminent)
                    }
                }
            } else if library.isSyncing {
                ProgressView()
                    .controlSize(.large)
                    .opacity(showsSpinner ? 1 : 0)
                    .task {
                        try? await Task.sleep(for: Motion.spinnerDelay)
                        withAnimation(Motion.fade) { showsSpinner = true }
                    }
            } else {
                ContentUnavailableView {
                    Label("No Apps", systemImage: "square.grid.2x2")
                } actions: {
                    Button("New App") { model.sheet = .newApp }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        // The wallpaper is dark in both modes; draw on it as on a dark surface.
        .environment(\.colorScheme, .dark)
        .padding(.bottom, geometry.size.height - geometry.pillFrame.minY)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// The screen's own corner radius, which the dock's corners follow.
@MainActor
enum Display {
    static let cornerRadius: CGFloat = {
        // UIKit knows the radius but doesn't publish it. Asking by name fails
        // soft: if the name ever goes away, the fallback is used.
        let key = "_displayCornerRadius"
        guard let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen,
              screen.responds(to: Selector(key)),
              let radius = screen.value(forKey: key) as? CGFloat, radius > 0 else {
            return HomeMetrics.fallbackDisplayRadius
        }
        return radius
    }()
}
