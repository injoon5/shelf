import SwiftUI

@main
struct ShelfApp: App {
    @State private var library = ShelfApp.makeLibrary()
    @State private var settings = ShelfSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(settings)
        }
    }

    private static func makeLibrary() -> LibraryStore {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ShelfDemo") { return Demo.library() }
        #endif
        return LibraryStore()
    }
}

private struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if library.isSignedIn {
                HomeScreen()
            } else {
                ConnectScreen()
            }
        }
        .task { await library.sync() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await library.syncIfStale() }
            case .background:
                // Writes made in the last two seconds haven't been pushed yet.
                let task = UIApplication.shared.beginBackgroundTask()
                Task {
                    await library.data.pushAll()
                    UIApplication.shared.endBackgroundTask(task)
                }
            default:
                break
            }
        }
    }
}
