import XCTest
import SwiftUI
@_spi(KilnTesting) @testable import Kiln

/// The Foundation and standard-library corpus (PLAN.md §3, Round 2C;
/// `Tests/Corpus`, `KilnCorpus`): every entry prints what compiled Swift
/// prints. A `[gap]` entry must still fail (when it passes, drop the flag).
/// `[ios]` entries need UIKit: Shelf's `KilnCorpusTests` runs them on the simulator.
@MainActor
final class CorpusTests: XCTestCase {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Corpus").standardized

    func testEveryEntryPrintsWhatSwiftPrints() {
        let entries = KilnCorpus.load(Self.folder)
        XCTAssertGreaterThan(entries.count, 600)
        var failures: [String] = []
        for e in entries where KilnCorpus.runsHere(e) {
            let got = KilnCorpus.run(e)
            if e.isGap {
                if got == e.expected { failures.append("\(e.family).corpus:\(e.line) \(e.id) passes now: drop its [gap]") }
                continue
            }
            if got != e.expected {
                failures.append("\(e.family).corpus:\(e.line) \(e.id)\n   want: \(e.expected.joined(separator: " ⏎ "))\n    got: \(got.joined(separator: " ⏎ "))")
            }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    func testEntriesHaveValuesAndUniqueIDs() {
        let entries = KilnCorpus.load(Self.folder)
        var seen = Set<String>()
        for e in entries {
            XCTAssertFalse(e.expected.isEmpty, "\(e.family).corpus:\(e.line) \(e.id) has no `=>` value: run Tools/corpus/oracle.py --write")
            XCTAssertTrue(seen.insert(e.family + "/" + e.id).inserted, "\(e.family).corpus:\(e.line) repeats the id \(e.id)")
        }
    }

    func testTheFormatParses() {
        let entries = KilnCorpus.parse("""
            prelude ::
                let x = 2
            ## Things
            one :: x + 1 => 3
            two [gap] [ios] ::
                print(x)
                print(x * 2)
            => 2
            => 4
            """, family: "Test")
        XCTAssertEqual(entries.map(\.id), ["one", "two"])
        XCTAssertEqual(entries[0].code, "let x = 2\nprint(x + 1)")
        XCTAssertEqual(entries[0].expected, ["3"])
        XCTAssertEqual(entries[1].flags, ["gap", "ios"])
        XCTAssertEqual(entries[1].expected, ["2", "4"])
        XCTAssertEqual(entries[1].section, "Things")
    }
}
