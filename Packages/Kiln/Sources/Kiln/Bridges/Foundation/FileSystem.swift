//
//  FileSystem.swift
//  Bridges: Foundation's file system, inside the app's folder
//
//  `URL.documentsDirectory` and the other directories, `FileManager`, and
//  reading and writing `Data` and `String`, all resolved into the run's
//  folder (`KilnContext.files`, PLAN.md §1.7). A path that leaves the folder
//  is an error with the app's line. The pickers (`.fileImporter` and the
//  rest) are §4.1's, in Files.
//

import Foundation

extension FoundationBridges {
    static func fileSystem(_ r: KRegistry) {
        urls(r)
        fileManager(r)
        dataAndText(r)
    }

    // MARK: Resolving

    /// A file URL in the app's folder, or an error naming the path.
    @MainActor static func file(_ c: KCall, _ ref: KArgRef) throws -> URL {
        guard let v = c[ref], !v.isNil else { throw c.fail("\(ref.description) is missing") }
        do {
            switch v {
            case .native(.url(let u)): return try c.context.resolveFile(u)
            case .string(let s): return try c.context.resolveFile(s.hasPrefix("/") ? URL(fileURLWithPath: s) : c.context.files.root.appending(path: s))
            default: throw c.fail("\(ref.description) should be a file URL, not \(v.typeName)")
            }
        } catch let refusal as KilnFiles.Refusal {
            throw c.fail(refusal.description)
        }
    }

    /// A Foundation error as the app's code catches it, with the folder's
    /// real place on the device left out.
    @MainActor static func thrown(_ error: Error, _ c: KCall) -> KEThrown {
        var message = (error as NSError).localizedDescription
        let root = KilnFiles.real(c.context.files.root).path(percentEncoded: false)
        message = message.replacingOccurrences(of: root, with: "").replacingOccurrences(of: c.context.files.root.path(percentEncoded: false), with: "")
        return KEThrown(value: KBuiltins.errorValue(message))
    }

    @MainActor static func directory(_ name: String, _ c: KCall) throws -> URL {
        let files = c.context.files
        switch name {
        case "documentDirectory", "documentsDirectory": return files.documents
        case "applicationSupportDirectory": return files.applicationSupport
        case "cachesDirectory": return files.caches
        case "temporaryDirectory", "itemReplacementDirectory": return files.temporary
        case "homeDirectory", "userDirectory": return files.home
        default: throw c.fail("Kiln has no .\(name): an app has its documents, application support, caches and temporary folders")
        }
    }

    // MARK: URL

    static func urls(_ r: KRegistry) {
        r.extend("URL") { t in
            for name in ["documentsDirectory", "applicationSupportDirectory", "cachesDirectory", "temporaryDirectory", "homeDirectory"] {
                t.staticProperty(name, notes: "In the app's own folder.") { c in .native(.url(try directory(name, c))) }
            }
            @MainActor func u(_ c: KCall) -> URL? { if case .native(.url(let u)) = c.receiver { return u }; return nil }
            func url(_ x: URL?) -> KV { x.map { .native(.url($0)) } ?? .nilValue }
            t.method("appendingPathComponent", "_:string isDirectory:bool?") { c in
                guard let base = u(c), let part = c.string(0) else { return .nilValue }
                return url(base.appendingPathComponent(part, isDirectory: c.bool("isDirectory", default: false)))
            }
            t.method("appending", "path:string directoryHint:any?") { c in
                guard let base = u(c), let part = c.string("path") else { return .nilValue }
                return url(base.appending(path: part))
            }
            t.method("appending", "component:string directoryHint:any?") { c in
                guard let base = u(c), let part = c.string("component") else { return .nilValue }
                return url(base.appending(component: part))
            }
            t.method("appendingPathExtension", "_:string") { c in url(u(c)?.appendingPathExtension(c.string(0) ?? "")) }
            t.method("deletingLastPathComponent", "") { c in url(u(c)?.deletingLastPathComponent()) }
            t.method("deletingPathExtension", "") { c in url(u(c)?.deletingPathExtension()) }
            t.method("path", "percentEncoded:bool?") { c in .string(u(c)?.path(percentEncoded: c.bool("percentEncoded", default: true)) ?? "") }
            t.property("path") { c in .string(u(c)?.path ?? "") }
            t.property("relativePath") { c in .string(u(c)?.relativePath ?? "") }
            t.property("pathExtension") { c in .string(u(c)?.pathExtension ?? "") }
            t.property("pathComponents") { c in .array((u(c)?.pathComponents ?? []).map { .string($0) }) }
            t.property("isFileURL") { c in .bool(u(c)?.isFileURL ?? false) }
            t.property("scheme") { c in u(c)?.scheme.map { .string($0) } ?? .nilValue }
            t.property("standardizedFileURL") { c in url(u(c)?.standardizedFileURL) }
            t.property("hasDirectoryPath") { c in .bool(u(c)?.hasDirectoryPath ?? false) }
            // A picked file's (Files/Grants.swift): Kiln started its access when the
            // picker handed it over, and stops it when the app closes.
            t.method("startAccessingSecurityScopedResource", "") { c in
                guard let url = u(c) else { return .bool(false) }
                return .bool(c.context.provided(KFileGrants.self)?.allows(url) != nil)
            }
            t.method("stopAccessingSecurityScopedResource", "") { _ in .void }
            t.method("resourceValues", "forKeys:any") { c in
                guard let url = u(c) else { return .nilValue }
                let file = try file(c, .receiver)
                return KResourceValues.read(file, as: url)
            }
        }
    }

    // MARK: FileManager

    static func fileManager(_ r: KRegistry) {
        r.type("FileManager", .foundation, notes: "Inside the app's own folder; a path that leaves it is an error.") { t in
            t.staticProperty("default") { _ in .native(.object("FileManager", KRef(FileManager.default))) }
            t.property("temporaryDirectory") { c in .native(.url(c.context.files.temporary)) }

            t.method("urls", "for:any in:any") { c in
                guard let name = c.symbol("for") else { throw c.fail("needs a directory, such as .documentDirectory") }
                return .array([.native(.url(try directory(name, c)))])
            }
            t.method("url", "for:any in:any appropriateFor:any? create:bool?") { c in
                guard let name = c.symbol("for") else { throw c.fail("needs a directory, such as .documentDirectory") }
                return .native(.url(try directory(name, c)))
            }
            t.method("fileExists", "atPath:string") { c in
                .bool(FileManager.default.fileExists(atPath: try file(c, "atPath").path(percentEncoded: false)))
            }
            t.method("contents", "atPath:string") { c in
                FileManager.default.contents(atPath: try file(c, "atPath").path(percentEncoded: false)).map { KBuiltins.data($0) } ?? .nilValue
            }
            t.method("createFile", "atPath:string contents:any? attributes:any?") { c in
                let at = try file(c, "atPath")
                let data = c["contents"].flatMap { KBuiltins.dataValue($0) }
                return .bool(FileManager.default.createFile(atPath: at.path(percentEncoded: false), contents: data))
            }
            t.method("createDirectory", "at:URL withIntermediateDirectories:bool attributes:any?") { c in
                let at = try file(c, "at")
                do { try FileManager.default.createDirectory(at: at, withIntermediateDirectories: c.bool("withIntermediateDirectories", default: false)) }
                catch { throw thrown(error, c) }
                return .void
            }
            t.method("createDirectory", "atPath:string withIntermediateDirectories:bool attributes:any?") { c in
                let at = try file(c, "atPath")
                do { try FileManager.default.createDirectory(at: at, withIntermediateDirectories: c.bool("withIntermediateDirectories", default: false)) }
                catch { throw thrown(error, c) }
                return .void
            }
            t.method("contentsOfDirectory", "at:URL includingPropertiesForKeys:any? options:any?") { c in
                let at = try file(c, "at")
                do {
                    let items = try FileManager.default.contentsOfDirectory(at: at, includingPropertiesForKeys: nil)
                    return .array(items.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { .native(.url($0)) })
                } catch { throw thrown(error, c) }
            }
            t.method("contentsOfDirectory", "atPath:string") { c in
                let at = try file(c, "atPath")
                do { return .array(try FileManager.default.contentsOfDirectory(atPath: at.path(percentEncoded: false)).sorted().map { .string($0) }) }
                catch { throw thrown(error, c) }
            }
            for (label, kind) in [("at", "URL"), ("atPath", "string")] {
                t.method("removeItem", "\(label):\(kind)") { c in
                    let at = try file(c, .label(label))
                    guard at != KilnFiles.real(c.context.files.root) else { throw c.fail("can't remove the app's own folder") }
                    do { try FileManager.default.removeItem(at: at) } catch { throw thrown(error, c) }
                    return .void
                }
            }
            for (from, to, kind) in [("at", "to", "URL"), ("atPath", "toPath", "string")] {
                t.method("copyItem", "\(from):\(kind) \(to):\(kind)") { c in
                    let a = try file(c, .label(from)), b = try file(c, .label(to))
                    do { try FileManager.default.copyItem(at: a, to: b) } catch { throw thrown(error, c) }
                    return .void
                }
                t.method("moveItem", "\(from):\(kind) \(to):\(kind)") { c in
                    let a = try file(c, .label(from)), b = try file(c, .label(to))
                    do { try FileManager.default.moveItem(at: a, to: b) } catch { throw thrown(error, c) }
                    return .void
                }
            }
            t.method("attributesOfItem", "atPath:string") { c in
                let at = try file(c, "atPath")
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: at.path(percentEncoded: false))
                    var out: [KV: KV] = [:]
                    if let size = attrs[.size] as? NSNumber { out[.string("size")] = .int(size.intValue) }
                    if let d = attrs[.modificationDate] as? Date { out[.string("modificationDate")] = .native(.date(d)) }
                    if let d = attrs[.creationDate] as? Date { out[.string("creationDate")] = .native(.date(d)) }
                    if let type = attrs[.type] as? FileAttributeType { out[.string("type")] = .string(type.rawValue) }
                    return .dict(out)
                } catch { throw thrown(error, c) }
            }
        }
    }

    // MARK: Data and String

    /// `Data(contentsOf: url)`: a file in the app's folder. Web addresses
    /// are read with `URLSession`, which doesn't hold up the screen.
    @MainActor static func dataContents(_ c: KCall) throws -> KV {
        let url = try file(c, "contentsOf")
        do { return KBuiltins.data(try Data(contentsOf: url)) } catch { throw thrown(error, c) }
    }

    /// `String(contentsOf: url, encoding:)` and `String(contentsOfFile:)`.
    @MainActor static func stringContents(_ c: KCall) throws -> KV {
        let url = try file(c, c.has("contentsOfFile") ? "contentsOfFile" : "contentsOf")
        do { return .string(try String(contentsOf: url, encoding: .utf8)) } catch { throw thrown(error, c) }
    }

    static func dataAndText(_ r: KRegistry) {
        r.extend("Data") { t in
            t.method("write", "to:URL options:any?") { c in
                guard let data = KBuiltins.dataValue(c.receiver) else { return .void }
                let to = try file(c, "to")
                do { try data.write(to: to, options: .atomic) } catch { throw thrown(error, c) }
                return .void
            }
        }
        r.extend("String") { t in
            t.method("write", "to:URL atomically:bool encoding:any") { c in
                let to = try file(c, "to")
                do { try (c.receiver.asString ?? "").write(to: to, atomically: true, encoding: .utf8) } catch { throw thrown(error, c) }
                return .void
            }
            t.method("write", "toFile:string atomically:bool encoding:any") { c in
                let to = try file(c, "toFile")
                do { try (c.receiver.asString ?? "").write(to: to, atomically: true, encoding: .utf8) } catch { throw thrown(error, c) }
                return .void
            }
        }
    }
}
