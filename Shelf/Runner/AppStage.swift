import Kiln
import SwiftUI

/// Runs one app's source with Kiln and shows the result, its launch surface
/// before it, or the error screen instead. Used full screen inside an app's
/// card (`AppCard`) and inside the New App sheet as a preview.
///
/// Each run has a Kiln context of its own (plan §1.7, `RunContext`): the
/// app's settings, folder, `DB` session and permission gate. Part of the
/// app failing while it runs (a view's `body`, a row, anything Kiln would
/// draw its red label for) replaces the whole app with the error screen,
/// as an error Kiln finds before it runs does: the run's context carries
/// Shelf's screen (`KilnErrorScreen`), which hears of every error Kiln
/// draws.
///
/// The app and the error screen replace the launch surface with a short
/// crossfade (`Motion.launch`), as a native app replaces its launch screen.
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
    /// The library's data, settings and folders (`LibraryStore.host`).
    var host: AppHost
    /// What the app may use: the gate bound to it, or the preview's.
    var permissions: any AppPermissions
    /// Nothing is built until this is true. A card says so once its open has
    /// come to rest, so nothing on the main thread hitches the motion; the
    /// source is parsed off the main thread and the data session opens
    /// meanwhile.
    var isReady = true
    /// Off when something else (a card's face) already is the launch
    /// surface: the stage is then clear until the app is built, and fades
    /// it in over whatever is under it.
    var showsLaunchScreen = true
    /// The app, or the error screen, has finished fading in.
    var onLaunched: () -> Void = {}
    var onError: (CompileError) -> Void = { _ in }
    /// The error screen's title in place of "<name> couldn’t open" or
    /// "<name> stopped".
    var errorTitle: String?
    /// What the error screen's Copy for Agents copies. By default, the
    /// change prompt with the error and this source, and a key that lets
    /// the agent update the app (`AppHost.fixKey`) when there is one.
    var fixPrompt: (@MainActor (CompileError) async -> String)?
    /// The run has begun: a card keeps it, to tear it down when it closes.
    var onRun: (AppRun) -> Void = { _ in }

    @State private var result: KilnResult?
    /// A view's `body` failed while the app ran.
    @State private var bodyError: CompileError?
    /// The app has faded in, so the launch surface under it can go.
    @State private var isLaunched = false
    @State private var session: DBSession?
    @State private var parsed: KilnParsedSource?
    @State private var holder = RunHolder()

    var body: some View {
        ZStack {
            // Under the app as it fades in, so the two cross without the
            // sheet showing through between them.
            if showsLaunchScreen, !isLaunched {
                // The New App preview: what is being tried has never run,
                // so it has no snapshot.
                LaunchSurface(layout: LaunchLayout(source: source))
                    .ignoresSafeArea()
            }
            if let result {
                ZStack {
                    // Many apps leave their background clear.
                    Color(.systemBackground).ignoresSafeArea()
                    if let view = result.view, bodyError == nil {
                        view.onAppear { LaunchTiming.mark("shown", app.slug) }
                    } else {
                        let error = bodyError ?? CompileError(errors: result.errors, source: source)
                        ErrorScreen(face: IconFace(app), name: app.name, error: error,
                                    title: errorTitle ?? (result.view == nil ? nil : "\(app.name) stopped")) { await prompt(for: error) }
                    }
                }
                // Faded as one picture. Faded view by view, each of the
                // app's backgrounds, cells and text at the same opacity
                // over the launch surface, the surface's own text showed
                // through several of them and the screen went pale halfway.
                .compositingGroup()
                .transition(.opacity)
            }
        }
        // Once per open, with the source the app was opened with: a sync
        // during a session swaps in new code only after the app is closed and
        // reopened, as on iOS. The parse and the data session both start at
        // once, off the main thread, while the card is still growing.
        .task {
            result = nil
            bodyError = nil
            isLaunched = false
            session = nil
            parsed = nil
            async let parse = host.builds.take(app.slug, source: source)
            let opened = await open()
            guard !Task.isCancelled else {
                await close(opened)
                return
            }
            await holder.replace(with: opened, closingIn: synced)
            session = opened
            parsed = await parse
        }
        .task(id: isReady && session != nil && parsed != nil) {
            guard isReady, let session, let parsed, result == nil else { return }
            build(parsed, session: session)
        }
        .onDisappear {
            holder.run?.tearDown()
            Task { await holder.replace(with: nil, closingIn: synced) }
        }
    }

    private func build(_ parsed: KilnParsedSource, session: DBSession) {
        let context = switch store {
        case .synced: RunContext.installed(app, session: session, permissions: permissions, host: host)
        case .scratch: RunContext.scratch(app, session: session, permissions: permissions)
        }
        let run = AppRun(context: context, permissions: permissions)
        holder.run?.tearDown()
        holder.run = run
        onRun(run)
        let source = source, slug = app.slug
        // What shows is broken: the error screen takes the whole app's place.
        let fail = { [weak run] (error: KilnError) in
            guard let run, !run.isTornDown, bodyError == nil else { return }
            let screen = CompileError(errors: [error.description], source: source)
            withAnimation(Motion.launch) { bodyError = screen }
            onError(screen)
        }
        // Where Kiln would draw its red label: nothing, while the stage
        // swaps the app for its screen. Every error Kiln draws comes this
        // way, a row's or a style's as well as a `body`'s.
        context.provide(KilnErrorScreen { error in
            Color.clear.frame(width: 0, height: 0)
                .onAppear { fail(error) }
        })
        LaunchTiming.mark("build", app.slug)
        let built = Kiln.run(parsed, context: context)
        run.result = built
        LaunchTiming.mark("built", app.slug)
        context.onError = { [weak run] error in
            guard let run, !run.isTornDown else { return }
            switch error.phase {
            case .body:
                fail(error)
            case .check:
                // `result` already shows it.
                break
            case .runtime:
                RunContext.log.error("\(slug, privacy: .public): \(error.description, privacy: .public)")
            }
        }
        if built.view == nil { onError(CompileError(errors: built.errors, source: source)) }
        withAnimation(Motion.launch, completionCriteria: .removed) {
            result = built
        } completion: {
            isLaunched = true
            onLaunched()
        }
    }

    /// Copy for Agents: the caller's prompt, or the change prompt for this
    /// app with the error as the change and a key to update it with.
    private func prompt(for error: CompileError) async -> String {
        if let fixPrompt { return await fixPrompt(error) }
        let install = await host.fixKey(app.slug)
        return Prompts.fixApp(error.report, slug: app.slug, source: source, install: install)
    }

    /// Where a session is closed (saved and pushed): nowhere for a scratch one.
    private var synced: AppData? { store == .synced ? host.data : nil }

    private func open() async -> DBSession {
        switch store {
        case .synced: await host.data.open(app.slug)
        case .scratch(let slug): await host.data.scratch(copying: slug)
        }
    }

    private func close(_ session: DBSession) async {
        await synced?.close(session)
    }
}

/// The stage's run and data session, outliving the view values: closes the
/// session it replaces.
@MainActor
private final class RunHolder {
    var run: AppRun?
    private var session: DBSession?

    /// `data` closes the replaced session; nil when it was a scratch one.
    func replace(with next: DBSession?, closingIn data: AppData?) async {
        let previous = session
        session = next
        if let previous, let data, previous !== next { await data.close(previous) }
    }
}
