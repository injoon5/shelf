import Foundation
import Testing
@testable import CoverageKit

/// The SDK half of Kiln's call-forms audit: each parameter's flags.
@Suite struct CallFormsTests {
    func params(_ decl: String) -> [CallParam] {
        let file = InterfaceParser.parse("public struct V {\n  \(decl)\n}\n", module: "SwiftUI")
        return file.decls.first?.children.first?.params.map(CallParam.init) ?? []
    }

    @Test func closuresDefaultsAndBuilders() {
        let ps = params("public func sheet<Content>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View")
        #expect(ps.map(\.label) == ["isPresented", "onDismiss", "content"])
        #expect(ps.map(\.flags) == ["", "dft", "ftb"])
    }

    /// `@SliderTickBuilder<V> content:` is labeled `content`, not `V`.
    @Test func genericAttributes() {
        let ps = params("public init<V>(_ data: Data, @SliderTickBuilder<V> content: @escaping (Data.Element) -> Content)")
        #expect(ps.map(\.label) == ["_", "content"])
        #expect(ps[1].isBuilder && ps[1].isFunction)
    }

    @Test func valuesAndAttributesInTypes() {
        let ps = params("public func task(priority: TaskPriority = .userInitiated, @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void) -> some View")
        #expect(ps.map(\.flags) == ["d", "ft"])
        let auto = params("public func f(_ v: @autoclosure () -> Bool, _ any: Any, items: T...) -> some View")
        #expect(auto.map(\.flags) == ["a", "t", "v"])
    }
}
