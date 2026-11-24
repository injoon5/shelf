//
//  Files.swift
//  Bridges: `UTType`, `FileWrapper`, `URLResourceValues`, and the
//  `FileDocument` and `ReferenceFileDocument` proxies (PLAN.md §1.5, §4.1)
//
//  The pickers that use them are in Pickers.swift, drag and drop in
//  DragDrop.swift, and files the person picks for the app in Grants.swift.
//  An app's own files live in its folder (`KilnFiles`): they stay on the
//  device, and `DB` is what syncs.
//

import SwiftUI
import UniformTypeIdentifiers

@objc(KilnBridges_Files)
final class FilesBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        types(r)
        documents(r)
        pickers(r)
        dragAndDrop(r)
    }

    /// Every `UTType` static member Swift has, by name.
    static let knownTypes: [String: UTType] = [
        "ahap": .ahap, "aiff": .aiff, "arReferenceObject": .arReferenceObject, "avi": .avi,
        "aliasFile": .aliasFile, "appleArchive": .appleArchive, "appleProtectedMPEG4Audio": .appleProtectedMPEG4Audio, "appleProtectedMPEG4Video": .appleProtectedMPEG4Video,
        "appleScript": .appleScript, "application": .application, "applicationBundle": .applicationBundle, "applicationExtension": .applicationExtension,
        "archive": .archive, "assemblyLanguageSource": .assemblyLanguageSource, "audio": .audio, "audiovisualContent": .audiovisualContent,
        "bmp": .bmp, "bz2": .bz2, "binaryPropertyList": .binaryPropertyList, "bookmark": .bookmark,
        "bundle": .bundle, "cHeader": .cHeader, "cPlusPlusHeader": .cPlusPlusHeader, "cPlusPlusSource": .cPlusPlusSource,
        "css": named("public.css"), "cSource": .cSource, "calendarEvent": .calendarEvent, "commaSeparatedText": .commaSeparatedText,
        "compositeContent": .compositeContent, "contact": .contact, "content": .content, "dng": named("com.adobe.raw-image"),
        "data": .data, "database": .database, "delimitedText": .delimitedText, "directory": .directory,
        "diskImage": .diskImage, "epub": .epub, "exe": .exe, "exr": named("com.ilm.openexr-image"),
        "emailMessage": .emailMessage, "executable": .executable, "fileURL": .fileURL, "flatRTFD": .flatRTFD,
        "folder": .folder, "font": .font, "framework": .framework, "gif": .gif,
        "gzip": .gzip, "geoJSON": named("public.geojson"), "heic": .heic, "heics": named("public.heics"),
        "heif": .heif, "html": .html, "icns": .icns, "ico": .ico,
        "image": .image, "internetLocation": .internetLocation, "internetShortcut": .internetShortcut, "item": .item,
        "jpeg": .jpeg, "jpegxl": named("public.jpeg-xl"), "json": .json, "javaScript": .javaScript,
        "linkPresentationMetadata": named("com.apple.linkpresentation.metadata"), "livePhoto": .livePhoto, "log": .log, "m3uPlaylist": .m3uPlaylist,
        "midi": .midi, "mp3": .mp3, "mpeg": .mpeg, "mpeg2TransportStream": .mpeg2TransportStream,
        "mpeg2Video": .mpeg2Video, "mpeg4Audio": .mpeg4Audio, "mpeg4Movie": .mpeg4Movie, "makefile": .makefile,
        "markdown": named("net.daringfireball.markdown"), "message": .message, "mountPoint": .mountPoint, "movie": .movie,
        "osaScript": .osaScript, "osaScriptBundle": .osaScriptBundle, "objectiveCPlusPlusSource": .objectiveCPlusPlusSource, "objectiveCSource": .objectiveCSource,
        "pdf": .pdf, "phpScript": .phpScript, "pkcs12": .pkcs12, "png": .png,
        "package": .package, "perlScript": .perlScript, "plainText": .plainText, "playlist": .playlist,
        "pluginBundle": .pluginBundle, "presentation": .presentation, "propertyList": .propertyList, "pythonScript": .pythonScript,
        "quickLookGenerator": .quickLookGenerator, "quickTimeMovie": .quickTimeMovie, "rawImage": .rawImage, "rtf": .rtf,
        "rtfd": .rtfd, "realityFile": .realityFile, "resolvable": .resolvable, "rubyScript": .rubyScript,
        "svg": .svg, "sceneKitScene": .sceneKitScene, "script": .script, "shellScript": .shellScript,
        "sourceCode": .sourceCode, "spotlightImporter": .spotlightImporter, "spreadsheet": .spreadsheet, "swiftSource": .swiftSource,
        "symbolicLink": .symbolicLink, "systemPreferencesPane": .systemPreferencesPane, "tiff": .tiff, "tabSeparatedText": .tabSeparatedText,
        "tarArchive": named("public.tar-archive"), "text": .text, "toDoItem": .toDoItem, "url": .url,
        "urlBookmarkData": .urlBookmarkData, "usd": .usd, "usdz": .usdz, "utf16ExternalPlainText": .utf16ExternalPlainText,
        "utf16PlainText": .utf16PlainText, "utf8PlainText": .utf8PlainText, "utf8TabSeparatedText": .utf8TabSeparatedText, "unixExecutable": .unixExecutable,
        "vCard": .vCard, "video": .video, "volume": .volume, "wav": .wav,
        "webArchive": .webArchive, "webP": .webP, "x509Certificate": .x509Certificate, "xml": .xml,
        "xmlPropertyList": .xmlPropertyList, "xpcService": .xpcService, "yaml": .yaml, "zip": .zip,
    ]

    /// A type by identifier, for the members newer than Kiln's oldest OS.
    private static func named(_ id: String) -> UTType { UTType(id) ?? UTType(importedAs: id) }

    static func utType(_ t: UTType) -> KV { .native(.boxed(KBoxed("UTType", t))) }

    /// A `UTType` value: `.json`, `UTType.png`, `UTType(filenameExtension: "md")`.
    @MainActor static func utType(_ v: KV?) -> UTType? {
        switch v {
        case .native(.boxed(let b))?: return b.get(UTType.self)
        case .native(.implicit(let n, _))?: return knownTypes[n]
        case .string(let s)?: return UTType(s)
        default: return nil
        }
    }

    /// `[.plainText, .json]`, or one type.
    @MainActor static func utTypes(_ v: KV?, _ interp: KInterpreter) -> [UTType] {
        guard let v, !v.isNil else { return [] }
        if let one = utType(v) { return [one] }
        return ((try? interp.sequence(v)) ?? []).compactMap { utType($0) }
    }

    static func tagClass(_ name: String?) -> UTTagClass {
        name == "mimeType" ? .mimeType : .filenameExtension
    }

    static func types(_ r: KRegistry) {
        r.type("UTType", .files, support: .full,
               notes: "Every static type (`.plainText`, `.json`, `.png`, `.pdf`, `.movie`…), `UTType(filenameExtension:)`, `UTType(mimeType:)`, `conforms(to:)`, `preferredFilenameExtension`.") { t in
            for (name, type) in knownTypes { t.staticProperty(name) { _ in utType(type) } }
            t.implicit { name, _, _ in knownTypes[name].map(utType) }
            @MainActor func opt(_ u: UTType?) -> KV { u.map(utType) ?? .nilValue }
            @MainActor func conforming(_ c: KCall) -> UTType { utType(c["conformingTo"]) ?? .data }
            t.initializer("_:string") { c in opt(UTType(c.string(0) ?? "")) }
            t.initializer("filenameExtension:string") { c in opt(UTType(filenameExtension: c.string("filenameExtension") ?? "")) }
            t.initializer("filenameExtension:string conformingTo:UTType") { c in
                opt(UTType(filenameExtension: c.string("filenameExtension") ?? "", conformingTo: conforming(c)))
            }
            t.initializer("mimeType:string") { c in opt(UTType(mimeType: c.string("mimeType") ?? "")) }
            t.initializer("mimeType:string conformingTo:UTType") { c in opt(UTType(mimeType: c.string("mimeType") ?? "", conformingTo: conforming(c))) }
            t.initializer("tag:string tagClass:UTTagClass conformingTo:UTType?") { c in
                opt(UTType(tag: c.string("tag") ?? "", tagClass: tagClass(c.symbol("tagClass")), conformingTo: utType(c["conformingTo"])))
            }
            t.initializer("exportedAs:string") { c in utType(UTType(exportedAs: c.string("exportedAs") ?? "public.data")) }
            t.initializer("exportedAs:string conformingTo:UTType") { c in utType(UTType(exportedAs: c.string("exportedAs") ?? "public.data", conformingTo: utType(c["conformingTo"]))) }
            t.initializer("importedAs:string") { c in utType(UTType(importedAs: c.string("importedAs") ?? "public.data")) }
            t.initializer("importedAs:string conformingTo:UTType") { c in utType(UTType(importedAs: c.string("importedAs") ?? "public.data", conformingTo: utType(c["conformingTo"]))) }
            t.staticMethod("types", "tag:string tagClass:UTTagClass conformingTo:UTType?") { c in
                .array(UTType.types(tag: c.string("tag") ?? "", tagClass: tagClass(c.symbol("tagClass")), conformingTo: utType(c["conformingTo"])).map(utType))
            }
            @MainActor func me(_ c: KCall) -> UTType? { utType(c.receiver) }
            t.property("identifier") { c in .string(me(c)?.identifier ?? "") }
            t.property("preferredFilenameExtension") { c in me(c)?.preferredFilenameExtension.map(KV.string) ?? .nilValue }
            t.property("preferredMIMEType") { c in me(c)?.preferredMIMEType.map(KV.string) ?? .nilValue }
            t.property("localizedDescription") { c in me(c)?.localizedDescription.map(KV.string) ?? .nilValue }
            t.property("description") { c in .string(me(c)?.identifier ?? "") }
            t.property("isDeclared") { c in .bool(me(c)?.isDeclared ?? false) }
            t.property("isDynamic") { c in .bool(me(c)?.isDynamic ?? false) }
            t.property("isPublic") { c in .bool(me(c)?.isPublic ?? false) }
            t.property("referenceURL") { c in me(c)?.referenceURL.map { .native(.url($0)) } ?? .nilValue }
            t.property("version") { c in me(c)?.version.map(KV.int) ?? .nilValue }
            t.property("supertypes") { c in .array((me(c)?.supertypes ?? []).sorted { $0.identifier < $1.identifier }.map(utType)) }
            t.property("tags") { c in
                var out: [KV: KV] = [:]
                for (k, v) in me(c)?.tags ?? [:] { out[.native(.implicit(k == .mimeType ? "mimeType" : "filenameExtension", []))] = .array(v.map(KV.string)) }
                return .dict(out)
            }
            for name in ["conforms", "isSubtype", "isSupertype"] {
                let label = name == "conforms" ? "to" : "of"
                t.method(name, "\(label):UTType") { c in
                    guard let a = me(c), let b = utType(c.args[0]) else { return .bool(false) }
                    switch name {
                    case "isSubtype": return .bool(a.isSubtype(of: b))
                    case "isSupertype": return .bool(a.isSupertype(of: b))
                    default: return .bool(a.conforms(to: b))
                    }
                }
            }
        }
        r.type("UTTagClass", .files, support: .full) { t in
            t.staticProperties(["filenameExtension": .native(.implicit("filenameExtension", [])), "mimeType": .native(.implicit("mimeType", []))])
        }
        r.type("FileWrapper", .files, support: .full) { t in
            t.initializer("regularFileWithContents:Data") { c in
                .native(.object("FileWrapper", KRef(FileWrapper(regularFileWithContents: KBuiltins.dataValue(c.args[0]) ?? Data()))))
            }
            t.initializer("directoryWithFileWrappers:any") { c in
                var children: [String: FileWrapper] = [:]
                if case .dict(let d)? = c["directoryWithFileWrappers"] {
                    for (k, v) in d { if let name = k.asString, let w = KCall.objectValue(v) as? FileWrapper { children[name] = w } }
                }
                return .native(.object("FileWrapper", KRef(FileWrapper(directoryWithFileWrappers: children))))
            }
            t.property("regularFileContents") { c in c.object(FileWrapper.self)?.regularFileContents.map(KBuiltins.data) ?? .nilValue }
            t.property("isRegularFile") { c in .bool(c.object(FileWrapper.self)?.isRegularFile ?? false) }
            t.property("isDirectory") { c in .bool(c.object(FileWrapper.self)?.isDirectory ?? false) }
            t.property("fileWrappers") { c in
                guard let children = c.object(FileWrapper.self)?.fileWrappers else { return .nilValue }
                var out: [KV: KV] = [:]
                for (k, v) in children { out[.string(k)] = .native(.object("FileWrapper", KRef(v))) }
                return .dict(out)
            }
            t.property("preferredFilename", { c in c.object(FileWrapper.self)?.preferredFilename.map(KV.string) ?? .nilValue },
                       set: { c in c.object(FileWrapper.self)?.preferredFilename = c.string(0) })
            t.property("filename") { c in c.object(FileWrapper.self)?.filename.map(KV.string) ?? .nilValue }
            t.method("addRegularFile", "withContents:Data preferredFilename:string") { c in
                let name = c.object(FileWrapper.self)?.addRegularFile(withContents: KBuiltins.dataValue(c["withContents"]) ?? Data(),
                                                                     preferredFilename: c.string("preferredFilename") ?? "file")
                return .string(name ?? "")
            }
        }
        r.nativeClass(FileWrapper.self, "FileWrapper")
        resourceValues(r)
    }

    static func documents(_ r: KRegistry) {
        r.protocolBridge("FileDocument", .files,
                         requirements: ["static readableContentTypes", "init(configuration:)", "fileWrapper(configuration:)", "static writableContentTypes?"],
                         support: .full,
                         notes: "For `.fileExporter(isPresented:document:contentType:)` and `.fileImporter`: `init(configuration:)` reads `configuration.file.regularFileContents`.") { app in
            KFileDocument(app: app)
        }
        r.protocolBridge("ReferenceFileDocument", .files,
                         requirements: ["static readableContentTypes", "init(configuration:)", "snapshot(contentType:)", "fileWrapper(snapshot:configuration:)",
                                        "static writableContentTypes?"],
                         support: .full,
                         notes: "A class document: `snapshot(contentType:)`, then `fileWrapper(snapshot:configuration:)`.") { app in
            KFileDocument(app: app)
        }
        // `configuration` in `init(configuration:)` and `fileWrapper(configuration:)`.
        r.type("FileDocumentReadConfiguration", .files) { t in
            t.property("file") { c in config(c)?.file ?? .nilValue }
            t.property("contentType") { c in config(c)?.contentType ?? .nilValue }
        }
        r.type("FileDocumentWriteConfiguration", .files) { t in
            t.property("existingFile") { c in config(c)?.file ?? .nilValue }
            t.property("contentType") { c in config(c)?.contentType ?? .nilValue }
        }
    }

    @MainActor static func config(_ c: KCall) -> KFileConfiguration? {
        if case .native(.object(_, let ref)) = c.receiver { return ref.value as? KFileConfiguration }
        return nil
    }
}

/// `FileDocument`'s read and write configurations, as the app reads them.
final class KFileConfiguration {
    let contentType: KV
    let file: KV
    init(contentType: KV, file: KV) {
        self.contentType = contentType
        self.file = file
    }
}

/// The app's `FileDocument`, as SwiftUI's file exporter takes it. SwiftUI
/// writes documents off the main thread; the app's `fileWrapper` runs on it.
struct KFileDocument: FileDocument, @unchecked Sendable {
    let app: KAppValue?

    /// Anything: what the app's type reads is checked by the bridge that reads it.
    static var readableContentTypes: [UTType] { [.data, .item, .content] }

    init(app: KAppValue) { self.app = app }

    /// Only the app's own type can read itself (`KFileDocuments.read`), so a
    /// picker reading into this type (rather than the app's) fails.
    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let existing = configuration.existingFile
        let type = configuration.contentType
        return try KDelegates.onMain {
            guard let app else { throw CocoaError(.fileWriteUnknown) }
            return try KFileDocuments.wrapper(app, contentType: type, existing: existing)
        }
    }
}

/// What the file pickers call.
@MainActor
enum KFileDocuments {
    /// The native document for the app's value, if its type adopts
    /// `FileDocument` or `ReferenceFileDocument`.
    static func document(for v: KV, _ interp: KInterpreter) -> KFileDocument? {
        (interp.proxy(for: v, as: "FileDocument") ?? interp.proxy(for: v, as: "ReferenceFileDocument")) as? KFileDocument
    }

    static func isDocument(_ t: KType) -> Bool { t.conforms("FileDocument") || t.conforms("ReferenceFileDocument") }

    /// The content types the app's document type declares it reads.
    static func readableContentTypes(_ t: KType, _ interp: KInterpreter) -> [UTType] {
        let v = try? KAppValue(type: t, value: .type(.user(t)), interp).getStatic("readableContentTypes")
        return (v?.asArray ?? []).compactMap { FilesBridges.utType($0) }
    }

    /// The content types it writes: `writableContentTypes`, or what it reads.
    static func writableContentTypes(_ t: KType, _ interp: KInterpreter) -> [UTType] {
        let app = KAppValue(type: t, value: .type(.user(t)), interp)
        if let v = try? app.getStatic("writableContentTypes"), let types = v.asArray { return types.compactMap { FilesBridges.utType($0) } }
        return readableContentTypes(t, interp)
    }

    /// A new value of the app's document type, read from `data` with its `init(configuration:)`.
    static func read(_ t: KType, data: Data, contentType: UTType, _ interp: KInterpreter) throws -> KV {
        try read(t, wrapper: FileWrapper(regularFileWithContents: data), contentType: contentType, interp)
    }

    static func read(_ t: KType, wrapper: FileWrapper, contentType: UTType, _ interp: KInterpreter) throws -> KV {
        guard let i = (t.inits + t.extensionInits).first(where: { $0.params.map(\.label) == ["configuration"] }) else {
            throw interp.fail("'\(t.name)' has no init(configuration:)", t.line)
        }
        let config = KV.native(.object("FileDocumentReadConfiguration", KRef(KFileConfiguration(
            contentType: FilesBridges.utType(contentType), file: .native(.object("FileWrapper", KRef(wrapper)))))))
        return try interp.entry { try interp.instantiate(t, args: [config], labels: ["configuration"], line: i.line) }
    }

    /// The app's document written as a file wrapper: `fileWrapper(configuration:)`,
    /// or for a `ReferenceFileDocument` its snapshot, then `fileWrapper(snapshot:configuration:)`.
    static func wrapper(_ app: KAppValue, contentType: UTType, existing: FileWrapper?) throws -> FileWrapper {
        var a = app
        let config = KV.native(.object("FileDocumentWriteConfiguration", KRef(KFileConfiguration(
            contentType: FilesBridges.utType(contentType), file: existing.map { .native(.object("FileWrapper", KRef($0))) } ?? .nilValue))))
        let v: KV
        if a.type.conforms("ReferenceFileDocument") {
            let snapshot = try a.call("snapshot", [FilesBridges.utType(contentType)], labels: ["contentType"])
            v = try a.call("fileWrapper", [snapshot, config], labels: ["snapshot", "configuration"])
        } else {
            v = try a.call("fileWrapper", [config], labels: ["configuration"])
        }
        guard let wrapper = KCall.objectValue(v) as? FileWrapper else {
            let name = a.type.conforms("ReferenceFileDocument") ? "fileWrapper(snapshot:configuration:)" : "fileWrapper(configuration:)"
            throw a.interp.fail("\(a.type.name).\(name) must return a FileWrapper", a.type.line)
        }
        return wrapper
    }

    /// The bytes the app's document writes, as a file exporter would save them.
    static func data(of v: KV, contentType: UTType, _ interp: KInterpreter) throws -> Data {
        guard let app = KAppValue(v, interp) else { throw interp.fail("Not a document") }
        let wrapper = try wrapper(app, contentType: contentType, existing: nil)
        guard let data = wrapper.regularFileContents else {
            throw interp.fail("\(app.type.name)'s file wrapper has no contents", app.type.line)
        }
        return data
    }
}

// MARK: - URLResourceValues

/// What `url.resourceValues(forKeys:)` reads: every common key at once, from
/// a file in the app's folder or one the person picked.
final class KResourceValues {
    let values: URLResourceValues
    let name: String
    init(values: URLResourceValues, name: String) {
        self.values = values
        self.name = name
    }

    static let keys: Set<URLResourceKey> = [.nameKey, .fileSizeKey, .totalFileSizeKey, .fileAllocatedSizeKey, .isDirectoryKey,
                                            .isRegularFileKey, .creationDateKey, .contentModificationDateKey, .contentTypeKey,
                                            .localizedNameKey, .isHiddenKey]

    @MainActor static func read(_ file: URL, as url: URL) -> KV {
        let values = (try? file.resourceValues(forKeys: keys)) ?? URLResourceValues()
        return .native(.object("URLResourceValues", KRef(KResourceValues(values: values, name: url.lastPathComponent))))
    }
}

extension FilesBridges {
    static func resourceValues(_ r: KRegistry) {
        r.type("URLResourceValues", .files, support: .full,
               notes: "`fileSize`, `totalFileSize`, `isDirectory`, `creationDate`, `contentModificationDate`, `contentType`, `name`.") { t in
            @MainActor func v(_ c: KCall) -> KResourceValues? { KCall.objectValue(c.receiver) as? KResourceValues }
            func opt<T>(_ x: T?, _ make: (T) -> KV) -> KV { x.map(make) ?? .nilValue }
            t.property("name") { c in opt(v(c)?.values.name ?? v(c)?.name, KV.string) }
            t.property("localizedName") { c in opt(v(c)?.values.localizedName, KV.string) }
            t.property("fileSize") { c in opt(v(c)?.values.fileSize, KV.int) }
            t.property("totalFileSize") { c in opt(v(c)?.values.totalFileSize, KV.int) }
            t.property("fileAllocatedSize") { c in opt(v(c)?.values.fileAllocatedSize, KV.int) }
            t.property("isDirectory") { c in opt(v(c)?.values.isDirectory, KV.bool) }
            t.property("isRegularFile") { c in opt(v(c)?.values.isRegularFile, KV.bool) }
            t.property("isHidden") { c in opt(v(c)?.values.isHidden, KV.bool) }
            t.property("creationDate") { c in opt(v(c)?.values.creationDate) { .native(.date($0)) } }
            t.property("contentModificationDate") { c in opt(v(c)?.values.contentModificationDate) { .native(.date($0)) } }
            t.property("contentType") { c in opt(v(c)?.values.contentType, utType) }
        }
        r.type("URLResourceKey", .files, support: .full) { t in
            t.internal()
            for k in ["nameKey", "localizedNameKey", "fileSizeKey", "totalFileSizeKey", "fileAllocatedSizeKey", "isDirectoryKey", "isRegularFileKey",
                      "isHiddenKey", "creationDateKey", "contentModificationDateKey", "contentTypeKey"] {
                t.staticProperty(k) { _ in .native(.implicit(k, [])) }
            }
        }
    }
}

extension UTType: KDescribable {
    func describe(_ interp: KInterpreter) -> String { identifier }
}
