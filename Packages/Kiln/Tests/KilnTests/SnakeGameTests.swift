import XCTest
@testable import Kiln

// Regression tests for the constructs a real Qwen-generated snake game used that
// used to fail Kiln (from a Bond export that burned 30 build-loop iterations):
// custom init(), repeat-while, a PreviewProvider beside ContentView. (The full
// game drew with GameCanvas, which went with the original interpreter.)
@MainActor
final class SnakeGameTests: XCTestCase {

    func assertValid(_ name: String, _ src: String) {
        let v = Kiln.validate(src)
        XCTAssertTrue(v.hasView, "\(name): no view — errors=\(v.errors)")
        XCTAssertTrue(v.renderedContent, "\(name): rendered nothing")
        XCTAssertTrue(v.errors.isEmpty, "\(name): errors=\(v.errors)")
        XCTAssertTrue(v.warnings.isEmpty, "\(name): warnings=\(v.warnings)")
    }

    func report(_ name: String, _ src: String) { assertValid(name, src) }

    // Minimal: custom init() in the struct.
    func testInit() {
        report("init", """
        import SwiftUI
        struct ContentView: View {
            @State private var n = 0
            init() { n = 5 }
            var body: some View { Text("n \\(n)") }
        }
        """)
    }

    // Minimal: repeat-while loop.
    func testRepeatWhile() {
        report("repeat-while", """
        import SwiftUI
        struct ContentView: View {
            @State private var x = 0
            func setup() {
                var i = 0
                repeat { i += 1 } while i < 3
                x = i
            }
            var body: some View { Text("x \\(x)").onAppear { setup() } }
        }
        """)
    }

    // Minimal: PreviewProvider extra struct.
    func testPreviewProvider() {
        report("preview", """
        import SwiftUI
        struct ContentView: View {
            var body: some View { Text("hi") }
        }
        struct ContentView_Previews: PreviewProvider {
            static var previews: some View { ContentView() }
        }
        """)
    }

}
