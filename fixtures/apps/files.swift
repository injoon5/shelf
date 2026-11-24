// Name: Notebook
// Icon: doc.text.fill
// Tint: brown
// Covers: Files

import SwiftUI
import UniformTypeIdentifiers

// Notes as plain-text files in the app's own folder (they stay on this
// device; DB is what syncs), opened from Files with .fileImporter, saved
// out with .fileExporter, previewed with Quick Look, and moved by drag and drop.

struct TextFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct Note: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

struct ContentView: View {
    @State private var notes: [Note] = []
    @State private var draft = ""
    @State private var importing = false
    @State private var exporting = false
    @State private var exportText = ""
    @State private var preview: URL?
    @State private var pinned: [String] = []
    @State private var status = "Ready"

    var body: some View {
        NavigationStack {
            List {
                Section("New note") {
                    TextField("Write something", text: $draft, axis: .vertical)
                    Button("Save as a file") { save() }
                        .disabled(draft.isEmpty)
                }
                Section("Notes") {
                    ForEach(notes) { note in
                        HStack {
                            Label(note.title, systemImage: "doc.text")
                                .draggable(note.title)
                            Spacer()
                            Button("Preview", systemImage: "eye") { preview = note.url }
                                .labelStyle(.iconOnly)
                            Button("Export", systemImage: "square.and.arrow.up") {
                                exportText = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
                                exporting = true
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                    .onDelete(perform: delete)
                }
                Section("Pinned (drop a note here)") {
                    Text(pinned.isEmpty ? "Nothing yet" : pinned.joined(separator: ", "))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .dropDestination(for: String.self) { titles, _ in
                            pinned += titles
                            return true
                        }
                }
                Section {
                    LabeledContent("Kind", value: UTType.plainText.localizedDescription ?? "Text")
                    LabeledContent("Extension", value: UTType.plainText.preferredFilenameExtension ?? "txt")
                    Text(status).foregroundStyle(.secondary)
                } footer: {
                    Text("Files stay on this iPhone.")
                }
            }
            .navigationTitle("Notebook")
            .toolbar {
                Button("Open", systemImage: "folder") { importing = true }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    for url in urls { bringIn(url) }
                    reload()
                case .failure(let error):
                    status = error.localizedDescription
                }
            }
            .fileExporter(isPresented: $exporting, document: TextFile(text: exportText), contentType: .plainText, defaultFilename: "Note") { result in
                if let url = try? result.get() { status = "Exported \(url.lastPathComponent)" }
            }
            .quickLookPreview($preview)
            .onAppear(perform: reload)
        }
    }

    var folder: URL { URL.documentsDirectory }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        notes = urls.filter { $0.pathExtension == "txt" }.map { Note(url: $0) }.sorted { $0.title < $1.title }
    }

    func save() {
        let name = draft.split(separator: " ").prefix(3).joined(separator: " ")
        let url = folder.appending(path: (name.isEmpty ? "Note" : name) + ".txt")
        do {
            try draft.write(to: url, atomically: true, encoding: .utf8)
            draft = ""
            status = "Saved \(url.lastPathComponent)"
        } catch {
            status = error.localizedDescription
        }
        reload()
    }

    func bringIn(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        let copy = folder.appending(path: url.lastPathComponent)
        try? FileManager.default.removeItem(at: copy)
        do {
            try FileManager.default.copyItem(at: url, to: copy)
            status = "Opened \(url.lastPathComponent)"
        } catch {
            status = error.localizedDescription
        }
    }

    func delete(_ offsets: IndexSet) {
        for i in offsets { try? FileManager.default.removeItem(at: notes[i].url) }
        reload()
    }
}
