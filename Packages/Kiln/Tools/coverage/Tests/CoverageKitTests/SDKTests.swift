// Runs against this Mac's iOS SDK when there is one: the "done when" spot checks.

import Foundation
import Testing
@testable import CoverageKit

@Suite struct SDKTests {
    static let sdk: String? = Runner.shell(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"])

    static func catalog() throws -> Catalog? {
        guard let sdk else { return nil }
        let files = try Runner.interfaces(sdk: sdk).map { module, path in
            InterfaceParser.parse(try String(contentsOfFile: path, encoding: .utf8), module: module)
        }
        return Catalog.build(files)
    }

    @Test(.enabled(if: SDKTests.sdk != nil)) func knownSymbolsAreFound() throws {
        let c = try #require(try SDKTests.catalog())
        let known: [(String, String?)] = [
            ("view:DatePicker", "13.0"), ("view:MultiDatePicker", "16.0"), ("view:NavigationSplitView", "16.0"),
            ("view:ViewThatFits", "16.0"), ("view:WebView", "26.0"), ("view:PhotosPicker", "16.0"), ("view:Chart", "16.0"),
            ("view:GlassEffectContainer", "26.0"), ("content:ToolbarSpacer", "26.0"), ("content:Tab", "18.0"),
            ("content:BarMark", "16.0"), ("gesture:MagnifyGesture", "17.0"), ("modifier:padding", "13.0"),
            ("modifier:swipeActions", "15.0"), ("modifier:swipeActionsContainer", "27.0"), ("modifier:reorderable", "27.0"),
            ("modifier:reorderContainer", "27.0"), ("modifier:ToolbarContent.visibilityPriority", "27.0"),
            ("modifier:glassEffect", "26.0"), ("modifier:sensoryFeedback", "17.0"), ("modifier:containerRelativeFrame", "17.0"),
            ("modifier:Gesture.updating", "13.0"), ("style:ButtonStyle.borderedProminent", "15.0"),
            ("style:ButtonStyle.glass", "26.0"), ("style:DatePickerStyle.graphical", "14.0"), ("style:PickerStyle.palette", "17.0"),
            ("member:Animation.spring", "13.0"), ("environment:dismiss", "15.0"), ("wrapper:State", "13.0"),
        ]
        for (id, version) in known {
            let s = c.symbol(id)
            #expect(s != nil, "\(id) is missing")
            #expect(s?.introduced == version, "\(id): \(s?.introduced ?? "nil")")
        }
        let modifiers = c.symbols.filter { $0.kind == .modifier }.count
        #expect(modifiers > 500, "SwiftUI has hundreds of modifiers; found \(modifiers)")
        // macOS-only API is dropped.
        #expect(c.symbol("view:HSplitView") == nil)
        #expect(c.symbol("modifier:Scene.windowStyle") == nil)
    }
}
