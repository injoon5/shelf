//
//  KilnAudioSession.swift
//  Kiln's run context: who owns the audio session (PLAN.md §3.5)
//
//  Kiln never configures `AVAudioSession` itself. The host owns it: Shelf
//  decides the category (playback, mixing with other audio) and when the
//  session is active. A run's audio bridges (`AVAudioPlayer`, `AVPlayer`,
//  `AVSpeechSynthesizer`, `AudioServicesPlaySystemSound`) tell the host
//  through this hook, which the host provides to each run:
//
//      context.provide(KilnAudioSession(willPlay: { … activate … },
//                                       didStop: { … deactivate … }))
//
//  - `willPlay` runs before the run first makes a sound, once per run.
//  - `didStop` runs when the run's screen closes, after every player,
//    synthesizer and stream the run made has been stopped, and only if
//    `willPlay` ran.
//
//  Without a hook (Kiln Lab, tests), nothing touches the session: iOS's
//  default category applies.
//

import Foundation

@MainActor
public final class KilnAudioSession {
    let willPlay: @MainActor () -> Void
    let didStop: @MainActor () -> Void

    public init(willPlay: @escaping @MainActor () -> Void, didStop: @escaping @MainActor () -> Void) {
        self.willPlay = willPlay
        self.didStop = didStop
    }
}

/// One run's sound: what it made, so teardown stops all of it before the
/// host's `didStop` (a session can't be deactivated while a player runs).
@MainActor
final class KAudioRun {
    private weak var context: KilnContext?
    private var stoppers: [ObjectIdentifier: @MainActor () -> Void] = [:]
    private(set) var hasPlayed = false

    private init(_ context: KilnContext) { self.context = context }

    /// The run's audio, made (and its teardown registered) when first used.
    static func of(_ context: KilnContext) -> KAudioRun {
        if let run = context.provided(KAudioRun.self) { return run }
        let run = KAudioRun(context)
        context.provide(run)
        context.onTearDown { run.stopAll() }
        return run
    }

    /// Stops `object` when the screen closes. Tracking it again replaces the stopper.
    func track(_ object: AnyObject, stop: @escaping @MainActor () -> Void) {
        stoppers[ObjectIdentifier(object)] = stop
    }

    /// Before any sound: the host's hook, once.
    func willPlay() {
        guard !hasPlayed, let context, !context.isTornDown else { return }
        hasPlayed = true
        context.provided(KilnAudioSession.self)?.willPlay()
    }

    private func stopAll() {
        let running = stoppers
        stoppers = [:]
        for stop in running.values { stop() }
        if hasPlayed { context?.provided(KilnAudioSession.self)?.didStop() }
    }
}
