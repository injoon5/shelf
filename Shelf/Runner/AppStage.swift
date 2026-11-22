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
    /// The library's data store (`LibraryStore.data`), which both kinds of
    /// store come from.
    var data: AppData
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
            await holder.replace(with: session, closingIn: synced)
            hasSession = true
        }
        .task(id: isReady && hasSession) {
            guard isReady, hasSession, result == nil else { return }
            let built = Kiln.run(SourceRewriter.prepare(source, slug: app.slug))
            if built.view == nil { onError(CompileError(errors: built.errors, source: source)) }
            withAnimation(Motion.launch) { result = built }
        }
        .onDisappear {
            Task { await holder.replace(with: nil, closingIn: synced) }
        }
    }

    /// Where a session is closed (saved and pushed): nowhere for a scratch one.
    private var synced: AppData? { store == .synced ? data : nil }

    private func open() async -> DBSession {
        switch store {
        case .synced: await data.open(app.slug)
        case .scratch(let slug): await data.scratch(copying: slug)
        }
    }

    private func close(_ session: DBSession) async {
        await synced?.close(session)
    }
}

/// Keeps the `db://` protocol pointed at whichever session is on screen, and
/// closes the one it replaces.
@MainActor
private final class SessionHolder {
    private var session: DBSession?

    /// `data` closes the replaced session; nil when it was a scratch one.
    func replace(with next: DBSession?, closingIn data: AppData?) async {
        let previous = session
        session = next
        if let next { ShelfDBProtocol.activate(next) }
        if let previous {
            if next == nil { ShelfDBProtocol.deactivate(previous) }
            if let data, previous !== next { await data.close(previous) }
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
