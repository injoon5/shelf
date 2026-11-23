//
//  AudioBridgeTests.swift
//  KilnTests
//
//  PLAN.md §3.5: AVAudioPlayer from Data and from the app's folder, its
//  delegate's finish callback, AVPlayer and VideoPlayer, system sounds,
//  speech, the host's audio-session hook, and teardown.
//

import XCTest
import SwiftUI
@testable import Kiln

@MainActor
final class AudioBridgeTests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() async throws {
        await MainActor.run { for f in folders { try? FileManager.default.removeItem(at: f) } }
    }

    /// A real (not stub) context with its own folder.
    private func context(_ slug: String = "audio") -> KilnContext {
        let folder = FileManager.default.temporaryDirectory.appending(path: "kiln-audio-\(UUID().uuidString)")
        folders.append(folder)
        return KilnContext(slug: slug, name: "Audio", defaults: KilnMemoryDefaults(), files: KilnFiles(root: folder))
    }

    /// Makes a quiet 8-bit WAV, in the app's own code.
    static let tone = """
    func tone(_ frequency: Double, seconds: Double) -> Data {
        let rate = 8000
        let count = Int(Double(rate) * seconds)
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255), UInt8((v >> 16) & 255), UInt8((v >> 24) & 255)] }
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255)] }
        var bytes: [UInt8] = Array("RIFF".utf8) + le32(36 + count) + Array("WAVE".utf8)
        bytes += Array("fmt ".utf8) + le32(16) + le16(1) + le16(1) + le32(rate) + le32(rate) + le16(1) + le16(8)
        bytes += Array("data".utf8) + le32(count)
        bytes += (0..<count).map { i in UInt8(128 + Int(sin(2 * Double.pi * frequency * Double(i) / Double(rate)) * 20)) }
        return Data(bytes)
    }
    """

    static let app = """
    import SwiftUI
    import AVFoundation
    import AVKit
    import AudioToolbox

    final class Sounds: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
        var finished = 0
        var spoken = 0
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            finished += 1
            print("finished \\(flag)")
        }
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            spoken += 1
            print("spoke \\(utterance.speechString)")
        }
    }

    \(tone)

    struct ContentView: View {
        @State private var player: AVAudioPlayer?
        @State private var sounds = Sounds()
        @State private var synth = AVSpeechSynthesizer()
        @State private var video = AVPlayer(url: URL(string: "https://example.com/clip.m3u8")!)
        @State private var status = "idle"

        var body: some View {
            VStack {
                Text(status)
                Button("Beep") { beep() }
                Button("Click") { AudioServicesPlaySystemSound(1104) }
                Button("Say") { say("Hello") }
                VideoPlayer(player: video)
                    .frame(height: 200)
                VideoPlayer(player: video) {
                    Text("Overlay")
                }
            }
        }

        func beep() {
            do {
                let p = try AVAudioPlayer(data: tone(440, seconds: 0.1))
                p.volume = 0
                p.numberOfLoops = 0
                p.enableRate = true
                p.rate = 1.5
                p.delegate = sounds
                p.prepareToPlay()
                status = p.play() ? "playing \\(p.duration > 0)" : "failed"
                player = p
            } catch {
                status = "error"
            }
        }

        func say(_ text: String) {
            let u = AVSpeechUtterance(string: text)
            u.rate = AVSpeechUtteranceDefaultSpeechRate
            u.pitchMultiplier = 1.2
            u.volume = 0
            u.voice = AVSpeechSynthesisVoice(language: "en-US")
            synth.delegate = sounds
            synth.speak(u)
        }
    }
    """

    func testTheAudioAppChecksValidatesAndShows() {
        XCTAssertEqual(BridgeTest.problems(Self.app), [])
    }

    func testAPlayerFromDataPlaysAndItsDelegateHearsTheEnd() async throws {
        let ctx = context()
        let c = try KilnEngine.compile(Self.app + """

        var keep: [AVAudioPlayer] = []
        let delegate = Sounds()
        func main() {
            let p = try! AVAudioPlayer(data: tone(440, seconds: 0.15))
            p.volume = 0
            p.delegate = delegate
            keep.append(p)
            print(p.play(), p.isPlaying, p.duration > 0.1, p.numberOfLoops)
        }
        """, headless: false, context: ctx)
        let main = try XCTUnwrap(c.interp.functions["main"]?.first)
        c.interp.perform(KFunction(.user(main, c.interp.globalEnv, nil)))
        XCTAssertEqual(c.interp.errors, [])
        XCTAssertTrue(c.interp.console.hasPrefix("true true true 0\n"), c.interp.console)
        let deadline = Date().addingTimeInterval(3)
        while !c.interp.console.contains("finished true"), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(c.interp.console.contains("finished true"), c.interp.console)
        ctx.tearDown()
    }

    func testAFileInTheAppsFolderPlaysAndOneOutsideIsAnError() throws {
        let ctx = context()
        let c = try KilnEngine.compile(Self.app + """

        func main() {
            let url = URL.documentsDirectory.appending(path: "beep.wav")
            try! tone(300, seconds: 0.05).write(to: url)
            let p = try! AVAudioPlayer(contentsOf: url)
            print(p.duration > 0, p.url?.lastPathComponent ?? "")
            do { _ = try AVAudioPlayer(contentsOf: URL.documentsDirectory.appending(path: "missing.wav")) } catch { print("caught") }
            _ = try! AVAudioPlayer(contentsOf: URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff"))
        }
        """, headless: false, context: ctx)
        let main = try XCTUnwrap(c.interp.functions["main"]?.first)
        c.interp.perform(KFunction(.user(main, c.interp.globalEnv, nil)))
        XCTAssertTrue(c.interp.console.hasPrefix("true beep.wav\ncaught\n"), c.interp.console)
        XCTAssertTrue(c.interp.errors.contains { $0.contains("outside the app's folder") }, "\(c.interp.errors)")
        ctx.tearDown()
    }

    /// The host owns the session: told before the first sound, and after
    /// everything the run made has stopped when its screen closes.
    func testTheHostsSessionHookAndTeardown() throws {
        let ctx = context()
        var events: [String] = []
        var player: AnyObject?
        ctx.provide(KilnAudioSession(willPlay: { events.append("willPlay") }, didStop: {
            events.append("didStop playing=\((player as? NSObject)?.value(forKey: "playing") as? Bool ?? false)")
        }))
        let c = try KilnEngine.compile(Self.app + """

        var keep: [AVAudioPlayer] = []
        func make() {
            let p = try! AVAudioPlayer(data: tone(440, seconds: 2))
            p.volume = 0
            p.numberOfLoops = -1
            keep.append(p)
        }
        func start() { _ = keep[0].play(); _ = keep[0].play() }
        """, headless: false, context: ctx)
        c.interp.perform(KFunction(.user(try XCTUnwrap(c.interp.functions["make"]?.first), c.interp.globalEnv, nil)))
        XCTAssertEqual(events, [], "making a player isn't playing")
        c.interp.perform(KFunction(.user(try XCTUnwrap(c.interp.functions["start"]?.first), c.interp.globalEnv, nil)))
        XCTAssertEqual(events, ["willPlay"])
        if case .array(let items)? = c.interp.globalEnv.lookup("keep")?.value, case .native(.object(_, let ref))? = items.first { player = ref.value }
        XCTAssertEqual((player as? NSObject)?.value(forKey: "playing") as? Bool, true)
        ctx.tearDown()
        XCTAssertEqual(events, ["willPlay", "didStop playing=false"])
    }

    /// A check makes no sound and never tells the host.
    func testACheckNeverPlays() throws {
        let ctx = KilnContext.stub()
        var events: [String] = []
        ctx.provide(KilnAudioSession(willPlay: { events.append("willPlay") }, didStop: { events.append("didStop") }))
        let v = Kiln.validate(Self.app, context: ctx)
        XCTAssertEqual(v.errors, [])
        ctx.tearDown()
        XCTAssertEqual(events, [])
    }

    func testSpeechUtterancesAndVoices() throws {
        let c = try KilnEngine.compile(Self.app + """

        func main() {
            let u = AVSpeechUtterance(string: "Hi there")
            u.rate = 0.4
            u.pitchMultiplier = 1.5
            u.preUtteranceDelay = 0.25
            let voice = AVSpeechSynthesisVoice(language: "en-US")
            u.voice = voice
            print(u.speechString, u.rate, u.pitchMultiplier, u.preUtteranceDelay, u.voice?.language ?? "none")
            let slowest = AVSpeechUtteranceMinimumSpeechRate
            print(AVSpeechSynthesisVoice.speechVoices().isEmpty, slowest < AVSpeechUtteranceMaximumSpeechRate)
            let synth = AVSpeechSynthesizer()
            print(synth.isSpeaking, synth.isPaused, synth.stopSpeaking(at: .immediate))
        }
        """, headless: true, context: .stub())
        c.interp.perform(KFunction(.user(try XCTUnwrap(c.interp.functions["main"]?.first), c.interp.globalEnv, nil)))
        XCTAssertEqual(c.interp.errors, [])
        XCTAssertEqual(c.interp.console, "Hi there 0.4000000059604645 1.5 0.25 en-US\nfalse true\nfalse false false\n")
    }

    /// The delegate's Swift names (`didFinish`) reach their Objective-C
    /// selectors (`didFinishSpeechUtterance`).
    func testTheSpeechDelegateHearsTheEnd() async throws {
        let ctx = context()
        let c = try KilnEngine.compile(Self.app + """

        let synth = AVSpeechSynthesizer()
        let delegate = Sounds()
        func main() {
            let u = AVSpeechUtterance(string: "Hi")
            u.volume = 0
            u.rate = AVSpeechUtteranceMaximumSpeechRate
            synth.delegate = delegate
            synth.speak(u)
        }
        """, headless: false, context: ctx)
        c.interp.perform(KFunction(.user(try XCTUnwrap(c.interp.functions["main"]?.first), c.interp.globalEnv, nil)))
        XCTAssertEqual(c.interp.errors, [])
        let deadline = Date().addingTimeInterval(10)
        while !c.interp.console.contains("spoke Hi"), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(c.interp.console, "spoke Hi\n")
        ctx.tearDown()
    }

    func testCMTimeAndAVPlayer() throws {
        let c = try KilnEngine.compile(Self.app + """

        func main() {
            let t = CMTime(seconds: 2.5, preferredTimescale: 600)
            print(t.seconds, CMTimeGetSeconds(t), CMTime.zero.seconds)
            let p = AVPlayer(url: URL(string: "https://example.com/a.mp3")!)
            p.volume = 0.5
            p.isMuted = true
            p.seek(to: t)
            print(p.volume, p.isMuted, p.timeControlStatus == .paused, p.rate)
        }
        """, headless: true, context: .stub())
        c.interp.perform(KFunction(.user(try XCTUnwrap(c.interp.functions["main"]?.first), c.interp.globalEnv, nil)))
        XCTAssertEqual(c.interp.errors, [])
        XCTAssertEqual(c.interp.console, "2.5 2.5 0.0\n0.5 true true 0.0\n")
    }

    func testWrongCallsReadWell() {
        let errors = Kiln.check(BridgeTest.app(#"Text("x").onAppear { let p = try? AVAudioPlayer(url: URL(string: "a")!); _ = p }"#)).errors
        XCTAssertTrue(errors.contains { "\($0)".contains("AVAudioPlayer(contentsOf:fileTypeHint:)") }, "\(errors)")
    }
}
