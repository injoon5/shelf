import SwiftUI

/// The Home Screen: icons on a wallpaper, a glass dock, and apps that open
/// out of their icon. There is no navigation stack here; each app is a
/// card with its own view controller (`AppCard`), so its own stack never
/// nests inside a launcher's. The stage (`HomeStage`) does the motion; this
/// view keeps the state and the sheets.
struct HomeScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ShelfSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = HomeModel()

    var body: some View {
        @Bindable var model = model
        HomeStage(model: model, library: library, settings: settings,
                  input: StageInput(run: model.run, isSearching: model.isSearching, isEditing: model.isEditing,
                                    showsPageDots: model.showsPageDots,
                                    pageCount: model.pageCount(library.layout.pages), page: model.page))
            .ignoresSafeArea()
            .statusBarHidden(model.isEditing)
            // With an app open, the first swipe up from the bottom edge is
            // Shelf's, and takes the app back to the Home Screen; a second
            // leaves Shelf. The same at the top, where a pull down closes the
            // app before it opens Notification Center. With none open, the
            // system has the edges to itself.
            .defersSystemGestures(on: model.run == nil ? [] : [.top, .bottom])
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
                if run != nil, model.isSearching { model.endSearch() }
            }
            .onChange(of: library.isSignedIn) { model.stopEditing() }
            // A drag the system cancels never reaches a drop target, so nothing
            // else would bring its icon back, or save where it left the others.
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    model.endDrag()
                    library.commitLayout()
                }
            }
            .onChange(of: model.isEditing) { _, isEditing in
                if !isEditing { library.commitLayout() }
            }
    }
}

/// What every layer of the stage reads.
struct StageEnvironment {
    var model: HomeModel
    var library: LibraryStore
    var settings: ShelfSettings
    var layout: StageLayout
}

extension View {
    /// A layer of the stage, hosted on its own: the stage's objects, and the
    /// coordinate space icons report their frames in. It ignores every safe
    /// area, the keyboard's included: the stage gives it the geometry.
    func stage(_ stage: StageEnvironment) -> some View {
        ignoresSafeArea()
            .environment(stage.model)
            .environment(stage.library)
            .environment(stage.settings)
            .environment(stage.layout)
            .coordinateSpace(.named(StageLayout.space))
    }
}

struct WallpaperLayer: View {
    var stage: StageEnvironment

    var body: some View {
        // The gradient stops drifting while an app covers it.
        Wallpaper(isPaused: stage.model.run != nil)
            .stage(stage)
    }
}

/// The grid, the dock and edit mode's buttons: what search fades away.
struct IconsLayer: View {
    var stage: StageEnvironment

    var body: some View {
        // No cap on the whole layer: the icons and edit buttons carry the
        // Home Screen's, and the empty library and the banner the app's.
        IconsContent()
            .stage(stage)
    }
}

private struct IconsContent: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HomeModel.self) private var model
    @Environment(StageLayout.self) private var layout

    var body: some View {
        let geometry = layout.geometry
        ZStack {
            Group {
                if library.apps.isEmpty {
                    EmptyLibrary(geometry: geometry)
                } else {
                    IconGrid(geometry: geometry, labelSize: layout.labelSize)
                }
            }

            DockGlass(geometry: geometry)
            DockIcons(geometry: geometry, labelSize: layout.labelSize)
                .environment(\.iconPlace, .dock)

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
                .padding(.top, geometry.safeTop + HomeMetrics.bannerTopGap)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .animation(Motion.standard, value: library.banner)
    }
}

/// Search results, which search fades in.
struct ResultsLayer: View {
    var stage: StageEnvironment

    var body: some View {
        // The results carry the Home Screen's cap, "No Results" the app's.
        ResultsContent()
            .stage(stage)
    }
}

private struct ResultsContent: View {
    @Environment(StageLayout.self) private var layout

    var body: some View {
        SearchResults(geometry: layout.geometry, labelSize: layout.labelSize, bottom: layout.resultsBottom)
            .frame(width: layout.geometry.size.width, height: layout.geometry.size.height)
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
        .dynamicTypeSize(...HomeMetrics.textSizeCap)
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
        .dynamicTypeSize(...ShelfMetrics.textSizeCap)
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
