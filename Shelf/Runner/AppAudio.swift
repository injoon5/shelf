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
/// - **Recording** (plan §4.4): while an app's `AVAudioRecorder` records,
///   the session is `.playAndRecord` (still mixing, sound from the speaker,
///   Bluetooth headsets allowed); when the last recorder stops, back to
///   `.playback`, or off if nothing plays. Kiln stops recorders when the
///   card closes, before `didStop`.
///
/// No background audio: background modes are on the won't-do list, so an
/// app's sound stops when Shelf leaves the screen.
@MainActor
enum AppAudio {
    /// Runs that have played and not yet stopped. A card closing while the
    /// next one opens can overlap them for a moment.
    private(set) static var playing = 0
    /// Runs recording now.
    private(set) static var recording = 0

    /// The hook a run's context carries.
    static func session() -> KilnAudioSession {
        KilnAudioSession(willPlay: { begin() }, didStop: { end() },
                         willRecord: { beginRecording() }, didStopRecording: { endRecording() })
    }

    /// The category for what's happening now.
    static func configure() throws {
        let session = AVAudioSession.sharedInstance()
        if recording > 0 {
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
        } else {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
    }

    static func beginRecording() {
        recording += 1
        guard recording == 1 else { return }
        do {
            try configure()
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            RunContext.log.error("audio session (recording): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func endRecording() {
        guard recording > 0 else { return }
        recording -= 1
        guard recording == 0 else { return }
        if playing > 0 {
            try? configure()
        } else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    static func begin() {
        playing += 1
        guard playing == 1, recording == 0 else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try configure()
            try session.setActive(true)
        } catch {
            RunContext.log.error("audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func end() {
        guard playing > 0 else { return }
        playing -= 1
        guard playing == 0, recording == 0 else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
