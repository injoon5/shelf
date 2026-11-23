// coverage: regenerate Packages/Kiln/COVERAGE.md and coverage.json.
//
//   Packages/Kiln/Tools/coverage.sh                 # usual
//   swift run --package-path Packages/Kiln/Tools/coverage coverage [--sdk PATH] [--manifest PATH] [--dry-run]

import CoverageKit
import Foundation

// This file is Packages/Kiln/Tools/coverage/Sources/coverage/main.swift.
let kilnRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

var options = Options(kilnRoot: kilnRoot)
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--sdk": options.sdkPath = args.isEmpty ? nil : args.removeFirst()
    case "--manifest": options.manifestPath = args.isEmpty ? nil : args.removeFirst()
    case "--kiln-root": if !args.isEmpty { options.kilnRoot = URL(fileURLWithPath: args.removeFirst()) }
    case "--dry-run": options.dryRun = true
    case "-h", "--help":
        print("""
        usage: coverage [--sdk PATH] [--manifest PATH] [--kiln-root PATH] [--dry-run]

        Reads the iOS SDK's SwiftUI interfaces and writes Packages/Kiln/COVERAGE.md and
        coverage.json. The manifest is --manifest, else Packages/Kiln/kiln-manifest.json
        (the registry's export; Tools/manifest.sh writes it).
        """)
        exit(0)
    default:
        FileHandle.standardError.write(Data("coverage: unknown argument \(a)\n".utf8))
        exit(2)
    }
}

do {
    let out = try Runner.run(options)
    let r = out.result
    for f in r.families where f.total > 0 {
        let round = f.round.map { "R\($0)" } ?? "--"
        print("  \(f.family.padding(toLength: 22, withPad: " ", startingAt: 0)) \(round)  \(f.supported)/\(f.total - f.wontDo) supported, \(f.missing) missing, \(f.wontDo) won't do")
    }
    let unsorted = r.entries.filter { $0.family == "Unsorted" && $0.status != .plumbing }.count
    if unsorted > 0 { print("  \(unsorted) symbols have no family: add rules to families.json.") }
    if !r.staleWontDo.isEmpty { print("  Won't-do entries matching nothing: \(r.staleWontDo.joined(separator: ", "))") }
    if !options.dryRun { print("Wrote COVERAGE.md and coverage.json (manifest: \(out.manifestPath)).") }
} catch {
    FileHandle.standardError.write(Data("coverage: \(error)\n".utf8))
    exit(1)
}
