// Name: Tone Lab
// Icon: speaker.wave.2.fill
// Tint: orange
// Covers: Audio

import SwiftUI
import AVFoundation
import AVKit
import AudioToolbox

/// Hears when a tone ends and when speech finishes.
final class Listener: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    var onFinish: (Bool) -> Void = { _ in }
    var onSpoken: (String) -> Void = { _ in }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish(flag)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onSpoken(utterance.speechString)
    }
}

/// An 8-bit mono WAV of a sine tone.
func tone(_ frequency: Double, seconds: Double) -> Data {
    let rate = 8000
    let count = Int(Double(rate) * seconds)
    func le32(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255), UInt8((v >> 16) & 255), UInt8((v >> 24) & 255)] }
    func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255)] }
    var bytes: [UInt8] = Array("RIFF".utf8) + le32(36 + count) + Array("WAVE".utf8)
    bytes += Array("fmt ".utf8) + le32(16) + le16(1) + le16(1) + le32(rate) + le32(rate) + le16(1) + le16(8)
    bytes += Array("data".utf8) + le32(count)
    bytes += (0..<count).map { i in
        UInt8(128 + Int(sin(2 * Double.pi * frequency * Double(i) / Double(rate)) * 90))
    }
    return Data(bytes)
}

struct ContentView: View {
    @State private var player: AVAudioPlayer?
    @State private var listener = Listener()
    @State private var synth = AVSpeechSynthesizer()
    @State private var stream = AVPlayer(url: URL(string: "https://example.com/stream.m3u8")!)
    @State private var frequency = 440.0
    @State private var volume = 0.8
    @State private var fast = false
    @State private var loops = 0
    @State private var status = "Ready"
    @State private var phrase = "Hello from Shelf"
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var voiceID = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Tone") {
                    LabeledContent("Pitch", value: "\(Int(frequency)) Hz")
                    Slider(value: $frequency, in: 220...880, step: 20)
                    Slider(value: $volume, in: 0...1) { Text("Volume") }
                        .onChange(of: volume) { player?.volume = Float(volume) }
                    Toggle("Faster", isOn: $fast)
                    Stepper("Repeats: \(loops)", value: $loops, in: 0...5)
                    Button("Play Tone", systemImage: "play.fill") { play(tone(frequency, seconds: 0.4)) }
                    Button("Save and Play File", systemImage: "doc") { playSaved() }
                    Button("Stop", systemImage: "stop.fill") {
                        player?.stop()
                        player?.currentTime = 0
                        status = "Stopped"
                    }
                    Text(status).foregroundStyle(.secondary)
                }
                Section("System Sounds") {
                    Button("Click") { AudioServicesPlaySystemSound(1104) }
                    Button("Vibrate") { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
                }
                Section("Speech") {
                    TextField("Phrase", text: $phrase)
                    Picker("Voice", selection: $voiceID) {
                        Text("Default").tag("")
                        ForEach(voices.prefix(8), id: \.identifier) { voice in
                            Text(voice.name).tag(voice.identifier)
                        }
                    }
                    Button("Speak", systemImage: "waveform") { speak() }
                    Button("Stop Speaking") { synth.stopSpeaking(at: .immediate) }
                }
                Section("Stream") {
                    VideoPlayer(player: stream)
                        .frame(height: 180)
                    Button("Play Stream") { stream.play() }
                }
            }
            .navigationTitle("Tone Lab")
            .onAppear {
                voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
                listener.onFinish = { ok in status = ok ? "Finished" : "Interrupted" }
                listener.onSpoken = { text in status = "Said \(text)" }
                synth.delegate = listener
            }
        }
    }

    func play(_ data: Data) {
        do {
            let p = try AVAudioPlayer(data: data)
            configure(p)
        } catch {
            status = "Couldn't play: \(error.localizedDescription)"
        }
    }

    func playSaved() {
        let url = URL.documentsDirectory.appending(path: "tone.wav")
        do {
            try tone(frequency, seconds: 0.3).write(to: url)
            configure(try AVAudioPlayer(contentsOf: url))
        } catch {
            status = "Couldn't save the tone."
        }
    }

    func configure(_ p: AVAudioPlayer) {
        p.delegate = listener
        p.volume = Float(volume)
        p.numberOfLoops = loops
        p.enableRate = true
        p.rate = fast ? 2 : 1
        p.prepareToPlay()
        if p.play() {
            status = String(format: "Playing %.1f s", p.duration)
        }
        player = p
    }

    func speak() {
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.1
        utterance.voice = voiceID.isEmpty ? AVSpeechSynthesisVoice(language: "en-US") : AVSpeechSynthesisVoice(identifier: voiceID)
        synth.speak(utterance)
    }
}
