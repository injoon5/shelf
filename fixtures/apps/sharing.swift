// Name: Clip Board
// Icon: doc.on.clipboard
// Tint: teal
// Covers: Sharing

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct Clip: Codable, Identifiable, Transferable {
    var id = UUID()
    var text: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
        ProxyRepresentation(exporting: \.text)
    }
}

struct ContentView: View {
    @State private var clips: [Clip] = [Clip(text: "Pick up oat milk"), Clip(text: "https://www.apple.com")]
    @State private var draft = ""
    @State private var selection: TextSelection?
    @State private var status = "Nothing copied yet"

    var body: some View {
        NavigationStack {
            List {
                Section("New clip") {
                    TextField("Type or paste", text: $draft, selection: $selection)
                    HStack {
                        PasteButton(payloadType: String.self) { strings in
                            draft = strings.joined(separator: " ")
                        }
                        Spacer()
                        Button("Add") {
                            clips.append(Clip(text: draft))
                            draft = ""
                        }
                        .disabled(draft.isEmpty)
                    }
                }
                Section("Clips") {
                    ForEach(clips) { clip in
                        HStack {
                            Text(clip.text).textSelection(.enabled)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = clip.text
                                status = "Copied \(clip.text.count) characters"
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            ShareLink(item: clip, preview: SharePreview(clip.text)) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
                Section("Share") {
                    ShareLink("All clips", items: clips.map(\.text))
                    ShareLink("Apple", item: URL(string: "https://www.apple.com")!, subject: Text("Look"), message: Text("From Clip Board"))
                    ShareLink(item: Image(systemName: "doc.on.clipboard"), preview: SharePreview("Clip Board", image: Image(systemName: "doc.on.clipboard"))) {
                        Label("The icon", systemImage: "photo")
                    }
                    ShareLink(item: Data(clips.map(\.text).joined(separator: "\n").utf8), preview: SharePreview("clips.txt")) {
                        Label("As data", systemImage: "doc")
                    }
                }
                Section {
                    Text(status).foregroundStyle(.secondary)
                    if UIPasteboard.general.hasStrings {
                        Text("The clipboard has text").font(.caption)
                    }
                }
            }
            .navigationTitle("Clip Board")
            .copyable(clips.map(\.text))
            .pasteDestination(for: String.self) { strings in
                clips += strings.map { Clip(text: $0) }
            }
        }
    }
}
