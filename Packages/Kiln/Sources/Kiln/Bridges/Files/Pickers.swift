//
//  Pickers.swift
//  Bridges: the file pickers (PLAN.md §4.1)
//
//  `.fileImporter`, `.fileExporter`, `.fileMover`, the `.fileDialog…`
//  modifiers and `.quickLookPreview`, all SwiftUI's own:
//
//  - What the importer returns is outside the app's folder: Kiln grants it
//    to the run (Grants.swift), with security-scoped access started for the
//    app and stopped when it closes. `Data(contentsOf:)`, `String(contentsOf:)`
//    and `FileManager.copyItem(at:to:)` then read it.
//  - The exporter takes the app's own `FileDocument` (or `ReferenceFileDocument`)
//    through its proxy (Files.swift), `Data` or a `String` with a `UTType`,
//    or the app's `Transferable` (Sharing/Transferable.swift).
//  - The mover moves a file out of the app's folder, to where the person
//    puts it; the URL it lands at is granted like an imported one.
//  - A check (`validate`) shows no picker: the importer's completion gets a
//    small file in the run's throwaway folder, the exporter's and mover's a
//    URL there.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(QuickLook) && !os(tvOS)
import QuickLook
#endif

extension FilesBridges {
    static func pickers(_ r: KRegistry) {
        importer(r)
        exporter(r)
        mover(r)
        dialogs(r)
        quickLook(r)
    }

    // MARK: Results

    /// A Swift `Result`: the prelude's (KSwiftPrelude), which the names of
    /// these bridges bring into the app, so `try result.get()` works.
    @MainActor static func result(_ caseName: String, _ v: KV, _ interp: KInterpreter?) -> KV {
        if let t = interp?.types["Result"], t.kind == .enumType, t.cases.contains(where: { $0.name == caseName }) {
            return .enumV(KEnumValue(type: t, caseName: caseName, payload: [v]))
        }
        return .native(.implicit(caseName, [v]))
    }
    @MainActor static func success(_ v: KV, _ interp: KInterpreter? = nil) -> KV { result("success", v, interp) }
    @MainActor static func failure(_ error: Error, _ interp: KInterpreter? = nil) -> KV {
        result("failure", KBuiltins.errorValue((error as NSError).localizedDescription), interp)
    }
    static func url(_ u: URL) -> KV { .native(.url(u)) }

    /// What a check's importer hands the app: a file in the run's own folder.
    @MainActor static func sampleFile(_ interp: KInterpreter, named name: String = "Sample.txt") -> URL {
        let url = interp.context.files.temporary.appending(path: name)
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? Data("Sample".utf8).write(to: url)
        }
        return url
    }

    // MARK: fileImporter

    static func importer(_ r: KRegistry) {
        r.modifier("fileImporter", .files,
                   notes: "The URLs it returns are the app's to read while it's open: `Data(contentsOf:)`, `String(contentsOf:)`, or `FileManager.default.copyItem(at:to:)` into `URL.documentsDirectory` to keep one.") { m in
            m.forms(["isPresented:binding allowedContentTypes:any onCompletion:closure",
                     "isPresented:binding allowedContentTypes:any allowsMultipleSelection:bool onCompletion:closure",
                     "isPresented:binding allowedContentTypes:any allowsMultipleSelection:bool onCompletion:closure onCancellation:closure"]) { c, view in
                fileImporter(c, view)
            }
            m.probe { _, args, interp in
                var calls: [KProbeCall] = []
                if case .function(let f)? = args["onCompletion"] {
                    let file = sampleFile(interp)
                    KFileGrants.of(interp.context).grant(file)
                    let many = args["allowsMultipleSelection"] != nil
                    calls.append(KProbeCall(fn: f, args: [success(many ? .array([url(file)]) : url(file), interp)], use: .action))
                }
                if case .function(let f)? = args["onCancellation"] { calls.append(KProbeCall(fn: f, use: .action)) }
                return calls
            }
        }
    }

    @MainActor static func fileImporter(_ c: KCall, _ view: AnyView) -> AnyView {
        guard let b = c.kbinding("isPresented"), let done = c.function("onCompletion") else { return view }
        let interp = c.interp, context = c.context
        let types = utTypes(c["allowedContentTypes"], interp)
        let returnsArray = c.has("allowsMultipleSelection")
        let many = c.bool("allowsMultipleSelection", default: false)
        let cancel = c.function("onCancellation")
        let shown = c.r.boolBinding(b)
        let completion: (Result<[URL], Error>) -> Void = { result in
            switch result {
            case .success(let urls):
                let grants = KFileGrants.of(context)
                urls.forEach(grants.grant)
                interp.perform(done, [success(returnsArray ? .array(urls.map(url)) : (urls.first.map(url) ?? .nilValue), interp)])
            case .failure(let error):
                interp.perform(done, [failure(error, interp)])
            }
        }
        if let cancel {
            return AnyView(view.fileImporter(isPresented: shown, allowedContentTypes: types.isEmpty ? [.item] : types, allowsMultipleSelection: many,
                                             onCompletion: completion, onCancellation: { interp.perform(cancel) }))
        }
        return AnyView(view.fileImporter(isPresented: shown, allowedContentTypes: types.isEmpty ? [.item] : types,
                                         allowsMultipleSelection: many, onCompletion: completion))
    }

    // MARK: fileExporter

    static func exporter(_ r: KRegistry) {
        r.modifier("fileExporter", .files,
                   notes: "`document:` your `FileDocument` with `contentType:`; or `item:` `Data` or a `String` with `contentTypes: [.png]`, or your `Transferable`; `documents:`/`items:` for several.") { m in
            m.forms(["isPresented:binding document:any contentType:UTType defaultFilename:string? onCompletion:closure",
                     "isPresented:binding documents:any contentType:UTType onCompletion:closure",
                     "isPresented:binding document:any contentTypes:any? defaultFilename:string? onCompletion:closure onCancellation:closure?",
                     "isPresented:binding documents:any contentTypes:any? onCompletion:closure onCancellation:closure?",
                     "isPresented:binding item:any contentTypes:any? defaultFilename:string? onCompletion:closure onCancellation:closure?",
                     "isPresented:binding items:any contentTypes:any? onCompletion:closure onCancellation:closure?"]) { c, view in
                fileExporter(c, view)
            }
            m.probe { _, args, interp in
                var calls: [KProbeCall] = []
                if case .function(let f)? = args["onCompletion"] {
                    let out = interp.context.files.temporary.appending(path: args["defaultFilename"]?.asString ?? "Exported")
                    let many = args["documents"] != nil || args["items"] != nil
                    calls.append(KProbeCall(fn: f, args: [success(many ? .array([url(out)]) : url(out), interp)], use: .action))
                }
                if case .function(let f)? = args["onCancellation"] { calls.append(KProbeCall(fn: f, use: .action)) }
                return calls
            }
        }
    }

    @MainActor static func fileExporter(_ c: KCall, _ view: AnyView) -> AnyView {
        guard let b = c.kbinding("isPresented"), let done = c.function("onCompletion") else { return view }
        let interp = c.interp, context = c.context
        let shown = c.r.boolBinding(b)
        let cancel = c.function("onCancellation").map { f in { interp.perform(f) } } ?? {}
        let many = c.has("documents") || c.has("items")
        let types = c.has("contentType") ? utTypes(c["contentType"], interp) : utTypes(c["contentTypes"], interp)
        let filename = c.string("defaultFilename")
        let one: (Result<URL, Error>) -> Void = { result in
            switch result {
            case .success(let u): KFileGrants.of(context).grant(u); interp.perform(done, [success(url(u), interp)])
            case .failure(let error): interp.perform(done, [failure(error, interp)])
            }
        }
        let several: (Result<[URL], Error>) -> Void = { result in
            switch result {
            case .success(let us):
                let grants = KFileGrants.of(context)
                us.forEach(grants.grant)
                interp.perform(done, [success(.array(us.map(url)), interp)])
            case .failure(let error): interp.perform(done, [failure(error, interp)])
            }
        }

        // The app's Transferable: SwiftUI's own item exporter.
        let values: [KV] = many ? ((try? interp.sequence(c["documents"] ?? c["items"] ?? .array([]))) ?? []) : [c["document"] ?? c["item"] ?? .nilValue]
        if c.has("item") || c.has("items"), let first = values.first(where: { !$0.isNil }),
           KFileDocuments.document(for: first, interp) == nil, interp.proxy(for: first, as: "Transferable") is KTransferItem {
            let items = values.compactMap { interp.proxy(for: $0, as: "Transferable") as? KTransferItem }
            if many {
                return AnyView(view.fileExporter(isPresented: shown, items: items, contentTypes: types, onCompletion: several, onCancellation: cancel))
            }
            return AnyView(view.fileExporter(isPresented: shown, item: items.first, contentTypes: types, defaultFilename: filename,
                                             onCompletion: one, onCancellation: cancel))
        }

        // Everything else as a document: the app's, or bytes.
        var documents: [KExportDocument] = []
        for v in values where !v.isNil {
            guard let d = exportDocument(v, types.first, c) else {
                interp.report(c.fail("exports your FileDocument, Data, a String, an Image or your Transferable, not \(v.typeName)"))
                return view
            }
            documents.append(d)
        }
        let type = types.first ?? documents.first?.contentType ?? .data
        if many {
            return AnyView(view.fileExporter(isPresented: shown, documents: documents, contentType: type, onCompletion: several))
        }
        return AnyView(view.fileExporter(isPresented: shown, document: documents.first, contentTypes: types.isEmpty ? [type] : types,
                                         defaultFilename: filename, onCompletion: one, onCancellation: cancel))
    }

    /// A value the exporter writes: the app's document, or bytes.
    @MainActor static func exportDocument(_ v: KV, _ type: UTType?, _ c: KCall) -> KExportDocument? {
        if let doc = KFileDocuments.document(for: v, c.interp), let app = doc.app {
            let declared = KFileDocuments.writableContentTypes(app.type, c.interp)
            return KExportDocument(source: .app(doc), contentType: type ?? declared.first ?? .data)
        }
        switch v {
        case .string(let s):
            return KExportDocument(source: .data(Data(s.utf8)), contentType: type ?? .plainText)
        case .native(.object("Data", _)):
            return KBuiltins.dataValue(v).map { KExportDocument(source: .data($0), contentType: type ?? .data) }
        case .native(.url(let u)):
            guard let file = try? c.context.resolveFile(u), let data = try? Data(contentsOf: file) else { return nil }
            return KExportDocument(source: .data(data), contentType: type ?? UTType(filenameExtension: u.pathExtension) ?? .data)
        default:
            #if canImport(UIKit)
            if case .native(.object("UIImage", let ref)) = v, let image = ref.value as? UIImage {
                let jpeg = type?.conforms(to: .jpeg) == true
                return (jpeg ? image.jpegData(compressionQuality: 0.9) : image.pngData()).map { KExportDocument(source: .data($0), contentType: type ?? .png) }
            }
            #endif
            return nil
        }
    }

    // MARK: fileMover

    static func mover(_ r: KRegistry) {
        r.modifier("fileMover", .files, notes: "Moves files out of the app's folder to where the person puts them.") { m in
            m.forms(["isPresented:binding file:any onCompletion:closure", "isPresented:binding files:any onCompletion:closure",
                     "isPresented:binding file:any onCompletion:closure onCancellation:closure",
                     "isPresented:binding files:any onCompletion:closure onCancellation:closure"]) { c, view in
                fileMover(c, view)
            }
            m.probe { _, args, interp in
                var calls: [KProbeCall] = []
                if case .function(let f)? = args["onCompletion"] {
                    let out = interp.context.files.temporary.appending(path: "Moved")
                    calls.append(KProbeCall(fn: f, args: [success(args["files"] != nil ? .array([url(out)]) : url(out), interp)], use: .action))
                }
                if case .function(let f)? = args["onCancellation"] { calls.append(KProbeCall(fn: f, use: .action)) }
                return calls
            }
        }
    }

    @MainActor static func fileMover(_ c: KCall, _ view: AnyView) -> AnyView {
        guard let b = c.kbinding("isPresented"), let done = c.function("onCompletion") else { return view }
        let interp = c.interp, context = c.context
        let shown = c.r.boolBinding(b)
        let cancel = c.function("onCancellation")
        @MainActor func file(_ v: KV) -> URL? {
            guard case .native(.url(let u)) = v else { return nil }
            do { return try context.resolveFile(u) } catch {
                interp.report(c.fail((error as? KilnFiles.Refusal)?.description ?? "\(error)"))
                return nil
            }
        }
        if c.has("files") {
            let files = ((try? interp.sequence(c["files"] ?? .array([]))) ?? []).compactMap(file)
            let completion: (Result<[URL], Error>) -> Void = { result in
                switch result {
                case .success(let us):
                    let grants = KFileGrants.of(context)
                    us.forEach(grants.grant)
                    interp.perform(done, [success(.array(us.map(url)), interp)])
                case .failure(let error): interp.perform(done, [failure(error, interp)])
                }
            }
            if let cancel { return AnyView(view.fileMover(isPresented: shown, files: files, onCompletion: completion, onCancellation: { interp.perform(cancel) })) }
            return AnyView(view.fileMover(isPresented: shown, files: files, onCompletion: completion))
        }
        let one = c["file"].flatMap(file)
        let completion: (Result<URL, Error>) -> Void = { result in
            switch result {
            case .success(let u): KFileGrants.of(context).grant(u); interp.perform(done, [success(url(u), interp)])
            case .failure(let error): interp.perform(done, [failure(error, interp)])
            }
        }
        if let cancel { return AnyView(view.fileMover(isPresented: shown, file: one, onCompletion: completion, onCancellation: { interp.perform(cancel) })) }
        return AnyView(view.fileMover(isPresented: shown, file: one, onCompletion: completion))
    }

    // MARK: The pickers' own modifiers

    static func dialogs(_ r: KRegistry) {
        @MainActor func text(_ c: KCall) -> Text? {
            guard let v = c[0], !v.isNil else { return nil }
            return KShare.text(v, c)
        }
        r.modifier("fileDialogMessage", .files) { m in
            m.form("_:any") { c, view in view.fileDialogMessage(text(c)) }
        }
        r.modifier("fileDialogConfirmationLabel", .files) { m in
            m.form("_:any") { c, view in view.fileDialogConfirmationLabel(text(c)) }
        }
        r.modifier("fileExporterFilenameLabel", .files) { m in
            m.form("_:any") { c, view in view.fileExporterFilenameLabel(text(c)) }
        }
        r.modifier("fileDialogCustomizationID", .files) { m in
            m.form("_:string") { c, view in view.fileDialogCustomizationID(c.string(0) ?? "") }
        }
        r.modifier("fileDialogImportsUnresolvedAliases", .files) { m in
            m.form("_:bool") { c, view in view.fileDialogImportsUnresolvedAliases(c.bool(0, default: false)) }
        }
        r.modifier("fileDialogDefaultDirectory", .files, notes: "A folder in the app's own folder, or one the person picked.") { m in
            m.form("_:URL?") { c, view in
                let dir: URL? = {
                    guard case .native(.url(let u))? = c[0] else { return nil }
                    do { return try c.context.resolveFile(u) } catch {
                        c.interp.report(c.fail((error as? KilnFiles.Refusal)?.description ?? "\(error)"))
                        return nil
                    }
                }()
                view.fileDialogDefaultDirectory(dir)
            }
        }
        r.modifier("fileDialogBrowserOptions", .files) { m in
            m.form("_:FileDialogBrowserOptions") { c, view in view.fileDialogBrowserOptions(browserOptions(c[0], c.interp)) }
        }
        r.type("FileDialogBrowserOptions", .files, support: .full) { t in
            t.internal()
            for n in ["enumeratePackages", "includeHiddenFiles", "displayFileExtensions"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }
    }

    @MainActor static func browserOptions(_ v: KV?, _ interp: KInterpreter) -> FileDialogBrowserOptions {
        let names: [String] = {
            if case .native(.implicit(let n, _))? = v { return [n] }
            return ((try? interp.sequence(v ?? .array([]))) ?? []).compactMap { if case .native(.implicit(let n, _)) = $0 { return n }; return nil }
        }()
        var options: FileDialogBrowserOptions = []
        for n in names {
            switch n {
            case "enumeratePackages": options.insert(.enumeratePackages)
            case "includeHiddenFiles": options.insert(.includeHiddenFiles)
            case "displayFileExtensions": options.insert(.displayFileExtensions)
            default: break
            }
        }
        return options
    }

    // MARK: Quick Look

    static func quickLook(_ r: KRegistry) {
        r.modifier("quickLookPreview", .files, notes: "A file in the app's folder (or one the person picked); `$url`, or `$selection, in: urls`.") { m in
            m.form("_:binding") { c, view in
                #if canImport(QuickLook) && !os(tvOS)
                if let b = c.kbinding(0) {
                    AnyView(view.quickLookPreview(previewBinding(b, c)))
                } else {
                    view
                }
                #else
                view
                #endif
            }
            m.form("_:binding in:any") { c, view in
                #if canImport(QuickLook) && !os(tvOS)
                if let b = c.kbinding(0) {
                    AnyView(view.quickLookPreview(previewBinding(b, c), in: ((try? c.interp.sequence(c["in"] ?? .array([]))) ?? []).compactMap { previewable($0, c) }))
                } else {
                    view
                }
                #else
                view
                #endif
            }
        }
    }

    /// The URL to preview, or nil (and an error) for one outside the app's files.
    @MainActor static func previewable(_ v: KV, _ c: KCall) -> URL? {
        guard case .native(.url(let u)) = v else { return nil }
        if !u.isFileURL { return u }
        do { return try c.context.resolveFile(u) } catch {
            c.interp.report(c.fail((error as? KilnFiles.Refusal)?.description ?? "\(error)"))
            return nil
        }
    }

    /// The app's `URL?` binding, as Quick Look reads and clears it. The app
    /// gets back the URL it wrote, not the resolved one.
    @MainActor static func previewBinding(_ b: KBinding, _ c: KCall) -> Binding<URL?> {
        Binding(get: { previewable(b.get(), c) }, set: { new in
            if new == nil { b.set(.nilValue); return }
            if let new, case .native(.url(let old)) = b.get(), (try? c.context.resolveFile(old)) == new { return }
            b.set(new.map(url) ?? .nilValue)
        })
    }
}

/// What the exporter writes: the app's document through its proxy, or bytes
/// it made. One type, so a `documents:` array can mix them.
struct KExportDocument: FileDocument, @unchecked Sendable {
    enum Source {
        case app(KFileDocument)
        case data(Data)
    }
    let source: Source
    let contentType: UTType

    init(source: Source, contentType: UTType) {
        self.source = source
        self.contentType = contentType
        Self.lock.withLock { _ = Self.used.insert(contentType) }
    }

    static var readableContentTypes: [UTType] { [.data, .item, .content] }

    /// SwiftUI exports only in a type listed here exactly, so it lists every
    /// type Kiln knows and each one an app has exported (`UTType(exportedAs:)`).
    static var writableContentTypes: [UTType] {
        let used = lock.withLock { Self.used }
        return [.data, .item, .content] + FilesBridges.knownTypes.values.sorted { $0.identifier < $1.identifier } + used.sorted { $0.identifier < $1.identifier }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var used: Set<UTType> = []

    init(configuration: ReadConfiguration) throws {
        source = .data(configuration.file.regularFileContents ?? Data())
        contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        switch source {
        case .app(let doc): return try doc.fileWrapper(configuration: configuration)
        case .data(let data): return FileWrapper(regularFileWithContents: data)
        }
    }
}
