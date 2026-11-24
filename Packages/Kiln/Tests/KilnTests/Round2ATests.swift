import XCTest
import SwiftUI
@testable import Kiln

/// Round 2A (PLAN.md §3.1–§3.4): haptics, share and paste, text parsing,
/// units. Each bridge's forms bind, its values behave as Foundation's, the
/// app is shown in a window, and what it prints is what compiled Swift prints.
@MainActor
final class Round2ATests: XCTestCase {
    /// What the app's top-level code prints, run as Shelf runs it (a stub context here).
    func console(_ code: String, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        let source = "import SwiftUI\nimport RegexBuilder\nimport NaturalLanguage\nstruct ContentView: View { var body: some View { Text(\"x\") } }\n" + code
        let check = Kiln.check(source)
        XCTAssertEqual(check.errors.map(\.message), [], file: file, line: line)
        let context = KilnContext.stub()
        var errors: [String] = []
        context.onError = { errors.append($0.message) }
        let result = Kiln.run(source, context: context)
        XCTAssertEqual(result.errors + errors, [], file: file, line: line)
        defer { result.tearDown() }
        return result.consoleOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
    }

    // MARK: §3.1 Haptics

    func testSensoryFeedbackFormsBindAndShow() throws {
        let src = BridgeTest.app(#"""
            VStack {
                Button("Tap") { count += 1 }
                    .sensoryFeedback(.success, trigger: count)
                    .sensoryFeedback(.impact(weight: .heavy, intensity: 0.8), trigger: count) { old, new in new > old }
                    .sensoryFeedback(trigger: count) { old, new in new % 2 == 0 ? .increase : nil }
                    .sensoryFeedback(.impact(flexibility: .soft), trigger: count)
                    .sensoryFeedback(.selection, trigger: count)
            }
            """#, state: "@State private var count = 0")
        XCTAssertEqual(BridgeTest.problems(src), [])
        let bound = try BridgeTest.bound(src)
        XCTAssertTrue(bound.contains(".sensoryFeedback(_:trigger:)"), "\(bound)")
        XCTAssertTrue(bound.contains(".sensoryFeedback(_:trigger:condition:)"), "\(bound)")
        XCTAssertTrue(bound.contains(".sensoryFeedback(trigger:_:)"), "\(bound)")
        XCTAssertEqual(Kiln.check(src).warnings.map(\.message), [], "no longer a stub")
    }

    func testSensoryFeedbackIsAValue() {
        XCTAssertEqual(console("""
            let a: SensoryFeedback = .success
            print(a == .success, a == .warning, SensoryFeedback.impact(weight: .light, intensity: 0.5))
            var f = SensoryFeedback.selection
            switch f { case .selection: print("selection") default: print("other") }
            """), ["true false SensoryFeedback.impact(weight: .light, intensity: 0.5)", "selection"])
        XCTAssertEqual(KFeedback.make("impact", [.native(.implicit("heavy", []))], ["weight"])?.swiftUI, .impact(weight: .heavy))
        XCTAssertEqual(KFeedback(name: "warning").swiftUI, .warning)
    }

    func testFeedbackGeneratorsPlay() {
        KHaptics.played = []
        let src = BridgeTest.app(#"""
            Button("Go") {
                let impact = UIImpactFeedbackGenerator(style: .heavy)
                impact.prepare()
                impact.impactOccurred()
                impact.impactOccurred(intensity: 0.5)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                UISelectionFeedbackGenerator().selectionChanged()
            }
            """#)
        XCTAssertEqual(Kiln.check(src).issues.map(\.message), [])
        XCTAssertEqual(Kiln.validate(src).errors, [])
        XCTAssertEqual(KHaptics.played, ["impact(heavy)", "impact(heavy, 0.5)", "notification(warning)", "selection"])
    }

    func testAConditionClosureIsCalledByTheCheck() {
        let src = BridgeTest.app(#"Text("x").sensoryFeedback(.success, trigger: count) { old, new in undefinedThing }"#, state: "@State private var count = 0")
        XCTAssertEqual(Kiln.validate(src).errors, ["Line 6: Cannot find 'undefinedThing' in scope"])
    }

    // MARK: §3.2 Share and paste

    func testShareLinkTakesEveryKindOfItem() throws {
        let src = BridgeTest.app(#"""
            VStack {
                ShareLink(item: "Hello")
                ShareLink("Site", item: URL(string: "https://apple.com")!, subject: Text("Look"), message: Text("Here"))
                ShareLink(items: ["a", "b"]) { Label("Two", systemImage: "square.and.arrow.up") }
                ShareLink(item: Image(systemName: "star"), preview: SharePreview("Star", image: Image(systemName: "star")))
                ShareLink(item: Data("x".utf8), preview: SharePreview("Data"))
                ShareLink(items: notes) { note in SharePreview(note.text, icon: Image(systemName: "note")) }
                ShareLink("One", item: notes[0], preview: SharePreview("Note"))
            }
            """#, state: "let notes = [Note(text: \"a\"), Note(text: \"b\")]", extra: """
            struct Note: Codable, Transferable {
                var text: String
                static var transferRepresentation: some TransferRepresentation {
                    CodableRepresentation(contentType: .json)
                    ProxyRepresentation(exporting: \\.text)
                }
            }
            """)
        XCTAssertEqual(BridgeTest.problems(src), [])
        let bound = try BridgeTest.bound(src)
        XCTAssertEqual(bound.filter { $0.hasPrefix("ShareLink") }.count, 7, "\(bound)")
        XCTAssertTrue(bound.contains("ShareLink(items:subject:message:preview:label:)"))
    }

    func testShareLinkKinds() throws {
        let interp = try KInterpreter(program: try KEParser.parse("let x = 1"), headless: true)
        guard case .strings(let s) = KShare.kind([.string("a"), .string("b")], interp) else { return XCTFail() }
        XCTAssertEqual(s, ["a", "b"])
        guard case .urls(let u) = KShare.kind([.native(.url(URL(string: "https://a.com")!))], interp) else { return XCTFail() }
        XCTAssertEqual(u.count, 1)
        guard case .data = KShare.kind([KBuiltins.data(Data([1]))], interp) else { return XCTFail() }
        guard case .images = KShare.kind([.view(.image(Image(systemName: "star")))], interp) else { return XCTFail() }
        guard case .none(let why) = KShare.kind([.bool(true)], interp) else { return XCTFail() }
        XCTAssertTrue(why.contains("not Bool"), why)
    }

    func testANonTransferableShareIsAnError() {
        let src = BridgeTest.app(#"ShareLink(item: Plain(), preview: SharePreview("x"))"#, extra: "struct Plain {}")
        XCTAssertEqual(BridgeTest.shown(src), ["ShareLink(item:subject:message:preview:): 'Plain' isn't Transferable: add `: Transferable` and `static var transferRepresentation`"])
    }

    func testPasteButtonAndEditCommands() throws {
        let src = BridgeTest.app(#"""
            VStack {
                PasteButton(payloadType: String.self) { strings in pasted = strings }
                PasteButton(payloadType: URL.self) { urls in pasted = urls.map(\.absoluteString) }
                PasteButton(payloadType: Note.self) { notes in pasted = notes.map(\.text) }
                Text(pasted.joined())
                    .copyable([pasted.joined()])
                    .cuttable(for: String.self) { [pasted.joined()] }
                    .pasteDestination(for: String.self) { items in pasted = items }
            }
            """#, state: "@State private var pasted: [String] = []", extra: """
            struct Note: Codable, Transferable {
                var text: String
                static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .json) }
            }
            """)
        XCTAssertEqual(BridgeTest.problems(src), [])
        XCTAssertEqual(try BridgeTest.bound(src).filter { $0.hasPrefix("PasteButton") }, Array(repeating: "PasteButton(payloadType:onPaste:)", count: 3))
    }

    func testPasteButtonRejectsAnUnknownPayload() {
        let src = BridgeTest.app(#"PasteButton(payloadType: Int.self) { _ in }"#)
        XCTAssertEqual(BridgeTest.shown(src), ["PasteButton(payloadType:onPaste:): payloadType needs String.self, URL.self, Data.self, Image.self or your Transferable type"])
    }

    func testThePasteboardIsTheRunsOwnInACheck() {
        XCTAssertEqual(console("""
            print(UIPasteboard.general.hasStrings, UIPasteboard.general.string ?? "-")
            UIPasteboard.general.string = "copied"
            print(UIPasteboard.general.hasStrings, UIPasteboard.general.string ?? "-", UIPasteboard.general.changeCount)
            UIPasteboard.general.strings = ["a", "b"]
            print(UIPasteboard.general.strings, UIPasteboard.general.numberOfItems)
            let pb = UIPasteboard.general
            pb.url = URL(string: "https://apple.com")
            print(pb.hasURLs, pb.hasStrings, pb.url!.absoluteString)
            """), ["false -", "true copied 1", "[\"a\", \"b\"] 2", "true false https://apple.com"])
    }

    func testAHostProvidedPasteboard() {
        let pb = KilnPasteboard.memory()
        let context = KilnContext.stub()
        context.provide(pb)
        let result = Kiln.run(BridgeTest.app(#"Text("x").onAppear { UIPasteboard.general.string = "hi" }"#) + "\nlet x = { UIPasteboard.general.string = \"top\" }()", context: context)
        defer { result.tearDown() }
        XCTAssertEqual(pb.strings, ["top"])
    }

    func testTextSelection() {
        XCTAssertEqual(console("""
            let text = "Hello world"
            let s = TextSelection(range: 6..<11)
            if case .selection(let r) = s.indices { print(text[r], s.isInsertion) }
            let caret = TextSelection(insertionPoint: 3)
            print(caret.isInsertion)
            """), ["world false", "true"])
        let src = BridgeTest.app(#"""
            VStack {
                TextField("Text", text: $text, selection: $selection)
                TextEditor(text: $text, selection: $selection)
                Text("Pick me").textSelection(.enabled)
                Text("Not me").textSelection(.disabled)
            }
            .textSelectionAffinity(.upstream)
            .searchable(text: $text).searchSelection($selection)
            """#, state: "@State private var text = \"Hello\"\n@State private var selection: TextSelection? = nil")
        XCTAssertEqual(BridgeTest.problems(src), [])
        if #available(macOS 15, iOS 18, *) {
            let sel = KTextSelection(ranges: [1..<3])
            XCTAssertEqual(KTextSelection(sel.swiftUI(in: "héllo"), in: "héllo").ranges, [1..<3])
        }
    }

    // MARK: §3.3 Text parsing

    func testRegexAPI() {
        XCTAssertEqual(console(#"""
            let text = "Order #123 shipped 2026-11-24; order #45 pending"
            let m = text.firstMatch(of: /#(?<num>\d+)/)
            print(m?.num ?? "-", m?.1 ?? "-", m?.0 ?? "-")
            print(text.matches(of: /#(\d+)/).map { String($0.1) })
            print(text.replacing(/\d+/, with: "N"))
            print("a, b ,c".split(separator: /\s*,\s*/))
            print(text.ranges(of: /#\d+/).count, text.firstRange(of: "shipped")!)
            let r = try Regex("o(r)der")
            print(text.firstMatch(of: r.ignoresCase())?.0 ?? "-", text.wholeMatch(of: /\d+/) == nil)
            print("  x".trimmingPrefix(/\s+/), "abc".starts(with: /a./), text.contains(/#\d{3}/))
            var t = "a  b   c"
            t.replace(/\s+/, with: " ")
            print(t)
            print(text.replacing(/#(\d+)/) { m in "No.\(m.1)" })
            """#), ["123 123 #123", "[\"123\", \"45\"]", "Order #N shipped N-N-N; order #N pending", "[\"a\", \"b\", \"c\"]",
                    "2 11..<18", "Order true", "x true true", "a b c", "Order No.123 shipped 2026-11-24; order No.45 pending"])
    }

    func testRegexBuilder() {
        XCTAssertEqual(console(#"""
            let text = "Order #123 shipped 2026-11-24; order #45 pending"
            let num = Reference(Int.self)
            let order = Regex {
                "#"
                Capture(as: num) { OneOrMore(.digit) } transform: { Int($0)! }
                OneOrMore(.whitespace)
                Capture { ChoiceOf { "shipped"; "pending" } }
            }
            for match in text.matches(of: order) { print(match[num] + 1, match.2) }
            let date = Regex {
                TryCapture { Repeat(.digit, count: 4) } transform: { Int($0) }
                "-"
                TryCapture { Repeat(.digit, count: 2) } transform: { Int($0) }
                "-"
                TryCapture { Repeat(.digit, count: 2) } transform: { Int($0) }
            }
            if let d = text.firstMatch(of: date) { print(d.1, d.2, d.3, d.output.1 + d.output.2) }
            let word = Regex { Anchor.wordBoundary; OneOrMore(.word); Anchor.wordBoundary }
            print(text.matches(of: word).count)
            print("ff00zz".firstMatch(of: Regex { OneOrMore(CharacterClass.hexDigit) })!.0)
            print(text.firstMatch(of: Regex { OneOrMore(.digit.inverted) })!.0)
            print("Total $1,234.50".firstMatch(of: Regex { "$"; Capture(.localizedDouble(locale: Locale(identifier: "en_US"))) })!.1)
            print("color colour".matches(of: Regex { "colo"; Optionally("u"); "r" }).count)
            print("aaa".firstMatch(of: Regex { OneOrMore("a", .reluctant) })!.0)
            print("x-1 y-22".matches(of: Regex { CharacterClass.anyOf("xy"); "-"; Repeat(1...2) { .digit } }).count)
            print("bad".firstMatch(of: Regex { TryCapture { OneOrMore(.word) } transform: { Int($0) } }) == nil)
            print("ab12".firstMatch(of: Regex { Capture { OneOrMore("a"..."z") }; NegativeLookahead { "x" } })!.1)
            """#), ["124 shipped", "46 pending", "2026 11 24 2037", "9", "ff00", "Order #", "1234.5", "2", "a", "2", "true", "ab"])
    }

    func testRegexBuilderCompilesToOnePattern() throws {
        XCTAssertEqual(KRegexBuilding.captureCount(#"(a)(?:b)(?<n>c)\(d\)[(]"#), 2)
        XCTAssertEqual(KRegexBuilding.escape("a.b*c"), #"a\.b\*c"#)
        let box = try KRegexBuilding.compile(.seq([.literal("$"), .capture(.quant(.raw("\\d", captures: 0), min: 1, max: nil, behavior: nil), KRegexCapture(), nil)]), 1)
        XCTAssertEqual(box.source, #"\$((?:(?:\d))+)"#)
        XCTAssertEqual(box.captures.count, 1)
    }

    func testFoundationParsers() {
        XCTAssertEqual(console(#"""
            let text = "Order #123 shipped 2026-11-24; order #45 pending"
            let rx = try NSRegularExpression(pattern: "#(\\d+)")
            let ns = NSRange(text.startIndex..., in: text)
            for res in rx.matches(in: text, range: ns) {
                if let rr = Range(res.range(at: 1), in: text) { print(text[rr]) }
            }
            print(rx.numberOfMatches(in: text, range: ns), rx.stringByReplacingMatches(in: text, range: ns, withTemplate: "[$1]"))
            print(NSRegularExpression.escapedPattern(for: "a.b"), ns.location, ns.length)
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
            let msg = "Call 555-123-4567 or see https://apple.com today"
            for d in detector.matches(in: msg, options: [], range: NSRange(location: 0, length: msg.utf16.count)) {
                if d.resultType == .link { print("link", d.url!.absoluteString) }
                if d.resultType == .phoneNumber { print("phone", d.phoneNumber ?? "") }
            }
            let sc = Scanner(string: "width=42 height=7.5 name:Bob")
            _ = sc.scanString("width=")
            let w = sc.scanInt()
            _ = sc.scanString("height=")
            let h = sc.scanDouble()
            _ = sc.scanUpToString(":")
            _ = sc.scanString(":")
            print(w!, h!, sc.scanCharacters(from: .letters)!, sc.isAtEnd)
            print("a1b2".components(separatedBy: CharacterSet.decimalDigits), "x,y".rangeOfCharacter(from: CharacterSet(charactersIn: ","))!)
            do { _ = try NSRegularExpression(pattern: "(") } catch { print("bad pattern") }
            """#), ["123", "45", "2 Order [123] shipped 2026-11-24; order [45] pending", #"a\.b 0 48"#,
                    "phone 555-123-4567", "link https://apple.com", "42 7.5 Bob true", "[\"a\", \"b\", \"\"] 1..<2", "bad pattern"])
    }

    func testParseStrategiesAndDecimal() {
        XCTAssertEqual(console(#"""
            print(try Date("2026-11-24T09:30:00Z", strategy: .iso8601).timeIntervalSince1970)
            print(try Double("1,234.5", format: .number), try Int("1,234", format: .number), try Double("45%", format: .percent))
            let dec = try Decimal("$1,234.50", format: .currency(code: "USD"))
            print(dec, dec + Decimal(string: "0.25")!, Decimal(string: "0.1")! + Decimal(string: "0.2")! == Decimal(string: "0.3")!)
            print(dec.formatted(.currency(code: "USD")), dec > Decimal(1000), dec * 2)
            do { _ = try Double("abc", format: .number) } catch { print("threw") }
            print("Café".localizedStandardContains("cafe"), "Résumé".localizedStandardContains("RESUME"))
            let s = "Hello"
            print(s[s.index(s.startIndex, offsetBy: 1)..<s.index(before: s.endIndex)], s.distance(from: s.startIndex, to: s.endIndex))
            let md = try AttributedString(markdown: "**Bold** and _it_")
            print(String(md.characters))
            """#), ["1795512600.0", "1234.5 1234 0.45", "1234.5 1234.75 true", "$1,234.50 true 2469", "threw", "true true", "ell 5", "Bold and it"])
    }

    func testNaturalLanguage() {
        let out = console(#"""
            let text = "Tim Cook visited Paris last week. The trip was wonderful!"
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = text
            print(tokenizer.tokens(for: text.startIndex..<text.endIndex).map { String(text[$0]) }.prefix(3))
            var sentences = 0
            let st = NLTokenizer(unit: .sentence)
            st.string = text
            st.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in sentences += 1; return true }
            print(sentences)
            let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType, .sentimentScore])
            tagger.string = text
            var nouns: [String] = []
            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, range in
                if tag == .noun { nouns.append(String(text[range])) }
                return true
            }
            print(nouns.contains("Paris"))
            let (score, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
            print(Double(score?.rawValue ?? "x") != nil)
            print(NLLanguageRecognizer.dominantLanguage(for: "Bonjour tout le monde, comment ça va?") == .french, NLLanguage.english.rawValue)
            """#)
        XCTAssertEqual(out, ["[\"Tim\", \"Cook\", \"visited\"]", "2", "true", "true", "true en"])
    }

    // MARK: §3.4 Units

    func testMeasurements() {
        XCTAssertEqual(console(#"""
            let run = Measurement(value: 5, unit: UnitLength.kilometers)
            print(run, run.converted(to: .miles).value > 3.1, run.unit == .kilometers, run.unit.symbol)
            let total = run + Measurement(value: 500, unit: UnitLength.meters)
            print(total, total > run, run == Measurement(value: 5000, unit: UnitLength.meters))
            print(run * 2, run / 2, run + run, run - Measurement(value: 1, unit: .kilometers))
            var t = Measurement(value: 100, unit: UnitTemperature.celsius)
            t.convert(to: .fahrenheit)
            print(t.value.rounded())
            t.value = 50
            print(t)
            let smoot = UnitLength(symbol: "smoot", converter: UnitConverterLinear(coefficient: 1.70180))
            print(Measurement(value: 100, unit: smoot).converted(to: .meters).value.rounded())
            print(Measurement(value: 3, unit: Unit(symbol: "apples")))
            print(UnitLength.baseUnit().symbol, UnitDuration.hours.converter.baseUnitValue(fromValue: 1))
            let laps = [run, Measurement(value: 3, unit: UnitLength.miles), Measurement(value: 800, unit: UnitLength.meters)]
            print(laps.sorted().map(\.description), laps.max()!)
            print(Measurement<UnitSpeed>(value: 10, unit: .metersPerSecond).converted(to: .kilometersPerHour).value.rounded())
            print(Measurement(value: 2048, unit: UnitInformationStorage.kilobytes).converted(to: .megabytes))
            """#), ["5.0 km true true km", "5500.0 m true true", "10.0 km 2.5 km 10.0 km 4.0 km", "212.0", "50.0 °F", "170.0", "3.0 apples",
                    "m 3600.0", "[\"800.0 m\", \"3.0 mi\", \"5.0 km\"] 5.0 km", "36.0", "2.048 MB"])
    }

    func testMeasurementFormatting() {
        let us = Locale(identifier: "en_US")
        let out = console(#"""
            let run = Measurement(value: 5, unit: UnitLength.kilometers)
            print(run.formatted(.measurement(width: .wide, usage: .asProvided).locale(Locale(identifier: "en_US"))))
            print(run.formatted(.measurement(width: .abbreviated, usage: .road).locale(Locale(identifier: "en_US"))))
            print(run.formatted(.measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))).locale(Locale(identifier: "en_US"))))
            let f = MeasurementFormatter()
            f.locale = Locale(identifier: "en_US")
            f.unitOptions = .providedUnit
            f.unitStyle = .long
            f.numberFormatter.maximumFractionDigits = 1
            print(f.string(from: run.converted(to: .miles)))
            print(Locale(identifier: "en_US").measurementSystem == .us, Locale(identifier: "fr_FR").measurementSystem == .metric, Locale(identifier: "en_GB").usesMetricSystem)
            """#)
        let km = Measurement(value: 5, unit: UnitLength.kilometers)
        XCTAssertEqual(out, [
            km.formatted(.measurement(width: .wide, usage: .asProvided).locale(us)),
            km.formatted(.measurement(width: .abbreviated, usage: .road).locale(us)),
            km.formatted(.measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))).locale(us)),
            "3.1 miles",
            "true true true",
        ])
    }

    func testUnitErrors() {
        func errors(_ code: String) -> [String] { Kiln.validate(BridgeTest.app(#"Text("x")"#) + "\n" + code).errors }
        XCTAssertEqual(errors("let m = Measurement(value: 1, unit: UnitLength.meters)\nprint(m.converted(to: UnitMass.grams))"),
                       ["Line 10: Measurement.converted(to:): can't convert UnitLength to UnitMass"])
        XCTAssertEqual(errors("print(Measurement(value: 1, unit: UnitLength.meters) + Measurement(value: 1, unit: UnitMass.grams))"),
                       ["Line 9: Binary operator '+' can't combine UnitLength and UnitMass measurements"])
    }

    func testEveryFoundationUnitExists() {
        for (dimension, names) in KUnits.dimensions {
            for name in names { XCTAssertNotNil(KUnits.unit(dimension, name), "\(dimension).\(name)") }
            XCTAssertNotNil(KUnits.baseUnit(dimension), dimension)
            XCTAssertEqual(KUnits.typeName(KUnits.baseUnit(dimension)!), dimension)
        }
        XCTAssertEqual(KUnits.dimensions.count, 22)
    }

    func testMeasurementInText() {
        let src = BridgeTest.app(#"""
            VStack {
                Text(distance, format: .measurement(width: .wide))
                Text(distance.converted(to: .miles).formatted(.measurement(width: .abbreviated, usage: .road)))
                Text("\(distance)")
            }
            """#, state: "@State private var distance = Measurement(value: 5, unit: UnitLength.kilometers)")
        XCTAssertEqual(BridgeTest.problems(src), [])
    }
}
