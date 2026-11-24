import XCTest
import SwiftUI
import UniformTypeIdentifiers
@testable import Kiln

/// Round 3A (PLAN.md §4.1–§4.4): files, photos, the camera and recording.
/// Each bridge's forms bind and show, a check drives its callbacks with
/// sample values, the app's folder holds, and the capability gate's
/// answer is what the app sees. What needs UIKit (the camera's gate, saving
/// a `UIImage`, the picker on screen) is tested in Shelf, on the simulator.
@MainActor
final class Round3ATests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() async throws {
        await MainActor.run { for f in folders { try? FileManager.default.removeItem(at: f) } }
    }

    /// What a check (`validate`) prints and the errors it hits, with its context.
    func checked(_ source: String, capabilities: KilnStubCapabilities? = nil,
                 file: StaticString = #filePath, line: UInt = #line) throws -> (console: [String], errors: [String]) {
        XCTAssertEqual(Kiln.check(source).errors.map(\.message), [], file: file, line: line)
        let context = KilnContext.stub(capabilities: capabilities)
        defer { context.tearDown() }
        let compiled = try KilnEngine.compile(source, headless: true, context: context)
        defer { compiled.interp.tearDown() }
        KProbe(interp: compiled.interp, ticks: 8).run(compiled.root)
        let console = compiled.interp.console.split(separator: "\n").map(String.init)
        return (console, compiled.interp.errors)
    }

    /// A real (not stub) context with its own folder, and fakes for the hardware.
    func liveContext(_ capabilities: (any KilnCapabilityGate)? = nil) -> KilnContext {
        let folder = FileManager.default.temporaryDirectory.appending(path: "kiln-3a-\(UUID().uuidString)")
        folders.append(folder)
        let context = KilnContext(slug: "rec", name: "Recorder", defaults: KilnMemoryDefaults(), files: KilnFiles(root: folder),
                                  capabilities: capabilities ?? KilnStubCapabilities())
        context.provide(KilnFakeMicrophone())
        return context
    }

    // MARK: §4.1 The app's folder

    func testThePathRulesHold() throws {
        let out = try checked(BridgeTest.app(#"Text("x").onAppear { run() }"#, extra: #"""
            func run() {
                let docs = URL.documentsDirectory
                print(docs.lastPathComponent, URL.cachesDirectory.lastPathComponent, URL.applicationSupportDirectory.lastPathComponent)
                try? "hi".write(to: docs.appending(path: "a.txt"), atomically: true, encoding: .utf8)
                print((try? String(contentsOf: docs.appending(path: "a.txt"), encoding: .utf8)) ?? "nil")
                for bad in [URL(fileURLWithPath: "/etc/hosts"), docs.appending(path: "../../../../x.txt")] {
                    do { _ = try Data(contentsOf: bad); print("read") } catch { print("refused") }
                }
                print(URL(fileURLWithPath: "/etc/hosts").startAccessingSecurityScopedResource())
            }
            """#))
        XCTAssertEqual(out.console, ["Documents Caches Application Support", "hi", "refused", "refused", "false"])
        XCTAssertEqual(out.errors, [])
        // Without a catch, leaving the folder is the app's error, with its line.
        let errors = Kiln.validate(BridgeTest.app(#"Text("x").onAppear { _ = try? AVAudioRecorder(url: URL(fileURLWithPath: "/tmp/x.m4a"), settings: [:]); let d = Data(); try! d.write(to: URL(fileURLWithPath: "/tmp/y")) }"#)).errors
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors.first?.contains("/tmp/y is outside the app's folder") ?? false, "\(errors)")
    }

    func testAPickedFileIsTheAppsWhileItRuns() throws {
        let context = liveContext()
        let outside = FileManager.default.temporaryDirectory.appending(path: "kiln-3a-picked-\(UUID().uuidString).txt")
        folders.append(outside)
        try Data("picked".utf8).write(to: outside)
        XCTAssertThrowsError(try context.resolveFile(outside))
        KFileGrants.of(context).grant(outside)
        XCTAssertEqual(try context.resolveFile(outside).lastPathComponent, outside.lastPathComponent)
        context.tearDown()
        XCTAssertNil(context.provided(KFileGrants.self)?.allows(outside))
    }

    // MARK: §4.1 Pickers

    static let pickerApp = #"""
        import SwiftUI
        import UniformTypeIdentifiers

        struct TextFile: FileDocument {
            static var readableContentTypes: [UTType] { [.plainText] }
            var text: String
            init(text: String) { self.text = text }
            init(configuration: ReadConfiguration) throws {
                text = configuration.file.regularFileContents.map { String(decoding: $0, as: UTF8.self) } ?? ""
            }
            func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
                FileWrapper(regularFileWithContents: Data(text.utf8))
            }
        }

        final class Ledger: ReferenceFileDocument {
            static var readableContentTypes: [UTType] { [.json] }
            var lines: [String] = ["a", "b"]
            init() {}
            required init(configuration: ReadConfiguration) throws {}
            func snapshot(contentType: UTType) throws -> [String] { lines }
            func fileWrapper(snapshot: [String], configuration: WriteConfiguration) throws -> FileWrapper {
                FileWrapper(regularFileWithContents: try JSONEncoder().encode(snapshot))
            }
        }

        struct Note: Codable, Transferable {
            var text: String
            static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .json) }
        }

        struct ContentView: View {
            @State private var a = false
            @State private var b = false
            @State private var preview: URL?
            var body: some View {
                VStack {
                    Text("Files")
                }
                .fileImporter(isPresented: $a, allowedContentTypes: [.plainText]) { result in
                    switch result {
                    case .success(let url):
                        print("access", url.startAccessingSecurityScopedResource())
                        print("read", (try? String(contentsOf: url, encoding: .utf8)) ?? "nil")
                        let copy = URL.documentsDirectory.appending(path: "copy.txt")
                        try? FileManager.default.copyItem(at: url, to: copy)
                        print("copied", FileManager.default.fileExists(atPath: copy.path()))
                    case .failure(let error):
                        print("failed", error)
                    }
                }
                .fileImporter(isPresented: $a, allowedContentTypes: [.plainText, .json], allowsMultipleSelection: true) { result in
                    print("many", (try? result.get())?.count ?? -1)
                } onCancellation: {
                    print("cancelled")
                }
                .fileExporter(isPresented: $b, document: TextFile(text: "hi"), contentType: .plainText, defaultFilename: "Note") { result in
                    print("exported", (try? result.get())?.lastPathComponent ?? "nil")
                }
                .fileExporter(isPresented: $b, documents: [TextFile(text: "1"), TextFile(text: "2")], contentType: .plainText) { result in
                    print("exported many", (try? result.get())?.count ?? -1)
                }
                .fileExporter(isPresented: $b, document: Ledger(), contentType: .json) { _ in }
                .fileExporter(isPresented: $b, item: Note(text: "n"), contentTypes: [.json], defaultFilename: "n") { _ in } onCancellation: {}
                .fileExporter(isPresented: $b, item: Data("raw".utf8), contentTypes: [.plainText]) { _ in }
                .fileExporter(isPresented: $b, items: ["a", "b"], contentTypes: [.plainText]) { _ in }
                .fileMover(isPresented: $b, file: URL.documentsDirectory.appending(path: "copy.txt")) { result in
                    if case .success(let url) = result { print("moved", url.lastPathComponent) }
                }
                .fileMover(isPresented: $b, files: [URL.documentsDirectory.appending(path: "copy.txt")]) { _ in } onCancellation: {}
                .quickLookPreview($preview)
                .quickLookPreview($preview, in: [URL.documentsDirectory.appending(path: "copy.txt")])
                .fileDialogMessage("Pick a note")
                .fileDialogConfirmationLabel("Open")
                .fileExporterFilenameLabel("Save as")
                .fileDialogCustomizationID("notes")
                .fileDialogDefaultDirectory(URL.documentsDirectory)
                .fileDialogImportsUnresolvedAliases(false)
                .fileDialogBrowserOptions([.displayFileExtensions, .includeHiddenFiles])
            }
        }
        """#

    func testThePickersFormsBindAndShow() throws {
        XCTAssertEqual(BridgeTest.problems(Self.pickerApp), [])
        let bound = try BridgeTest.bound(Self.pickerApp)
        XCTAssertEqual(bound.filter { $0.hasPrefix(".fileExporter") }, [
            ".fileExporter(isPresented:document:contentType:defaultFilename:onCompletion:)",
            ".fileExporter(isPresented:documents:contentType:onCompletion:)",
            ".fileExporter(isPresented:document:contentType:defaultFilename:onCompletion:)",
            ".fileExporter(isPresented:item:contentTypes:defaultFilename:onCompletion:onCancellation:)",
            ".fileExporter(isPresented:item:contentTypes:defaultFilename:onCompletion:onCancellation:)",
            ".fileExporter(isPresented:items:contentTypes:onCompletion:onCancellation:)", ".fileExporterFilenameLabel(_:)",
        ])
    }

    func testACheckHandsTheImporterAFileAndTheExporterAURL() throws {
        let out = try checked(Self.pickerApp)
        XCTAssertEqual(out.errors, [])
        for expected in ["access true", "read Sample", "copied true", "many 1", "cancelled", "exported Note", "exported many 1", "moved Moved"] {
            XCTAssertTrue(out.console.contains(expected), "\(expected) not in \(out.console)")
        }
    }

    func testDocumentsWriteThroughTheirProxies() throws {
        let c = try KilnEngine.compile(Self.pickerApp, headless: true)
        defer { c.interp.tearDown() }
        let interp = c.interp
        let file = try XCTUnwrap(interp.types["TextFile"])
        let doc = try KFileDocuments.read(file, data: Data("from disk".utf8), contentType: .plainText, interp)
        XCTAssertEqual(String(decoding: try KFileDocuments.data(of: doc, contentType: .plainText, interp), as: UTF8.self), "from disk")
        XCTAssertEqual(KFileDocuments.readableContentTypes(file, interp), [.plainText])
        let ledger = try interp.entry { try interp.instantiate(try XCTUnwrap(interp.types["Ledger"]), args: [], labels: [], line: 0) }
        XCTAssertNotNil(KFileDocuments.document(for: ledger, interp))
        XCTAssertEqual(String(decoding: try KFileDocuments.data(of: ledger, contentType: .json, interp), as: UTF8.self), #"["a","b"]"#)
    }

    func testAMissingDocumentRequirementIsAnError() {
        let src = BridgeTest.app(#"Text("x")"#, extra: """
            final class Doc: ReferenceFileDocument {
                static var readableContentTypes: [UTType] { [.json] }
                required init(configuration: ReadConfiguration) throws {}
                func snapshot(contentType: UTType) throws -> Int { 1 }
            }
            """)
        let errors = Kiln.validate(src).errors
        XCTAssertTrue(errors.contains { $0.contains("'Doc' doesn't conform to 'ReferenceFileDocument': it has no fileWrapper(snapshot:configuration:)") }, "\(errors)")
    }

    // MARK: §4.1 UTType

    func testEveryUTTypeAndItsMembers() throws {
        XCTAssertEqual(FilesBridges.knownTypes.count, 140)
        let out = try checked(BridgeTest.app(#"Text("x").onAppear { run() }"#, extra: #"""
            func run() {
                print(UTType.png.identifier, UTType.json.conforms(to: .text), UTType.heic.isSubtype(of: .image), UTType.image.isSupertype(of: .jpeg))
                print(UTType(filenameExtension: "md")?.identifier ?? "nil", UTType(mimeType: "application/pdf")?.identifier ?? "nil")
                print(UTType.plainText.preferredFilenameExtension ?? "", UTType.mp3.preferredMIMEType ?? "")
                print(UTType("public.mpeg-4") == .mpeg4Movie, UTType.yaml.isDeclared, UTType.swiftSource.identifier)
                print(UTType(filenameExtension: "kilnx", conformingTo: .data)?.isDynamic ?? false)
                let custom = UTType(exportedAs: "dev.example.board")
                print(custom.identifier, UTType.types(tag: "jpg", tagClass: .filenameExtension, conformingTo: nil).first?.identifier ?? "")
            }
            """#))
        XCTAssertEqual(out.console, ["public.png true true true", "net.daringfireball.markdown com.adobe.pdf", "txt audio/mpeg",
                                     "true true public.swift-source", "true", "dev.example.board public.jpeg"])
    }

    // MARK: §4.1 Drag and drop

    static let dragApp = #"""
        import SwiftUI
        import UniformTypeIdentifiers

        struct Card: Codable, Identifiable, Transferable {
            var id: Int
            var title: String
            static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .json) }
        }

        struct Dropper: DropDelegate {
            func performDrop(info: DropInfo) -> Bool {
                print("delegate", info.hasItemsConforming(to: [.plainText]))
                return true
            }
            func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
        }

        struct ContentView: View {
            @State private var cards = [Card(id: 1, title: "One"), Card(id: 2, title: "Two")]
            @State private var over = false
            @Namespace private var space
            var body: some View {
                VStack {
                    Text("Drag").draggable("text")
                    Text("Drag card").draggable(cards[0]) { Text("Preview") }
                    Text("URL").draggable(URL(string: "https://example.com")!)
                    Text("Drop strings")
                        .dropDestination(for: String.self) { items, location in
                            print("strings", items, location.x)
                            return true
                        } isTargeted: { over = $0 }
                    Text("Drop cards")
                        .dropDestination(for: Card.self) { cards, session in
                            print("session", session.phase == .ended(.copy), session.itemsCount)
                        }
                    List {
                        ForEach(cards) { card in Text(card.title) }
                            .onDelete { cards.remove(atOffsets: $0) }
                            .dropDestination(for: String.self) { items, index in print("insert", items, index) }
                    }
                    Text("Old").onDrop(of: [.plainText], isTargeted: $over) { providers in
                        providers.first?.loadObject(ofClass: String.self) { text, _ in print("provider", text ?? "nil") }
                        return true
                    }
                    Text("Old with location").onDrop(of: ["public.text"], isTargeted: nil) { providers, location in providers.count == 1 }
                    Text("Delegate").onDrop(of: [.plainText], delegate: Dropper())
                    Text("Provider").onDrag { NSItemProvider(object: "dragged" as NSString) }
                    Text("Provider 2").itemProvider { NSItemProvider(object: "x" as NSString) }
                    Text("Spring").springLoadingBehavior(.enabled)
                    HStack {
                        ForEach(cards) { card in Text(card.title).draggable(containerItemID: card.id, containerNamespace: space) }
                    }
                    .dragContainer(for: Card.self, in: space) { ids in cards.filter { ids.contains($0.id) } }
                    .dragContainerSelection([1], containerNamespace: space)
                    .dragConfiguration(DragConfiguration(allowMove: true))
                    .onDragSessionUpdated { session in
                        if case .ended(let op) = session.phase { print("drag ended", op == .move) }
                    }
                    .onDropSessionUpdated { session in print("drop phase", session.phase == .ended(.copy)) }
                    .dropConfiguration { _ in DropConfiguration(operation: .move) }
                    Text("Item").draggable(Card.self, item: cards[1], containerNamespace: space)
                }
            }
        }
        """#

    func testDragAndDropFormsBindShowAndAreChecked() throws {
        XCTAssertEqual(BridgeTest.problems(Self.dragApp), [])
        let out = try checked(Self.dragApp)
        XCTAssertEqual(out.errors, [])
        for expected in ["strings [\"Pasted\"] 0.0", "session true 1", "insert [\"Pasted\"] 0", "provider Dropped", "drag ended true", "drop phase true"] {
            XCTAssertTrue(out.console.contains(expected), "\(expected) not in \(out.console)")
        }
    }

    func testDroppedValuesAreThePayloadType() async throws {
        let c = try KilnEngine.compile(Self.dragApp, headless: true)
        defer { c.interp.tearDown() }
        let context = c.interp.context
        let items = [KDropItem(value: .string("hello")), KDropItem(value: .data(Data(#"{"id":3,"title":"Three"}"#.utf8), .json)),
                     KDropItem(value: .url(URL(string: "https://example.com/a")!))]
        let strings = await KDropItem.values(items, as: .type(.builtin("String")), c.interp, context)
        XCTAssertEqual(strings.compactMap(\.asString), ["hello", #"{"id":3,"title":"Three"}"#, "https://example.com/a"])
        let urls = await KDropItem.values(items, as: .type(.builtin("URL")), c.interp, context)
        XCTAssertEqual(urls.count, 1)
        let cards = await KDropItem.values(items, as: .type(.user(try XCTUnwrap(c.interp.types["Card"]))), c.interp, context)
        XCTAssertEqual(cards.map { c.interp.describe($0) }, [#"Card(id: 3, title: "Three")"#])
    }

    func testADropDelegateNeedsPerformDrop() {
        let src = BridgeTest.app(#"Text("x").onDrop(of: [.text], delegate: D())"#, extra: "struct D: DropDelegate { func dropEntered(info: DropInfo) {} }")
        let errors = Kiln.validate(src).errors
        XCTAssertTrue(errors.contains { $0.contains("'D' doesn't conform to 'DropDelegate': it has no performDrop(info:)") }, "\(errors)")
    }

    // MARK: FileRepresentation

    func testFileRepresentationImportsIntoTheAppsFolder() async throws {
        let src = BridgeTest.app(#"Text("x")"#, extra: #"""
            struct Clip: Transferable {
                let url: URL
                static var transferRepresentation: some TransferRepresentation {
                    FileRepresentation(contentType: .movie) { clip in SentTransferredFile(clip.url) } importing: { received in
                        let copy = URL.documentsDirectory.appending(path: "clip.mov")
                        try? FileManager.default.removeItem(at: copy)
                        try FileManager.default.copyItem(at: received.file, to: copy)
                        return Clip(url: copy)
                    }
                }
            }
            """#)
        let context = liveContext()
        let c = try KilnEngine.compile(src, headless: false, context: context)
        defer { c.interp.tearDown(); context.tearDown() }
        let clipType = try XCTUnwrap(c.interp.types["Clip"])
        let clip = try await KTransferables.importValue(clipType, data: Data("movie bytes".utf8), contentType: .quickTimeMovie, c.interp)
        let url = try XCTUnwrap(try c.interp.member(try XCTUnwrap(clip), "url", line: 0).asURL)
        XCTAssertEqual(url.lastPathComponent, "clip.mov")
        XCTAssertTrue(url.path(percentEncoded: false).hasPrefix(context.files.root.resolvingSymlinksInPath().path(percentEncoded: false)) ||
                      url.path(percentEncoded: false).hasPrefix(context.files.root.path(percentEncoded: false)))
        // Exporting reads the file back.
        let data = try await KTransferables.data(try XCTUnwrap(clip), as: .movie, c.interp)
        XCTAssertEqual(data.map { String(decoding: $0, as: UTF8.self) }, "movie bytes")
    }

    // MARK: §4.2 Photos

    func testPhotosPickerFormsBindAndShow() throws {
        let src = BridgeTest.app(#"""
            VStack {
                PhotosPicker("One", selection: $item, matching: .images)
                PhotosPicker(selection: $items, maxSelectionCount: 4, selectionBehavior: .ordered, matching: .any(of: [.images, .not(.livePhotos)])) {
                    Label("Many", systemImage: "photo.stack")
                }
                PhotosPicker(selection: $item, matching: .videos, preferredItemEncoding: .current, photoLibrary: .shared()) { Text("Library") }
                PhotosPicker(selection: $item) { Text("Inline") }
                    .photosPickerStyle(.inline)
                    .photosPickerDisabledCapabilities([.search, .selectionActions])
                    .photosPickerAccessoryVisibility(.hidden, edges: .bottom)
                    .photosPickerSearchText("cats")
                    .photosPickerMetadataOptions(.removeLocation)
            }
            .photosPicker(isPresented: $shown, selection: $items, maxSelectionCount: 2, matching: .screenshots)
            .onChange(of: item) { Task { _ = try? await item?.loadTransferable(type: Data.self) } }
            """#, state: "@State private var item: PhotosPickerItem?\n@State private var items: [PhotosPickerItem] = []\n@State private var shown = false",
            extra: "import PhotosUI")
        XCTAssertEqual(BridgeTest.problems(src), [])
        XCTAssertEqual(try BridgeTest.bound(src).filter { $0.hasPrefix("PhotosPicker") }, [
            "PhotosPicker(_:selection:matching:preferredItemEncoding:)",
            "PhotosPicker(selection:maxSelectionCount:selectionBehavior:matching:preferredItemEncoding:label:)",
            "PhotosPicker(selection:matching:preferredItemEncoding:photoLibrary:label:)",
            "PhotosPicker(selection:matching:preferredItemEncoding:label:)",
        ])
    }

    func testACheckLoadsASmallImage() throws {
        let out = try checked(BridgeTest.app(#"Text("x").task { await run() }"#, extra: #"""
            import PhotosUI
            func run() async {
                let item = PhotosPickerItem(itemIdentifier: "x")
                let data = try? await item.loadTransferable(type: Data.self)
                print("data", (data?.count ?? 0) > 0)
                item.loadTransferable(type: Data.self) { result in
                    if case .success(let d) = result { print("handler", d != nil) }
                }
            }
            """#))
        XCTAssertEqual(out.errors, [])
        XCTAssertEqual(out.console, ["data true", "handler true"])
    }

    func testSavingAsksAndARefusedAppGetsTheDeniedAnswer() throws {
        let app = BridgeTest.app(#"Text("x").task { await run() }"#, extra: #"""
            import Photos
            func run() async {
                print("before", PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined)
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                print("status", status == .authorized, status == .denied)
                let file = URL.documentsDirectory.appending(path: "p.png")
                try? Data([1, 2, 3]).write(to: file)
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: file)
                    }
                    print("saved")
                } catch {
                    print("not saved")
                }
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { s in print("handler", s == .authorized) }
            }
            """#)
        KPhotoSaves.saved = []
        let allowed = try checked(app, capabilities: KilnStubCapabilities([:], answerWhenAsked: true))
        XCTAssertEqual(allowed.console, ["before true", "status true false", "saved", "handler true"])
        XCTAssertEqual(KPhotoSaves.saved, [.file("p.png")])

        KPhotoSaves.saved = []
        let refused = KilnStubCapabilities([.photoLibraryAdd: .denied])
        let denied = try checked(app, capabilities: refused)
        XCTAssertEqual(denied.console, ["before false", "status false true", "not saved", "handler false"])
        XCTAssertEqual(KPhotoSaves.saved, [])
        XCTAssertTrue(refused.requested.allSatisfy { $0 == .photoLibraryAdd })
    }

    func testAChangeRequestOutsidePerformChangesIsAnError() {
        let errors = Kiln.validate(BridgeTest.app(#"Text("x").onAppear { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: URL.documentsDirectory) }"#, extra: "import Photos")).errors
        XCTAssertTrue(errors.first?.contains("inside PHPhotoLibrary.shared().performChanges") ?? false, "\(errors)")
    }

    // MARK: §4.3 Camera permissions

    func testCaptureDeviceAnswersFromTheGate() throws {
        let app = BridgeTest.app(#"Text("x").task { await run() }"#, extra: #"""
            import AVFoundation
            func run() async {
                print(AVCaptureDevice.authorizationStatus(for: .video) == .authorized, AVCaptureDevice.authorizationStatus(for: .audio) == .denied)
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                print("granted", granted)
                AVCaptureDevice.requestAccess(for: .audio) { ok in print("audio", ok) }
                print(UIImagePickerController.isSourceTypeAvailable(.camera))
            }
            """#)
        let out = try checked(app, capabilities: KilnStubCapabilities([.camera: .allowed, .microphone: .denied]))
        XCTAssertEqual(Array(out.console.prefix(3)), ["true true", "granted true", "audio false"])
        let off = try checked(app, capabilities: KilnStubCapabilities([.camera: .denied, .microphone: .denied]))
        XCTAssertEqual(Array(off.console.prefix(2)), ["false true", "granted false"])
    }

    // MARK: §4.4 Recording

    static let recorderApp = #"""
        import SwiftUI
        import AVFoundation

        final class Watcher: NSObject, AVAudioRecorderDelegate {
            func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
                print("finished", flag, recorder.url.lastPathComponent)
            }
        }

        var recorder: AVAudioRecorder?
        let watcher = Watcher()

        let start: () -> Bool = {
            let url = URL.documentsDirectory.appending(path: "take.m4a")
            let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 22050, AVNumberOfChannelsKey: 1,
                                           AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
            recorder = try? AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = watcher
            recorder?.isMeteringEnabled = true
            return recorder?.record() ?? false
        }

        struct ContentView: View {
            var body: some View { Text("Rec") }
        }
        """#

    func testRecordingRecordsMetersAndStopsWithTheCard() throws {
        var recorded = 0, stopped = 0
        let context = liveContext()
        context.provide(KilnAudioSession(willPlay: {}, didStop: {}, willRecord: { recorded += 1 }, didStopRecording: { stopped += 1 }))
        let c = try KilnEngine.compile(Self.recorderApp, headless: false, context: context)
        defer { c.interp.tearDown() }
        guard case .function(let start)? = c.interp.globalEnv.lookup("start")?.value else { return XCTFail("no start") }
        XCTAssertEqual(try c.interp.entry { try c.interp.call(start, [], []) }, .bool(true))
        guard case .native(.object(_, let ref))? = c.interp.globalEnv.lookup("recorder")?.value, let rec = ref.value as? KRecorder else { return XCTFail("no recorder") }
        XCTAssertTrue(rec.isRecording)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        rec.updateMeters()
        XCTAssertGreaterThan(rec.averagePower(), -60)
        XCTAssertGreaterThan(rec.currentTime, 0.2)
        // The card closes: the recorder stops, its file is written and its delegate hears.
        context.tearDown()
        XCTAssertFalse(rec.isRecording)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rec.url.path(percentEncoded: false)))
        XCTAssertTrue(c.interp.console.contains("finished true take.m4a"), c.interp.console)
        // A fake microphone never holds the session: only the real one does.
        XCTAssertEqual(recorded, 0)
        XCTAssertEqual(stopped, 0)
    }

    func testARefusedMicrophoneRecordsNothing() throws {
        let context = liveContext(KilnStubCapabilities([.microphone: .denied]))
        defer { context.tearDown() }
        let c = try KilnEngine.compile(Self.recorderApp + #"""

            func permissions() async {
                print(AVAudioApplication.shared.recordPermission == .denied, AVAudioSession.sharedInstance().recordPermission == .denied)
                print(await AVAudioApplication.requestRecordPermission())
            }
            """#, headless: true, context: context)
        defer { c.interp.tearDown() }
        guard case .function(let start)? = c.interp.globalEnv.lookup("start")?.value else { return XCTFail("no start") }
        XCTAssertEqual(try c.interp.entry { try c.interp.call(start, [], []) }, .bool(false))
        let out = try checked(BridgeTest.app(#"Text("x").task { await run() }"#, extra: #"""
            import AVFoundation
            func run() async {
                print(AVAudioApplication.shared.recordPermission == .denied, AVAudioSession.sharedInstance().recordPermission == .denied)
                print(await AVAudioApplication.requestRecordPermission())
                AVAudioApplication.requestRecordPermission { ok in print("handler", ok) }
                try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            """#), capabilities: KilnStubCapabilities([.microphone: .denied]))
        XCTAssertEqual(out.console, ["true true", "false", "handler false"])
    }
}

private extension KV {
    var asURL: URL? { if case .native(.url(let u)) = self { return u }; return nil }
}
