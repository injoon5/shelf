import Foundation

/// The shape of an app's first screen, read cheaply from its source, for
/// the launch surface it opens on when there is no snapshot (plan §0.8):
/// what a native app's launch screen (`UILaunchScreen`) would declare.
///
/// It reads the root view's `body` (Kiln's root: `ContentView`, or the only
/// view no other uses) as text, never runs it, and looks at its outermost
/// views. Wrappers that add no background of their own are looked through:
/// a navigation container (which gives the screen its bar), a `TabView`
/// and its tabs, a `Group`. Whatever comes next is the screen's root: a
/// `List` or a `Form` sits on the grouped background, anything else on the
/// plain one. A guess for anything stranger, which is fine: the app replaces
/// it as soon as it is built.
struct LaunchLayout: Equatable, Sendable {
    /// The root is a `List` (in its default, inset grouped style) or a `Form`.
    var grouped = false
    /// The root is in a `NavigationStack`, `NavigationView` or
    /// `NavigationSplitView`.
    var navigationBar = false
    /// The app forces one appearance with `.preferredColorScheme`: true
    /// dark, false light, nil whatever the system's is.
    var dark: Bool?

    static let plain = LaunchLayout()

    init(grouped: Bool = false, navigationBar: Bool = false, dark: Bool? = nil) {
        self.grouped = grouped
        self.navigationBar = navigationBar
        self.dark = dark
    }

    init(source: String) {
        let text = SwiftText(source)
        let code = Code(text)
        guard let body = code.rootBody() else {
            self.init()
            return
        }
        var grouped = false, navigationBar = false
        for name in code.views(in: body) {
            if Self.navigation.contains(name) {
                navigationBar = true
            } else if Self.lookedThrough.contains(name) {
                continue
            } else {
                grouped = Self.groupedRoots.contains(name) && !code.contains(Self.plainListStyles, in: body)
                break
            }
        }
        var dark: Bool?
        if code.contains([".preferredColorScheme(.dark)"], in: 0..<code.scalars.count) { dark = true }
        if code.contains([".preferredColorScheme(.light)"], in: 0..<code.scalars.count) { dark = false }
        self.init(grouped: grouped, navigationBar: navigationBar, dark: dark)
    }

    private static let navigation: Set = ["NavigationStack", "NavigationView", "NavigationSplitView"]
    private static let lookedThrough: Set = ["TabView", "Tab", "Group"]
    private static let groupedRoots: Set = ["List", "Form"]
    /// List styles without the grouped background.
    private static let plainListStyles = [".listStyle(.plain)", ".listStyle(PlainListStyle())", ".listStyle(.inset)",
                                          ".listStyle(InsetListStyle())"]
}

/// The source with its comments and strings blanked out, and the few
/// questions `LaunchLayout` asks of it.
private struct Code {
    /// Every scalar of the source; comments and string literals are spaces.
    let scalars: [Unicode.Scalar]

    init(_ text: SwiftText) {
        scalars = text.scalars.indices.map { text.isCode($0) ? text.scalars[$0] : " " }
    }

    private var count: Int { scalars.count }

    /// The text between the braces of the root view's `body`.
    func rootBody() -> Range<Int>? {
        let views = viewStructs()
        let root = views.first { $0.name == "ContentView" }
            ?? views.first { view in views.allSatisfy { $0.name == view.name || !uses(view.name, in: $0.braces) } }
            ?? views.first
        guard let root else { return nil }
        guard let body = find("var body", in: root.braces),
              let open = scalars[body..<root.braces.upperBound].firstIndex(of: "{"),
              let close = matching(open) else { return nil }
        return (open + 1)..<close
    }

    /// Every `struct Name: …View…` with the range inside its braces.
    private func viewStructs() -> [(name: String, braces: Range<Int>)] {
        var found: [(String, Range<Int>)] = []
        var i = 0
        while let at = find("struct", in: i..<count) {
            i = at + 6
            guard isWordStart(at), i < count, scalars[i] == " " || scalars[i] == "\t" else { continue }
            var j = i
            while j < count, scalars[j] == " " { j += 1 }
            let nameStart = j
            while j < count, SwiftText.isIdentifier(scalars[j]) { j += 1 }
            let name = String(String.UnicodeScalarView(scalars[nameStart..<j]))
            guard !name.isEmpty, let open = scalars[j..<count].firstIndex(of: "{") else { continue }
            let header = String(String.UnicodeScalarView(scalars[j..<open]))
            guard header.contains(":"), header.range(of: #"\bView\b"#, options: .regularExpression) != nil,
                  let close = matching(open) else { continue }
            found.append((name, (open + 1)..<close))
        }
        return found
    }

    /// The type names in `range` that open a view: a capitalised name
    /// followed by `(` or `{`, at any depth, in order.
    func views(in range: Range<Int>) -> [String] {
        var names: [String] = []
        var i = range.lowerBound
        while i < range.upperBound {
            guard SwiftText.isIdentifier(scalars[i]), isWordStart(i) else { i += 1; continue }
            var j = i
            while j < range.upperBound, SwiftText.isIdentifier(scalars[j]) { j += 1 }
            let word = String(String.UnicodeScalarView(scalars[i..<j]))
            var k = j
            while k < range.upperBound, scalars[k] == " " || scalars[k] == "\n" || scalars[k] == "\t" { k += 1 }
            let preceded = i > 0 && scalars[i - 1] == "."
            if !preceded, let first = word.unicodeScalars.first, ("A"..."Z").contains(first),
               k < range.upperBound, scalars[k] == "(" || scalars[k] == "{" {
                names.append(word)
            }
            i = j
        }
        return names
    }

    func contains(_ needles: [String], in range: Range<Int>) -> Bool {
        needles.contains { find($0, in: range) != nil }
    }

    private func uses(_ name: String, in range: Range<Int>) -> Bool {
        var i = range.lowerBound
        while let at = find(name, in: i..<range.upperBound) {
            let end = at + name.unicodeScalars.count
            if isWordStart(at), end >= count || !SwiftText.isIdentifier(scalars[end]) { return true }
            i = end
        }
        return false
    }

    private func isWordStart(_ i: Int) -> Bool {
        i == 0 || !SwiftText.isIdentifier(scalars[i - 1])
    }

    private func find(_ needle: String, in range: Range<Int>) -> Int? {
        let n = Array(needle.unicodeScalars)
        guard !n.isEmpty, range.upperBound - range.lowerBound >= n.count else { return nil }
        var i = range.lowerBound
        while i + n.count <= range.upperBound {
            if scalars[i] == n[0], Array(scalars[i..<(i + n.count)]) == n { return i }
            i += 1
        }
        return nil
    }

    /// The `}` that closes the `{` at `open`.
    private func matching(_ open: Int) -> Int? {
        var depth = 0
        for i in open..<count {
            if scalars[i] == "{" { depth += 1 }
            if scalars[i] == "}" {
                depth -= 1
                if depth == 0 { return i }
            }
        }
        return nil
    }
}
