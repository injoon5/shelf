import XCTest
@testable import Kiln

// From a real 7B breakout: `for (i, x) in arr.enumerated()` (its GameCanvas
// cases went with the original interpreter).
@MainActor
final class BreakoutRepro: XCTestCase {

    // for (i, x) in arr.enumerated() must actually iterate (used for brick hits).
    func testEnumeratedLoop() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            @State private var total = 0
            @State private var nums = [10, 20, 30]
            var body: some View {
                Text("Total \\(total)")
                    .onAppear {
                        var sum = 0
                        for (i, n) in nums.enumerated() {
                            sum = sum + n + i
                        }
                        total = sum
                    }
            }
        }
        """
        let v = Kiln.validate(src)
        XCTAssertTrue(v.errors.isEmpty && v.warnings.isEmpty,
                      "enumerated loop should run clean: \(v.errors) \(v.warnings)")
    }

}
