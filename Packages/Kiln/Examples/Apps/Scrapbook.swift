import SwiftUI
import UniformTypeIdentifiers

// Round 3A's Lab example (Files): notes and lists kept as files in the app's
// own folder, listed with their sizes and kinds, copied, deleted, and moved
// between sections by drag and drop.

struct Entry: Identifiable, Hashable {
    let url: URL
    var id: String { url.lastPathComponent }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var kind: String { UTType(filenameExtension: url.pathExtension)?.identifier ?? "unknown" }
}

struct ContentView: View {
    @State private var entries: [Entry] = []
    @State private var sizes: [String: Int] = [:]
    @State private var starred: [String] = []
    @State private var counter = 0

    let folder = URL.documentsDirectory.appending(path: "Scrapbook", directoryHint: .isDirectory)

    var body: some View {
        NavigationStack {
            List {
                Section("Files") {
                    ForEach(entries) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.name).font(.headline)
                                Text(entry.kind).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(sizes[entry.id] ?? 0) B").monospacedDigit()
                        }
                        .draggable(entry.name)
                    }
                    .onDelete(perform: remove)
                }
                Section("Starred") {
                    Text(starred.isEmpty ? "Drop a file here" : starred.joined(separator: ", "))
                        .dropDestination(for: String.self) { names, _ in
                            starred += names
                            return true
                        }
                }
                Section("Kinds") {
                    LabeledContent("Text is data", value: UTType.plainText.conforms(to: .data) ? "yes" : "no")
                    LabeledContent("JSON extension", value: UTType.json.preferredFilenameExtension ?? "")
                    LabeledContent("PNG MIME type", value: UTType.png.preferredMIMEType ?? "")
                    LabeledContent("Total", value: "\(sizes.values.reduce(0, +)) bytes in \(entries.count) files")
                }
                Section {
                    Button("Add note") { add() }
                    Button("Duplicate first") { duplicate() }
                    Button("Delete last") { if !entries.isEmpty { remove(IndexSet(integer: entries.count - 1)) } }
                }
            }
            .navigationTitle("Scrapbook")
            .onAppear(perform: seed)
        }
    }

    func seed() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        write("Groceries.txt", "eggs\nmilk\nbread")
        write("Trip.json", #"{"city":"Lisbon","days":4}"#)
        write("Ideas.md", "# Ideas\n- a kite\n- a garden")
        reload()
    }

    func write(_ name: String, _ text: String) {
        try? text.write(to: folder.appending(path: name), atomically: true, encoding: .utf8)
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        entries = urls.map { Entry(url: $0) }.sorted { $0.name < $1.name }
        var out: [String: Int] = [:]
        for entry in entries {
            out[entry.id] = (try? entry.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }
        sizes = out
    }

    func add() {
        counter += 1
        write("Note \(counter).txt", String(repeating: "note ", count: counter))
        reload()
    }

    func duplicate() {
        guard let first = entries.first else { return }
        let copy = folder.appending(path: first.name + " copy." + first.url.pathExtension)
        try? FileManager.default.copyItem(at: first.url, to: copy)
        reload()
    }

    func remove(_ offsets: IndexSet) {
        for i in offsets { try? FileManager.default.removeItem(at: entries[i].url) }
        reload()
    }
}
