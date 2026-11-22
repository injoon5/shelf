import Kiln
import SwiftUI

/// Runs one app's source with Kiln and shows the result, a launch screen
/// before it, or the error screen instead. Used full screen inside an app's
/// card (`AppCard`) and inside the New App sheet as a preview.
struct AppStage: View {
    /// Where the app's `DB` calls go.
    enum Store: Equatable {
        /// The app's real data, synced with the server.
        case synced
        /// A throwaway store, optionally starting from a copy of an app's data.
        case scratch(copying: String?)
    }

    var app: AppMeta
    var source: String
    var store: Store
    /// Nothing is built until this is true. A card says so once its open has
    /// come to rest, because Kiln parses on the main thread and would hitch
    /// the motion; the data session opens meanwhile.
    var isReady = true
    /// Off when something else (a card's face) already is the launch screen:
    /// the stage is then clear until the app is built.
    var showsLaunchScreen = true
    var onError: (CompileError) -> Void = { _ in }

    @State private var result: KilnResult?
    @State private var hasSession = false
    @State private var holder = SessionHolder()

    var body: some View {
        ZStack {
            if let result {
                ZStack {
                    // Many apps leave their background clear.
                    Color(.systemBackground).ignoresSafeArea()
                    if let view = result.view {
                        view
                    } else {
                        ErrorScreen(face: IconFace(app), name: app.name, error: CompileError(errors: result.errors, source: source))
                    }
                }
                .transition(.opacity)
            } else if showsLaunchScreen {
                LaunchScreen(face: IconFace(app))
                    .transition(.opacity)
            }
        }
        // Once per open, with the source the app was opened with: a sync
        // during a session swaps in new code only after the app is closed and
        // reopened, as on iOS.
        .task {
            result = nil
            hasSession = false
            let session = await open()
            guard !Task.isCancelled else {
                await close(session)
                return
            }
            await holder.replace(with: session, synced: store == .synced)
            hasSession = true
        }
        .task(id: isReady && hasSession) {
            guard isReady, hasSession, result == nil else { return }
            let built = Kiln.run(SourceRewriter.prepare(source, slug: app.slug))
            if built.view == nil { onError(CompileError(errors: built.errors, source: source)) }
            withAnimation(Motion.launch) { result = built }
        }
        .onDisappear {
            Task { await holder.replace(with: nil, synced: store == .synced) }
        }
    }

    private func open() async -> DBSession {
        switch store {
        case .synced: await AppData.shared.open(app.slug)
        case .scratch(let slug): await AppData.shared.scratch(copying: slug)
        }
    }

    private func close(_ session: DBSession) async {
        if store == .synced { await AppData.shared.close(session) }
    }
}

/// Keeps the `db://` protocol pointed at whichever session is on screen, and
/// closes the one it replaces.
@MainActor
private final class SessionHolder {
    private var session: DBSession?

    func replace(with next: DBSession?, synced: Bool) async {
        let previous = session
        session = next
        if let next { ShelfDBProtocol.activate(next) }
        if let previous {
            if next == nil { ShelfDBProtocol.deactivate(previous) }
            if synced, previous !== next { await AppData.shared.close(previous) }
        }
    }
}

/// Like a native app's launch screen: the tint, and the glyph where the icon's was.
private struct LaunchScreen: View {
    var face: IconFace

    var body: some View {
        ZStack {
            face.tint.ignoresSafeArea()
            Image(systemName: face.symbol)
                .font(.system(size: HomeMetrics.iconSize * HomeMetrics.glyphRatio, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
    }
}
