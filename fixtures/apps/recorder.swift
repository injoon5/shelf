// Name: Voice Notes
// Icon: mic.fill
// Tint: red
// Covers: Audio

import SwiftUI
import AVFoundation

// Recording with AVAudioRecorder into the app's own folder, with a level
// meter from averagePower(forChannel:), and playing the recordings back.
// Shelf asks for the microphone; recording stops when the app closes.

final class RecorderDelegate: NSObject, AVAudioRecorderDelegate {
    var onFinish: (Bool) -> Void = { _ in }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        onFinish(flag)
    }
}

struct ContentView: View {
    @State private var recorder: AVAudioRecorder?
    @State private var player: AVAudioPlayer?
    @State private var delegate = RecorderDelegate()
    @State private var level: Float = -160
    @State private var elapsed: TimeInterval = 0
    @State private var memos: [URL] = []
    @State private var note = ""

    let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var isRecording: Bool { recorder?.isRecording ?? false }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Gauge(value: Double(max(level, -60)), in: -60...0) {
                            Text("Level")
                        }
                        .gaugeStyle(.accessoryLinearCapacity)
                        Text(elapsed, format: .number.precision(.fractionLength(1)))
                            .font(.largeTitle.monospacedDigit())
                        Button(isRecording ? "Stop" : "Record", systemImage: isRecording ? "stop.circle.fill" : "record.circle") {
                            Task { await toggle() }
                        }
                        .font(.title2)
                        .tint(.red)
                        if !note.isEmpty { Text(note).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity)
                }
                Section("Recordings") {
                    ForEach(memos, id: \.self) { url in
                        Button(url.deletingPathExtension().lastPathComponent, systemImage: "play.circle") { play(url) }
                    }
                    .onDelete { offsets in
                        for i in offsets { try? FileManager.default.removeItem(at: memos[i]) }
                        reload()
                    }
                }
            }
            .navigationTitle("Voice Notes")
            .onAppear(perform: reload)
            .onReceive(tick) { _ in
                guard let recorder, recorder.isRecording else { return }
                recorder.updateMeters()
                level = recorder.averagePower(forChannel: 0)
                elapsed = recorder.currentTime
            }
        }
    }

    func toggle() async {
        if let recorder, recorder.isRecording {
            recorder.stop()
            level = -160
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            note = "The microphone is off for this app."
            return
        }
        let url = URL.documentsDirectory.appending(path: "Memo \(memos.count + 1).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            delegate.onFinish = { ok in
                note = ok ? "Saved \(url.lastPathComponent)" : "Recording failed"
                reload()
            }
            r.delegate = delegate
            r.record()
            recorder = r
            note = ""
        } catch {
            note = error.localizedDescription
        }
    }

    func play(_ url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: URL.documentsDirectory, includingPropertiesForKeys: nil)) ?? []
        memos = urls.filter { $0.pathExtension == "m4a" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
