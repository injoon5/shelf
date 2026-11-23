import SwiftUI

/// The Home Screen: icons on a wallpaper, a glass dock, and apps that open
/// out of their icon. There is no navigation stack here; each app is a
/// card with its own view controller (`AppCard`), so its own stack never
/// nests inside a launcher's. The stage (`HomeStage`, in UIKit) draws and
/// moves everything; this view keeps the state, the sheets and the status bar.
struct HomeScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ShelfSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = HomeModel()

    var body: some View {
        @Bindable var model = model
        HomeStage(model: model, library: library, settings: settings)
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
            .onChange(of: library.isSignedIn) { model.stopEditing() }
            // Leaving the foreground ends a drag (the stage lets go of its
            // icon when the model says so) and saves where it left the others.
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    model.endDrag()
                    library.commitLayout()
                }
            }
            .onChange(of: model.isEditing) { _, isEditing in
                if !isEditing { library.finishEditing() }
            }
            .onChange(of: library.layout) { old, new in
                model.layoutChanged(from: old, to: new, in: library)
            }
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
