//
//  Audio.swift
//  Bridges: playing sounds (PLAN.md §3.5)
//
//  - `AVAudioPlayer(data:)` and `AVAudioPlayer(contentsOf:)`, for `Data` the
//    app made or a file in its own folder, with its delegate's finish
//    callback (`KDelegates`).
//  - `AVPlayer(url:)` for streams and files, and AVKit's `VideoPlayer`.
//  - `AudioServicesPlaySystemSound`.
//  - `AVSpeechSynthesizer` and its voices (Speech.swift).
//
//  Kiln never configures `AVAudioSession`: the host owns it
//  (`KilnAudioSession`). Everything a run makes is stopped when its screen
//  closes (`KAudioRun`). A check (`validate`, a stub context) makes no
//  sound: `play()` answers as if it played, and streams aren't opened.
//
//  Out: real-time render callbacks (`AVAudioSourceNode`), on the won't-do list.
//

import SwiftUI
import AVFoundation
#if canImport(AVKit)
import AVKit
#endif
#if canImport(AudioToolbox)
import AudioToolbox
#endif

@objc(KilnBridges_Audio)
final class AudioBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        players(r)
        streams(r)
        systemSounds(r)
        speech(r)
    }

    /// Whether this run makes real sound: not in a check.
    @MainActor static func isLive(_ c: KCall) -> Bool { !(c.interp.headless || c.context.isStub) }

    // MARK: AVAudioPlayer

    static func players(_ r: KRegistry) {
        r.type("AVAudioPlayer", .audio, support: .full) { t in
            @MainActor func make(_ c: KCall, _ build: () throws -> AVAudioPlayer) throws -> KV {
                let player: AVAudioPlayer
                do { player = try build() } catch { throw FoundationBridges.thrown(error, c) }
                KAudioRun.of(c.context).track(player) { player.stop() }
                return .native(.object("AVAudioPlayer", KRef(player)))
            }
            @MainActor func hint(_ c: KCall) -> String? {
                c.string("fileTypeHint")
            }
            t.initializer("contentsOf:URL fileTypeHint:string?") { c in
                let url = try FoundationBridges.file(c, "contentsOf")
                return try make(c) { try AVAudioPlayer(contentsOf: url, fileTypeHint: hint(c)) }
            }
            t.initializer("data:any fileTypeHint:string?") { c in
                guard let data = KBuiltins.dataValue(c["data"]) else { throw c.fail("data should be Data") }
                return try make(c) { try AVAudioPlayer(data: data, fileTypeHint: hint(c)) }
            }

            @MainActor func player(_ c: KCall) -> AVAudioPlayer? { c.object(AVAudioPlayer.self) }
            t.method("prepareToPlay", "") { c in .bool(player(c)?.prepareToPlay() ?? false) }
            t.method("play", "") { c in
                guard let p = player(c) else { return .bool(false) }
                guard isLive(c) else { return .bool(true) }
                KAudioRun.of(c.context).willPlay()
                return .bool(p.play())
            }
            t.method("play", "atTime:number") { c in
                guard let p = player(c) else { return .bool(false) }
                guard isLive(c) else { return .bool(true) }
                KAudioRun.of(c.context).willPlay()
                return .bool(p.play(atTime: c.double("atTime") ?? p.deviceCurrentTime))
            }
            t.method("pause", "") { c in player(c)?.pause(); return .void }
            t.method("stop", "") { c in player(c)?.stop(); return .void }
            t.method("setVolume", "_:number fadeDuration:number") { c in
                player(c)?.setVolume(Float(c.double(0) ?? 1), fadeDuration: c.double("fadeDuration") ?? 0)
                return .void
            }

            t.property("isPlaying") { c in .bool(player(c)?.isPlaying ?? false) }
            t.property("duration") { c in .double(player(c)?.duration ?? 0) }
            t.property("deviceCurrentTime") { c in .double(player(c)?.deviceCurrentTime ?? 0) }
            t.property("numberOfChannels") { c in .int(player(c)?.numberOfChannels ?? 0) }
            t.property("url") { c in player(c)?.url.map { .native(.url($0)) } ?? .nilValue }
            t.property("data") { c in player(c)?.data.map { KBuiltins.data($0) } ?? .nilValue }
            t.property("currentTime", { c in .double(player(c)?.currentTime ?? 0) },
                       set: { c in player(c)?.currentTime = c.double(0) ?? 0 })
            t.property("volume", { c in .double(Double(player(c)?.volume ?? 1)) },
                       set: { c in player(c)?.volume = Float(c.double(0) ?? 1) })
            t.property("pan", { c in .double(Double(player(c)?.pan ?? 0)) },
                       set: { c in player(c)?.pan = Float(c.double(0) ?? 0) })
            t.property("rate", { c in .double(Double(player(c)?.rate ?? 1)) },
                       set: { c in player(c)?.rate = Float(c.double(0) ?? 1) })
            t.property("enableRate", { c in .bool(player(c)?.enableRate ?? false) },
                       set: { c in player(c)?.enableRate = c.bool(0, default: false) })
            t.property("numberOfLoops", { c in .int(player(c)?.numberOfLoops ?? 0) },
                       set: { c in player(c)?.numberOfLoops = c.int(0) ?? 0 })
            t.property("isMeteringEnabled", { c in .bool(player(c)?.isMeteringEnabled ?? false) },
                       set: { c in player(c)?.isMeteringEnabled = c.bool(0, default: false) })
            t.method("updateMeters", "") { c in player(c)?.updateMeters(); return .void }
            t.method("averagePower", "forChannel:number") { c in .double(Double(player(c)?.averagePower(forChannel: c.int("forChannel") ?? 0) ?? -160)) }
            t.method("peakPower", "forChannel:number") { c in .double(Double(player(c)?.peakPower(forChannel: c.int("forChannel") ?? 0) ?? -160)) }
            t.property("delegate", { _ in .nilValue }, set: { c in
                guard let p = player(c) else { return }
                if c.args[0].isNil { p.delegate = nil; KDelegates.retain(nil, by: p); return }
                guard let proxy = KDelegates.proxy(for: c.args[0], c.interp) else {
                    throw c.fail("the delegate should be a class that adopts AVAudioPlayerDelegate")
                }
                p.delegate = unsafeBitCast(proxy, to: AVAudioPlayerDelegate.self)
                KDelegates.retain(proxy, by: p)
            })
        }
        r.nativeClass(AVAudioPlayer.self, "AVAudioPlayer")
        r.delegateProtocol("AVAudioPlayerDelegate", .audio,
                           requirements: ["audioPlayerDidFinishPlaying(_:successfully:)?", "audioPlayerDecodeErrorDidOccur(_:error:)?"])
    }

    // MARK: AVPlayer, VideoPlayer, CMTime

    static func streams(_ r: KRegistry) {
        /// A URL to stream: a web address as written, a file URL only inside the app's folder.
        @MainActor func streamURL(_ c: KCall, _ ref: KArgRef) throws -> URL {
            guard let url = c.url(ref) else { throw c.fail("needs a URL") }
            if url.isFileURL { return try FoundationBridges.file(c, ref) }
            return url
        }
        @MainActor func item(_ c: KCall, _ url: URL) -> AVPlayerItem? {
            // A check never opens a stream.
            isLive(c) ? AVPlayerItem(url: url) : nil
        }
        @MainActor func wrap(_ c: KCall, _ player: AVPlayer) -> KV {
            KAudioRun.of(c.context).track(player) {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
            return .native(.object("AVPlayer", KRef(player)))
        }

        r.type("AVPlayer", .audio, support: .full) { t in
            t.initializer("url:URL") { c in wrap(c, AVPlayer(playerItem: item(c, try streamURL(c, "url")))) }
            t.initializer("playerItem:any") { c in
                let i: AVPlayerItem? = { if case .native(.object(_, let ref))? = c["playerItem"] { return ref.value as? AVPlayerItem }; return nil }()
                return wrap(c, AVPlayer(playerItem: i))
            }
            t.initializer("") { c in wrap(c, AVPlayer()) }

            @MainActor func player(_ c: KCall) -> AVPlayer? { c.object(AVPlayer.self) }
            t.method("play", "") { c in
                guard isLive(c), let p = player(c) else { return .void }
                KAudioRun.of(c.context).willPlay()
                p.play()
                return .void
            }
            t.method("pause", "") { c in player(c)?.pause(); return .void }
            t.method("seek", "to:any") { c in
                if let time = cmTime(c["to"]) { player(c)?.seek(to: time) }
                return .void
            }
            t.method("currentTime", "") { c in boxed(player(c)?.currentTime() ?? .zero) }
            t.method("replaceCurrentItem", "with:any") { c in
                if case .native(.object(_, let ref))? = c["with"] { player(c)?.replaceCurrentItem(with: ref.value as? AVPlayerItem) }
                else { player(c)?.replaceCurrentItem(with: nil) }
                return .void
            }
            t.property("currentItem") { c in player(c)?.currentItem.map { .native(.object("AVPlayerItem", KRef($0))) } ?? .nilValue }
            t.property("rate", { c in .double(Double(player(c)?.rate ?? 0)) }, set: { c in
                guard let p = player(c) else { return }
                let rate = Float(c.double(0) ?? 0)
                if rate != 0, isLive(c) { KAudioRun.of(c.context).willPlay(); p.rate = rate } else if rate == 0 { p.rate = 0 }
            })
            t.property("volume", { c in .double(Double(player(c)?.volume ?? 1)) },
                       set: { c in player(c)?.volume = Float(c.double(0) ?? 1) })
            t.property("isMuted", { c in .bool(player(c)?.isMuted ?? false) },
                       set: { c in player(c)?.isMuted = c.bool(0, default: false) })
            t.property("timeControlStatus") { c in
                switch player(c)?.timeControlStatus {
                case .playing?: return .native(.implicit("playing", []))
                case .waitingToPlayAtSpecifiedRate?: return .native(.implicit("waitingToPlayAtSpecifiedRate", []))
                default: return .native(.implicit("paused", []))
                }
            }
            t.property("actionAtItemEnd", { c in
                switch player(c)?.actionAtItemEnd {
                case .pause?: return .native(.implicit("pause", []))
                case .advance?: return .native(.implicit("advance", []))
                default: return .native(.implicit("none", []))
                }
            }, set: { c in
                switch c.symbol(0) {
                case "pause": player(c)?.actionAtItemEnd = .pause
                case "advance": player(c)?.actionAtItemEnd = .advance
                default: player(c)?.actionAtItemEnd = .none
                }
            })
        }

        r.type("AVPlayerItem", .audio, support: .full) { t in
            t.initializer("url:URL") { c in
                let url = try streamURL(c, "url")
                // A check never opens a stream: an item for nothing.
                let item = isLive(c) ? AVPlayerItem(url: url) : AVPlayerItem(asset: AVMutableComposition())
                return .native(.object("AVPlayerItem", KRef(item)))
            }
            @MainActor func item(_ c: KCall) -> AVPlayerItem? { c.object(AVPlayerItem.self) }
            t.property("duration") { c in boxed(item(c)?.duration ?? .zero) }
            t.method("currentTime", "") { c in boxed(item(c)?.currentTime() ?? .zero) }
            t.property("status") { c in
                switch item(c)?.status {
                case .readyToPlay?: return .native(.implicit("readyToPlay", []))
                case .failed?: return .native(.implicit("failed", []))
                default: return .native(.implicit("unknown", []))
                }
            }
        }
        r.nativeClass(AVPlayerItem.self, "AVPlayerItem")
        r.nativeClass(AVPlayer.self, "AVPlayer")

        r.type("CMTime", .audio, support: .full) { t in
            t.initializer("seconds:number preferredTimescale:number") { c in
                boxed(CMTime(seconds: c.double("seconds") ?? 0, preferredTimescale: CMTimeScale(c.int("preferredTimescale") ?? 600)))
            }
            t.initializer("value:number timescale:number") { c in
                boxed(CMTime(value: CMTimeValue(c.int("value") ?? 0), timescale: CMTimeScale(c.int("timescale") ?? 1)))
            }
            t.staticProperty("zero") { _ in boxed(.zero) }
            t.staticProperty("indefinite") { _ in boxed(.indefinite) }
            t.property("seconds") { c in .double(cmTime(c.receiver)?.seconds ?? 0) }
            t.property("isValid") { c in .bool(cmTime(c.receiver)?.isValid ?? false) }
            t.property("isIndefinite") { c in .bool(cmTime(c.receiver)?.isIndefinite ?? false) }
        }
        r.function("CMTimeGetSeconds", .audio, "_:any", owner: "CoreMedia") { c in .double(cmTime(c[0])?.seconds ?? 0) }
        r.function("CMTimeMakeWithSeconds", .audio, "_:number preferredTimescale:number", owner: "CoreMedia") { c in
            boxed(CMTime(seconds: c.double(0) ?? 0, preferredTimescale: CMTimeScale(c.int("preferredTimescale") ?? 600)))
        }

        r.view("VideoPlayer", .audio, notes: nil) { v in
            v.form("player:any") { c in KVideoPlayer(player: avPlayer(c["player"]), overlay: nil) }
            v.form("player:any videoOverlay:content") { c in KVideoPlayer(player: avPlayer(c["player"]), overlay: c.content("videoOverlay")) }
        }
    }

    static func boxed(_ t: CMTime) -> KV { .native(.boxed(KBoxed("CMTime", t))) }

    static func cmTime(_ v: KV?) -> CMTime? {
        switch v {
        case .native(.boxed(let b))?: return b.get(CMTime.self)
        case .int(let i)?: return CMTime(seconds: Double(i), preferredTimescale: 600)
        case .double(let d)?: return CMTime(seconds: d, preferredTimescale: 600)
        default: return nil
        }
    }

    static func avPlayer(_ v: KV?) -> AVPlayer? {
        if case .native(.object(_, let ref))? = v { return ref.value as? AVPlayer }
        return nil
    }

    // MARK: System sounds

    static func systemSounds(_ r: KRegistry) {
        r.alias("SystemSoundID", to: "Int")
        for name in ["AudioServicesPlaySystemSound", "AudioServicesPlayAlertSound"] {
            r.function(name, .audio, "_:number", owner: "AudioToolbox") { c in
                guard isLive(c) else { return .void }
                #if canImport(AudioToolbox)
                let id = SystemSoundID(truncatingIfNeeded: c.int(0) ?? 0)
                KAudioRun.of(c.context).willPlay()
                if name == "AudioServicesPlaySystemSound" { AudioServicesPlaySystemSound(id) } else { AudioServicesPlayAlertSound(id) }
                #endif
                return .void
            }
        }
        r.addConstant("kSystemSoundID_Vibrate") { _ in .int(4095) }
    }
}

// MARK: - VideoPlayer

/// AVKit's `VideoPlayer` with the app's player (and overlay).
struct KVideoPlayer: View {
    let player: AVPlayer?
    let overlay: AnyView?

    #if os(macOS)
    /// SwiftUI's VideoPlayer subclasses `AVPlayerView`, which a process that
    /// never loaded AVKit (a test runner) can't find by name.
    static let loadAVKit: Void = { _ = dlopen("/System/Library/Frameworks/AVKit.framework/AVKit", RTLD_NOW) }()
    #endif

    var body: some View {
        #if canImport(AVKit) && !os(watchOS)
        #if os(macOS)
        let _ = Self.loadAVKit
        #endif
        if let overlay {
            VideoPlayer(player: player) { overlay }
        } else {
            VideoPlayer(player: player)
        }
        #else
        Color.black
        #endif
    }
}
