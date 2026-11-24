//
//  Recording.swift
//  Bridges: recording sound (PLAN.md §4.4)
//
//      let url = URL.documentsDirectory.appending(path: "memo.m4a")
//      let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1]
//      recorder = try AVAudioRecorder(url: url, settings: settings)
//      recorder?.isMeteringEnabled = true
//      recorder?.record()
//      …
//      recorder?.updateMeters()
//      level = recorder?.averagePower(forChannel: 0) ?? -160
//
//  - Into the app's own folder only: a URL elsewhere is an error with its line.
//  - The microphone goes through the capability gate. `record()` with the
//    microphone allowed starts at once; not yet asked, it asks (Shelf's
//    sheet, then iOS's prompt) and starts when allowed; refused, it returns
//    `false`, as the app's `recordPermission` check would have said. An app
//    that asks first (`AVAudioApplication.requestRecordPermission()`) gets
//    the gate's answer there.
//  - Shelf owns the audio session (`KilnAudioSession`): it switches to
//    recording while a recorder records, and back. The app's own
//    `AVAudioSession` calls are accepted and change nothing.
//  - A recorder stops when the app's screen closes.
//  - Where there's no microphone to use (a check, or a host's
//    `KilnFakeMicrophone`), a fake records a tone and meters a level that
//    rises and falls, so a level meter moves.
//

import Foundation
import AVFoundation

extension AudioBridges {
    static func recording(_ r: KRegistry) {
        recorder(r)
        session(r)
    }

    // MARK: AVAudioRecorder

    static func recorder(_ r: KRegistry) {
        r.type("AVAudioRecorder", .audio, support: .full,
               notes: "Into a file in the app's folder (`URL.documentsDirectory`); `record()` asks for the microphone first. `isMeteringEnabled`, `updateMeters()`, `averagePower(forChannel:)` for a level meter. Stops when the app closes.") { t in
            t.initializer("url:URL settings:any") { c in
                let url = try FoundationBridges.file(c, "url")
                let settings = recorderSettings(c["settings"], c.interp)
                let recorder = try KRecorder(url: url, settings: settings, c)
                return .native(.object("AVAudioRecorder", KRef(recorder)))
            }
            @MainActor func rec(_ c: KCall) -> KRecorder? { c.object(KRecorder.self) }
            @MainActor func me(_ c: KCall) -> KV { c.receiver }
            t.method("prepareToRecord", "") { c in .bool(rec(c)?.prepare() ?? false) }
            t.method("record", "") { c in .bool(rec(c)?.record(me(c), c) ?? false) }
            t.method("record", "forDuration:number") { c in .bool(rec(c)?.record(me(c), c, duration: c.double("forDuration")) ?? false) }
            t.method("record", "atTime:number forDuration:number?") { c in .bool(rec(c)?.record(me(c), c, duration: c.double("forDuration")) ?? false) }
            t.method("pause", "") { c in rec(c)?.pause(); return .void }
            t.method("stop", "") { c in rec(c)?.stop(); return .void }
            t.method("deleteRecording", "") { c in .bool(rec(c)?.delete() ?? false) }
            t.property("isRecording") { c in .bool(rec(c)?.isRecording ?? false) }
            t.property("currentTime") { c in .double(rec(c)?.currentTime ?? 0) }
            t.property("deviceCurrentTime") { c in .double(rec(c)?.deviceCurrentTime ?? 0) }
            t.property("url") { c in rec(c).map { .native(.url($0.url)) } ?? .nilValue }
            t.property("settings") { c in
                var out: [KV: KV] = [:]
                for (k, v) in rec(c)?.settings ?? [:] { out[.string(k)] = KNativeValues.kv(from: v) }
                return .dict(out)
            }
            t.property("isMeteringEnabled", { c in .bool(rec(c)?.isMeteringEnabled ?? false) },
                       set: { c in rec(c)?.isMeteringEnabled = c.bool(0, default: false) })
            t.method("updateMeters", "") { c in rec(c)?.updateMeters(); return .void }
            t.method("averagePower", "forChannel:number") { c in .double(Double(rec(c)?.averagePower() ?? -160)) }
            t.method("peakPower", "forChannel:number") { c in .double(Double(rec(c)?.peakPower() ?? -160)) }
            t.property("delegate", { c in rec(c)?.delegateValue ?? .nilValue }, set: { c in
                guard let recorder = rec(c) else { return }
                if c.args[0].isNil { recorder.delegateValue = nil; return }
                guard let app = KAppValue(c.args[0], c.interp), app.type.conforms("AVAudioRecorderDelegate") else {
                    throw c.fail("the delegate should be a class that adopts AVAudioRecorderDelegate")
                }
                recorder.delegateValue = c.args[0]
            })
        }
        r.delegateProtocol("AVAudioRecorderDelegate", .audio,
                           requirements: ["audioRecorderDidFinishRecording(_:successfully:)?", "audioRecorderEncodeErrorDidOccur(_:error:)?"])

        // The settings' keys and values.
        for (name, key) in [("AVFormatIDKey", AVFormatIDKey), ("AVSampleRateKey", AVSampleRateKey), ("AVNumberOfChannelsKey", AVNumberOfChannelsKey),
                            ("AVEncoderAudioQualityKey", AVEncoderAudioQualityKey), ("AVEncoderBitRateKey", AVEncoderBitRateKey),
                            ("AVEncoderBitDepthHintKey", AVEncoderBitDepthHintKey), ("AVLinearPCMBitDepthKey", AVLinearPCMBitDepthKey),
                            ("AVLinearPCMIsFloatKey", AVLinearPCMIsFloatKey), ("AVLinearPCMIsBigEndianKey", AVLinearPCMIsBigEndianKey),
                            ("AVLinearPCMIsNonInterleaved", AVLinearPCMIsNonInterleaved), ("AVSampleRateConverterAudioQualityKey", AVSampleRateConverterAudioQualityKey)] {
            r.addConstant(name) { _ in .string(key) }
        }
        for (name, id) in [("kAudioFormatMPEG4AAC", kAudioFormatMPEG4AAC), ("kAudioFormatLinearPCM", kAudioFormatLinearPCM),
                           ("kAudioFormatAppleLossless", kAudioFormatAppleLossless), ("kAudioFormatAppleIMA4", kAudioFormatAppleIMA4),
                           ("kAudioFormatULaw", kAudioFormatULaw), ("kAudioFormatALaw", kAudioFormatALaw),
                           ("kAudioFormatMPEG4AAC_HE", kAudioFormatMPEG4AAC_HE), ("kAudioFormatFLAC", kAudioFormatFLAC), ("kAudioFormatOpus", kAudioFormatOpus)] {
            r.addConstant(name) { _ in .int(Int(id)) }
        }
        r.alias("AudioFormatID", to: "Int")
        r.type("AVAudioQuality", .audio, support: .full) { t in
            for (n, v) in [("min", AVAudioQuality.min), ("low", .low), ("medium", .medium), ("high", .high), ("max", .max)] {
                t.staticProperty(n) { _ in .native(.boxed(KBoxed("AVAudioQuality", v.rawValue))) }
            }
            t.property("rawValue") { c in
                if case .native(.boxed(let b)) = c.receiver, let raw = b.get(Int.self) { return .int(raw) }
                return .int(AVAudioQuality.medium.rawValue)
            }
        }
    }

    /// `[AVFormatIDKey: Int(kAudioFormatMPEG4AAC), …]` as AVFoundation takes it.
    @MainActor static func recorderSettings(_ v: KV?, _ interp: KInterpreter) -> [String: Any] {
        guard case .dict(let d)? = v else { return [:] }
        var out: [String: Any] = [:]
        for (k, value) in d {
            guard let key = k.asString else { continue }
            switch value {
            case .int(let i): out[key] = i
            case .double(let x): out[key] = x
            case .bool(let b): out[key] = b
            case .native(.boxed(let b)): if let raw = b.get(Int.self) { out[key] = raw }
            default: if let n = value.asDouble { out[key] = n }
            }
        }
        return out
    }

    // MARK: AVAudioSession, AVAudioApplication

    static func session(_ r: KRegistry) {
        let note = "Shelf owns the audio session: it plays (mixing with other audio) and records while a recorder records. These calls are accepted and change nothing."
        r.type("AVAudioSession", .audio, support: .partial, notes: note) { t in
            t.staticMethod("sharedInstance", "") { _ in .native(.object("AVAudioSession", KRef(KAudioSessionStandIn.shared))) }
            for sig in ["_:any", "_:any options:any", "_:any mode:any options:any?", "_:any mode:any policy:any options:any"] {
                t.method("setCategory", sig) { _ in .void }
            }
            for sig in ["_:bool", "_:bool options:any"] { t.method("setActive", sig) { _ in .void } }
            t.method("setMode", "_:any") { _ in .void }
            t.method("setPreferredSampleRate", "_:number") { _ in .void }
            t.method("setPreferredIOBufferDuration", "_:number") { _ in .void }
            t.method("overrideOutputAudioPort", "_:any") { _ in .void }
            t.property("category") { _ in .native(.implicit("playAndRecord", [])) }
            t.property("isInputAvailable") { c in .bool(KAudioRecordingSupport.microphoneExists(c.context)) }
            t.property("sampleRate") { _ in .double(44100) }
            t.property("isOtherAudioPlaying") { _ in .bool(false) }
            t.property("recordPermission") { c in recordPermission(c.context, session: true) }
            t.method("requestRecordPermission", "_:closure") { c in requestPermission(c, c.function(0)) }
        }
        for (type, cases) in [("AVAudioSession.Category", ["ambient", "soloAmbient", "playback", "record", "playAndRecord", "multiRoute"]),
                              ("AVAudioSession.Mode", ["default", "voiceChat", "videoChat", "gameChat", "videoRecording", "measurement", "moviePlayback", "spokenAudio", "voicePrompt"]),
                              ("AVAudioSession.CategoryOptions", ["mixWithOthers", "duckOthers", "allowBluetooth", "allowBluetoothHFP", "allowBluetoothA2DP", "allowAirPlay", "defaultToSpeaker", "interruptSpokenAudioAndMixWithOthers"]),
                              ("AVAudioSession.SetActiveOptions", ["notifyOthersOnDeactivation"]),
                              ("AVAudioSession.PortOverride", ["none", "speaker"]),
                              ("AVAudioSession.RecordPermission", ["undetermined", "denied", "granted"]),
                              ("AVAudioApplication.recordPermission", ["undetermined", "denied", "granted"])] {
            r.type(type, .audio, support: .full) { t in
                t.internal()
                for n in cases { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
            }
        }
        r.type("AVAudioApplication", .audio, support: .full,
               notes: "`AVAudioApplication.shared.recordPermission`, and `await AVAudioApplication.requestRecordPermission()`: the app's own answer, asked through Shelf first.") { t in
            t.staticProperty("shared") { _ in .native(.object("AVAudioApplication", KRef(KAudioSessionStandIn.shared))) }
            t.property("recordPermission") { c in recordPermission(c.context, session: false) }
            t.staticMethod("requestRecordPermission", "", async: true) { c in .suspension(c.context.capabilities.request(.microphone)) }
            t.staticMethod("requestRecordPermission", "completionHandler:closure") { c in requestPermission(c, c.function("completionHandler")) }
            t.property("isInputMuted") { _ in .bool(false) }
        }
    }

    @MainActor static func recordPermission(_ context: KilnContext, session: Bool) -> KV {
        switch context.capabilities.status(.microphone) {
        case .allowed: return .native(.implicit("granted", []))
        case .denied: return .native(.implicit("denied", []))
        case .notAsked: return .native(.implicit("undetermined", []))
        }
    }

    @MainActor static func requestPermission(_ c: KCall, _ f: KFunction?) -> KV {
        guard let f else { return .void }
        let interp = c.interp, context = c.context
        if interp.headless || context.isStub {
            interp.perform(f, [.bool(context.capabilities.gate.answerWithoutAsking(.microphone))])
            return .void
        }
        Task { @MainActor in
            let allowed = await context.capabilities.ask(.microphone)
            interp.perform(f, [.bool(allowed)])
        }
        return .void
    }
}

/// `AVAudioSession.sharedInstance()` and `AVAudioApplication.shared`, as the
/// app sees them: Shelf's session isn't the app's to change.
final class KAudioSessionStandIn {
    @MainActor static let shared = KAudioSessionStandIn()
}

@MainActor
enum KAudioRecordingSupport {
    /// The run's fake microphone: the host's, or a check's own.
    static func fake(_ context: KilnContext) -> KilnFakeMicrophone? {
        if let fake = context.provided(KilnFakeMicrophone.self) { return fake }
        return context.isStub ? stubMicrophone : nil
    }

    static let stubMicrophone = KilnFakeMicrophone()

    static func microphoneExists(_ context: KilnContext) -> Bool {
        if fake(context) != nil { return true }
        #if os(iOS)
        return AVAudioSession.sharedInstance().isInputAvailable
        #else
        return true
        #endif
    }
}

/// One `AVAudioRecorder` of the app's: the real one, or the fake
/// microphone's, behind the gate.
@MainActor
final class KRecorder {
    let url: URL
    let settings: [String: Any]
    private var real: AVAudioRecorder?
    private let fake: KilnFakeMicrophone?
    private weak var context: KilnContext?
    private weak var interp: KInterpreter?
    /// The app's `AVAudioRecorderDelegate`, called with the app's recorder.
    var delegateValue: KV?
    /// The app's value for this recorder, for the delegate's first argument.
    private var me: KV = .nilValue

    var isMeteringEnabled = false {
        didSet { real?.isMeteringEnabled = isMeteringEnabled }
    }

    private enum State { case idle, asking, recording, paused, stopped }
    private var state = State.idle
    /// The fake's clock: seconds recorded before the current stretch, and when it started.
    private var recorded: TimeInterval = 0
    private var stretchStart: Date?
    private var meterTime: TimeInterval = 0
    private var timer: Timer?
    private var finishDelegate: KRecorderDelegate?
    private var sessionHeld = false

    init(url: URL, settings: [String: Any], _ c: KCall) throws {
        self.url = url
        self.settings = settings
        context = c.context
        interp = c.interp
        fake = KAudioRecordingSupport.fake(c.context)
        if fake == nil {
            do { real = try AVAudioRecorder(url: url, settings: settings) } catch { throw FoundationBridges.thrown(error, c) }
            let forward = KRecorderDelegate()
            forward.finished = { [weak self] ok in self?.finished(ok) }
            real?.delegate = forward
            finishDelegate = forward
        }
        KAudioRun.of(c.context).track(self) { [weak self] in self?.stop() }
    }

    var isRecording: Bool { state == .recording }

    var currentTime: TimeInterval {
        if let real { return real.currentTime }
        return recorded + (stretchStart.map { Date.now.timeIntervalSince($0) } ?? 0)
    }

    var deviceCurrentTime: TimeInterval { real?.deviceCurrentTime ?? ProcessInfo.processInfo.systemUptime }

    func prepare() -> Bool {
        if fake != nil { return true }
        return real?.prepareToRecord() ?? false
    }

    /// Starts now if the microphone is allowed, asks first if nobody has;
    /// `false` when it's refused.
    func record(_ value: KV, _ c: KCall, duration: TimeInterval? = nil) -> Bool {
        me = value
        guard let context, !context.isTornDown, state != .recording else { return state == .recording }
        let capabilities = context.capabilities
        if c.interp.headless || context.isStub {
            guard capabilities.gate.answerWithoutAsking(.microphone) else { return false }
            start(duration)
            return true
        }
        switch capabilities.status(.microphone) {
        case .allowed:
            return start(duration)
        case .denied:
            return false
        case .notAsked:
            state = .asking
            Task { @MainActor [weak self] in
                let allowed = await capabilities.ask(.microphone)
                guard let self, self.state == .asking else { return }
                if allowed, self.start(duration) { return }
                self.state = .stopped
                self.tellDelegate(successfully: false)
            }
            return true
        }
    }

    @discardableResult
    private func start(_ duration: TimeInterval?) -> Bool {
        guard let context else { return false }
        if let real {
            if !sessionHeld { KAudioRun.of(context).willRecord(); sessionHeld = true }
            let ok = duration.map { real.record(forDuration: $0) } ?? real.record()
            if !ok { releaseSession() }
            state = ok ? .recording : .idle
            return ok
        }
        state = .recording
        stretchStart = .now
        if let duration {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: max(0, duration - recorded), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
        }
        return true
    }

    func pause() {
        guard state == .recording else { return }
        real?.pause()
        if let s = stretchStart { recorded += Date.now.timeIntervalSince(s) }
        stretchStart = nil
        state = .paused
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        switch state {
        case .asking:
            state = .stopped
        case .recording, .paused:
            if let real {
                real.stop()        // the delegate's finish arrives through KRecorderDelegate
                releaseSession()
                state = .stopped
            } else {
                if let s = stretchStart { recorded += Date.now.timeIntervalSince(s) }
                stretchStart = nil
                state = .stopped
                writeFakeRecording()
                tellDelegate(successfully: true)
            }
        default:
            break
        }
    }

    func delete() -> Bool {
        if isRecording { return false }
        if let real { return real.deleteRecording() }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    func updateMeters() {
        real?.updateMeters()
        meterTime = currentTime
    }

    func averagePower() -> Float {
        if let real { return isMeteringEnabled ? real.averagePower(forChannel: 0) : -160 }
        guard isMeteringEnabled, isRecording, let fake else { return -160 }
        return fake.averagePower(at: meterTime)
    }

    func peakPower() -> Float {
        if let real { return isMeteringEnabled ? real.peakPower(forChannel: 0) : -160 }
        guard isMeteringEnabled, isRecording, let fake else { return -160 }
        return fake.peakPower(at: meterTime)
    }

    private func releaseSession() {
        guard sessionHeld, let context else { return }
        sessionHeld = false
        KAudioRun.of(context).didStopRecording()
    }

    private func finished(_ ok: Bool) {
        releaseSession()
        state = .stopped
        tellDelegate(successfully: ok)
    }

    private func tellDelegate(successfully ok: Bool) {
        guard let delegateValue, let interp, var app = KAppValue(delegateValue, interp),
              app.implements("audioRecorderDidFinishRecording", labels: [nil, "successfully"]) else { return }
        _ = app.callReporting("audioRecorderDidFinishRecording", [me, .bool(ok)], labels: [nil, "successfully"], fallback: .nilValue)
    }

    /// The fake microphone's recording, in the format the app asked for when
    /// AVFoundation can write it, else a WAV.
    private func writeFakeRecording() {
        guard let fake else { return }
        let seconds = max(0.2, recorded)
        let rate = (settings[AVSampleRateKey] as? Double) ?? (settings[AVSampleRateKey] as? Int).map(Double.init) ?? 44100
        let channels = (settings[AVNumberOfChannelsKey] as? Int) ?? 1
        if let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(max(1, channels))),
           let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * seconds)) {
            buffer.frameLength = buffer.frameCapacity
            for ch in 0..<Int(format.channelCount) {
                guard let samples = buffer.floatChannelData?[ch] else { continue }
                for i in 0..<Int(buffer.frameLength) { samples[i] = Float(sin(2 * .pi * fake.frequency * Double(i) / rate) * 0.2) }
            }
            do {
                try? FileManager.default.removeItem(at: url)
                let file = try AVAudioFile(forWriting: url, settings: settings.isEmpty ? format.settings : settings)
                try file.write(from: buffer)
                return
            } catch {}
        }
        try? fake.recording(seconds: seconds).write(to: url)
    }
}

/// The real recorder's delegate: its finish reaches the app's delegate
/// with the app's own recorder value.
final class KRecorderDelegate: NSObject, AVAudioRecorderDelegate {
    var finished: (@MainActor (Bool) -> Void)?
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let finished = self.finished
        Task { @MainActor in finished?(flag) }
    }
}
