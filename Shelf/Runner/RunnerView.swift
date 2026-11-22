import Kiln
import SwiftUI

/// An app, full screen. It grows out of its icon behind a launch screen in the
/// app's tint; once the zoom has settled, Kiln builds the app and it fades in.
struct RunnerView: View {
    // Kiln exports an `Environment` of its own.
    @SwiftUI.Environment(\.dismiss) private var dismiss
    var run: HomeModel.Run

    var body: some View {
        AppStage(app: run.app.meta, source: run.source, store: .synced)
            .overlay(alignment: .top) {
                // Apps with their own vertical drags can fight the system's
                // pull-to-close. From the status bar, down always closes.
                Color.clear
                    .frame(height: RunnerMetrics.dismissStrip)
                    .contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: RunnerMetrics.dismissDistance).onEnded { drag in
                        if drag.translation.height > RunnerMetrics.dismissDistance { dismiss() }
                    })
                    .ignoresSafeArea()
            }
    }
}

/// Runs one app's source with Kiln and shows the result, a launch screen
/// before it, or the error screen instead. Used full screen by the runner and
/// inside the New App sheet as a preview.
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
    /// The launch screen waits out the zoom; a preview has no zoom to wait for.
    var settle: Duration = Motion.launchSettle
    var onError: (CompileError) -> Void = { _ in }

    @State private var result: KilnResult?
    @State private var holder = SessionHolder()

    var body: some View {
        ZStack {
            // Many apps leave their background clear.
            Color(.systemBackground).ignoresSafeArea()
            if let result {
                if let view = result.view {
                    view.transition(.opacity)
                } else {
                    ErrorScreen(face: IconFace(app), name: app.name, error: CompileError(errors: result.errors, source: source))
                        .transition(.opacity)
                }
            } else {
                LaunchScreen(face: IconFace(app))
                    .transition(.opacity)
            }
        }
        // Once per open and once per version: a sync during a session swaps in
        // new code only after the app is closed and reopened, as on iOS.
        .task(id: app.version + source.count.description) {
            result = nil
            async let opening = open()
            try? await Task.sleep(for: settle)
            let session = await opening
            guard !Task.isCancelled else {
                await close(session)
                return
            }
            await holder.replace(with: session, synced: store == .synced)
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
        case .synced: await AppData.shared.open(app.slug, pullTimeout: Motion.dataPullTimeout)
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
