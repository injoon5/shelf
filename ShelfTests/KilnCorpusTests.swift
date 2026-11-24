import Foundation
import Testing
@_spi(KilnTesting) @testable import Kiln

/// Kiln's Foundation and standard-library corpus (PLAN.md §3, Round 2C), on
/// iOS: what `CorpusTests` checks on the Mac, plus the entries marked `[ios]`
/// (UIKit's `UIDevice`, `UIFont`, `UIGraphicsImageRenderer`, `ImageRenderer.uiImage`),
/// which only run here. Each prints what compiled Swift prints.
@MainActor
@Suite(.serialized)
struct KilnCorpusTests {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../Packages/Kiln/Tests/Corpus").standardized

    @Test func everyEntryPrintsWhatSwiftPrintsOnTheSimulator() {
        let entries = KilnCorpus.load(Self.folder)
        #expect(entries.count > 600, "no corpus at \(Self.folder.path)")
        #expect(entries.contains { $0.flags.contains("ios") })
        var failures: [String] = []
        for e in entries where KilnCorpus.runsHere(e) {
            let got = KilnCorpus.run(e)
            if e.isGap { continue }
            if got != e.expected {
                failures.append("\(e.family).corpus:\(e.line) \(e.id)\n   want: \(e.expected.joined(separator: " ⏎ "))\n    got: \(got.joined(separator: " ⏎ "))")
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }
}
