// Finds the SDK's interfaces and the checked-in rules, picks the manifest, and
// writes the outputs.

import Foundation

public struct Options: Sendable {
    /// `Packages/Kiln`.
    public var kilnRoot: URL
    public var sdkPath: String?
    /// Use this manifest instead of the registry's.
    public var manifestPath: String?
    /// Don't write files; print the summary only.
    public var dryRun = false

    public init(kilnRoot: URL) { self.kilnRoot = kilnRoot }

    var toolDir: URL { kilnRoot.appendingPathComponent("Tools/coverage") }
    /// Where §1.4's registry writes its export.
    public var registryManifest: URL { kilnRoot.appendingPathComponent("kiln-manifest.json") }
}

public enum Runner {
    /// Overlays read besides SwiftUI, SwiftUICore and Charts.
    static func isOverlay(_ framework: String) -> Bool {
        framework.hasPrefix("_") && (framework.hasSuffix("_SwiftUI.framework") || framework.hasSuffix("_FoundationModels.framework"))
    }

    static func shell(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every interface to read, as (module, path), sorted by module.
    public static func interfaces(sdk: String) throws -> [(String, String)] {
        let fw = sdk + "/System/Library/Frameworks"
        let fm = FileManager.default
        let names = try fm.contentsOfDirectory(atPath: fw)
            .filter { ["SwiftUI.framework", "SwiftUICore.framework", "Charts.framework"].contains($0) || isOverlay($0) }
            .sorted()
        var out: [(String, String)] = []
        for n in names {
            let module = String(n.dropLast(".framework".count))
            let dir = "\(fw)/\(n)/Modules/\(module).swiftmodule"
            for arch in ["arm64e-apple-ios", "arm64-apple-ios"] {
                let p = "\(dir)/\(arch).swiftinterface"
                if fm.fileExists(atPath: p) { out.append((module, p)); break }
            }
        }
        guard out.contains(where: { $0.0 == "SwiftUI" }) else {
            throw CoverageError("No SwiftUI.swiftinterface under \(fw).")
        }
        return out
    }

    public struct Output {
        public var result: CoverageResult
        public var markdown: String
        public var json: Data
        public var manifestPath: String
    }

    public static func run(_ o: Options, log: (String) -> Void = { print($0) }) throws -> Output {
        guard let sdk = o.sdkPath ?? shell(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"]) else {
            throw CoverageError("Couldn't find the iOS SDK. Pass --sdk <path>.")
        }
        let sdkVersion = shell(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"]) ?? "?"
        let xcode = (shell(["xcodebuild", "-version"]) ?? "Xcode ?").replacingOccurrences(of: "\n", with: ", ")

        let found = try interfaces(sdk: sdk)
        var files: [InterfaceFile] = []
        for (module, path) in found {
            files.append(InterfaceParser.parse(try String(contentsOfFile: path, encoding: .utf8), module: module))
        }
        let catalog = Catalog.build(files)
        log("Read \(found.count) interfaces from iOS \(sdkVersion): \(catalog.symbols.count) symbols.")

        let families = try FamilyRules.load(o.toolDir.appendingPathComponent("families.json"))
        let wontDo = try WontDoList.load(o.toolDir.appendingPathComponent("wont-do.json"))

        let manifest: Manifest
        let manifestURL: URL
        if let p = o.manifestPath {
            manifestURL = URL(fileURLWithPath: p)
            manifest = try Manifest.load(manifestURL)
        } else if FileManager.default.fileExists(atPath: o.registryManifest.path) {
            manifestURL = o.registryManifest
            manifest = try Manifest.load(manifestURL)
        } else {
            throw CoverageError("No kiln-manifest.json: run Packages/Kiln/Tools/manifest.sh to export it from the bridge registry.")
        }
        let manifestPath = relativePath(manifestURL, to: o.kilnRoot)

        let result = Coverage.compute(catalog: catalog, manifest: manifest, families: families, wontDo: wontDo)
        let info = SDKInfo(sdkVersion: sdkVersion, xcode: xcode, interfaces: found.map(\.0))
        let md = Report.markdown(result, sdk: info, families: families, wontDo: wontDo, manifestPath: manifestPath)
        let json = try Report.json(result, sdk: info, manifestPath: manifestPath)
        if !o.dryRun {
            try Data((md + "\n").utf8).write(to: o.kilnRoot.appendingPathComponent("COVERAGE.md"))
            try json.write(to: o.kilnRoot.appendingPathComponent("coverage.json"))
        }
        return Output(result: result, markdown: md, json: json, manifestPath: manifestPath)
    }

    static func relativePath(_ url: URL, to root: URL) -> String {
        let p = url.standardizedFileURL.path
        let r = root.standardizedFileURL.path + "/"
        return p.hasPrefix(r) ? String(p.dropFirst(r.count)) : p
    }
}
