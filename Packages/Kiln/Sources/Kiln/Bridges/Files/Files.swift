//
//  Files.swift
//  Bridges: `UTType`, `FileWrapper` and the `FileDocument` proxy (PLAN.md §1.5)
//
//  Round 3 (§4.1) adds the pickers: `.fileExporter(isPresented:document:…)`
//  takes `KFileDocuments.document(for:)`, the native `FileDocument` standing
//  for the app's, and `.fileImporter` reads files the app opens with
//  `KFileDocuments.read(_:data:contentType:)`. What's here is the proxy and
//  the values its requirements take.
//

import SwiftUI
import UniformTypeIdentifiers

@objc(KilnBridges_Files)
final class FilesBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        types(r)
        documents(r)
    }

    /// `UTType`'s static members Kiln knows by name.
    static let knownTypes: [String: UTType] = [
        "json": .json, "plainText": .plainText, "utf8PlainText": .utf8PlainText, "text": .text, "data": .data,
        "content": .content, "item": .item, "image": .image, "png": .png, "jpeg": .jpeg, "heic": .heic, "pdf": .pdf,
        "url": .url, "fileURL": .fileURL, "commaSeparatedText": .commaSeparatedText, "tabSeparatedText": .tabSeparatedText,
        "html": .html, "xml": .xml, "rtf": .rtf, "audio": .audio, "movie": .movie, "propertyList": .propertyList,
        "markdown": UTType("net.daringfireball.markdown") ?? .plainText, "folder": .folder, "zip": .zip,
    ]

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

    static func types(_ r: KRegistry) {
        r.type("UTType", .files, support: .partial) { t in
            for (name, type) in knownTypes { t.staticProperty(name) { _ in utType(type) } }
            t.implicit { name, _, _ in knownTypes[name].map(utType) }
            t.initializer("filenameExtension:string") { c in UTType(filenameExtension: c.string("filenameExtension") ?? "").map(utType) ?? .nilValue }
            t.initializer("_:string") { c in UTType(c.string(0) ?? "").map(utType) ?? .nilValue }
            t.initializer("exportedAs:string") { c in utType(UTType(exportedAs: c.string("exportedAs") ?? "public.data")) }
            t.initializer("importedAs:string") { c in utType(UTType(importedAs: c.string("importedAs") ?? "public.data")) }
            t.property("identifier") { c in .string(utType(c.receiver)?.identifier ?? "") }
            t.property("preferredFilenameExtension") { c in utType(c.receiver)?.preferredFilenameExtension.map(KV.string) ?? .nilValue }
            t.property("preferredMIMEType") { c in utType(c.receiver)?.preferredMIMEType.map(KV.string) ?? .nilValue }
            t.method("conforms", "to:UTType") { c in
                guard let a = utType(c.receiver), let b = utType(c.args[0]) else { return .bool(false) }
                return .bool(a.conforms(to: b))
            }
        }
        r.type("FileWrapper", .files, support: .partial) { t in
            t.initializer("regularFileWithContents:Data") { c in
                .native(.object("FileWrapper", KRef(FileWrapper(regularFileWithContents: KBuiltins.dataValue(c.args[0]) ?? Data()))))
            }
            t.property("regularFileContents") { c in c.object(FileWrapper.self)?.regularFileContents.map(KBuiltins.data) ?? .nilValue }
            t.property("isRegularFile") { c in .bool(c.object(FileWrapper.self)?.isRegularFile ?? false) }
            t.property("preferredFilename", { c in c.object(FileWrapper.self)?.preferredFilename.map(KV.string) ?? .nilValue },
                       set: { c in c.object(FileWrapper.self)?.preferredFilename = c.string(0) })
            t.property("filename") { c in c.object(FileWrapper.self)?.filename.map(KV.string) ?? .nilValue }
        }
        r.nativeClass(FileWrapper.self, "FileWrapper")
    }

    static func documents(_ r: KRegistry) {
        r.protocolBridge("FileDocument", .files,
                         requirements: ["static readableContentTypes", "init(configuration:)", "fileWrapper(configuration:)", "static writableContentTypes?"],
                         support: .partial,
                         notes: "Declared, for the file pickers to come; nothing shows it yet.") { app in
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
            guard var a = app else { throw CocoaError(.fileWriteUnknown) }
            let config = KV.native(.object("FileDocumentWriteConfiguration", KRef(KFileConfiguration(
                contentType: FilesBridges.utType(type), file: existing.map { .native(.object("FileWrapper", KRef($0))) } ?? .nilValue))))
            let v = try a.call("fileWrapper", [config], labels: ["configuration"])
            guard let wrapper = KCall.objectValue(v) as? FileWrapper else {
                throw a.interp.fail("\(a.type.name).fileWrapper(configuration:) must return a FileWrapper", a.type.line)
            }
            return wrapper
        }
    }
}

/// What the file pickers (Round 3) call.
@MainActor
enum KFileDocuments {
    /// The native document for the app's value, if its type adopts `FileDocument`.
    static func document(for v: KV, _ interp: KInterpreter) -> KFileDocument? {
        interp.proxy(for: v, as: "FileDocument") as? KFileDocument
    }

    /// The content types the app's document type declares it reads.
    static func readableContentTypes(_ t: KType, _ interp: KInterpreter) -> [UTType] {
        let v = try? KAppValue(type: t, value: .type(.user(t)), interp).getStatic("readableContentTypes")
        return (v?.asArray ?? []).compactMap { FilesBridges.utType($0) }
    }

    /// A new value of the app's document type, read from `data` with its `init(configuration:)`.
    static func read(_ t: KType, data: Data, contentType: UTType, _ interp: KInterpreter) throws -> KV {
        guard let i = (t.inits + t.extensionInits).first(where: { $0.params.map(\.label) == ["configuration"] }) else {
            throw interp.fail("'\(t.name)' has no init(configuration:)", t.line)
        }
        let config = KV.native(.object("FileDocumentReadConfiguration", KRef(KFileConfiguration(
            contentType: FilesBridges.utType(contentType), file: .native(.object("FileWrapper", KRef(FileWrapper(regularFileWithContents: data))))))))
        return try interp.entry { try interp.instantiate(t, args: [config], labels: ["configuration"], line: i.line) }
    }

    /// The bytes the app's document writes, as a file exporter would save them.
    static func data(of v: KV, contentType: UTType, _ interp: KInterpreter) throws -> Data {
        guard var app = KAppValue(v, interp) else { throw interp.fail("Not a document") }
        let config = KV.native(.object("FileDocumentWriteConfiguration", KRef(KFileConfiguration(contentType: FilesBridges.utType(contentType), file: .nilValue))))
        let w = try app.call("fileWrapper", [config], labels: ["configuration"])
        guard let wrapper = KCall.objectValue(w) as? FileWrapper, let data = wrapper.regularFileContents else {
            throw interp.fail("\(app.type.name).fileWrapper(configuration:) must return a FileWrapper with contents", app.type.line)
        }
        return data
    }
}
