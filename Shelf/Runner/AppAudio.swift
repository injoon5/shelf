import AVFoundation
import Kiln

/// Shelf owns the audio session (plan §3.5); Kiln only tells it when an app
/// is about to make a sound and when that app's sound has all stopped.
///
/// The policy:
/// - **Playback**, so an app's sound plays with the ring switch on silent,
///   as a music or speech app's would.
/// - **Mixing with other audio**: an app never stops the user's music or
///   podcast. An app that wants the user's full attention is still a card
///   on a Home Screen, not a media app.
/// - **Active only while an app that played is open.** Kiln stops every
///   player, stream and synthesizer the app made when its card closes, then
///   calls `didStop`; the session is deactivated and other apps are told
///   they can resume (`.notifyOthersOnDeactivation`).
///
/// No background audio: background modes are on the won't-do list, so an
/// app's sound stops when Shelf leaves the screen.
@MainActor
enum AppAudio {
    /// Runs that have played and not yet stopped. A card closing while the
    /// next one opens can overlap them for a moment.
    private(set) static var playing = 0

    /// The hook a run's context carries.
    static func session() -> KilnAudioSession {
        KilnAudioSession(willPlay: { begin() }, didStop: { end() })
    }

    static func begin() {
        playing += 1
        guard playing == 1 else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            RunContext.log.error("audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func end() {
        guard playing > 0 else { return }
        playing -= 1
        guard playing == 0 else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
