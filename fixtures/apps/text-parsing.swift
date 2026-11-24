// Name: Note Reader
// Icon: text.magnifyingglass
// Tint: indigo
// Covers: Text

import SwiftUI
import RegexBuilder
import NaturalLanguage

struct Finding: Identifiable {
    let id = UUID()
    let kind: String
    let value: String
}

struct ContentView: View {
    @State private var text = """
    Lunch with Maria in Lisbon on 2026-12-03 was wonderful! #travel #food
    Call 555-010-4477 or see https://www.apple.com. Total: $1,234.50
    """

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextEditor(text: $text).frame(minHeight: 120)
                }
                Section("Found") {
                    ForEach(findings) { f in
                        LabeledContent(f.kind, value: f.value)
                    }
                }
                Section("Language") {
                    LabeledContent("Language", value: language)
                    LabeledContent("Words", value: "\(wordCount)")
                    LabeledContent("Mood", value: mood)
                    LabeledContent("Mentions \"lisbon\"", value: text.localizedStandardContains("lisbon") ? "Yes" : "No")
                }
            }
            .navigationTitle("Note Reader")
        }
    }

    var findings: [Finding] {
        var out: [Finding] = []
        for match in text.matches(of: /#(\w+)/) {
            out.append(Finding(kind: "Tag", value: String(match.1)))
        }
        let date = Regex {
            TryCapture { Repeat(.digit, count: 4) } transform: { Int($0) }
            "-"
            TryCapture { Repeat(.digit, count: 2) } transform: { Int($0) }
            "-"
            TryCapture { Repeat(.digit, count: 2) } transform: { Int($0) }
        }
        if let d = text.firstMatch(of: date) {
            out.append(Finding(kind: "Date", value: "\(d.3)/\(d.2)/\(d.1)"))
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue) {
            for result in detector.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
                if let url = result.url { out.append(Finding(kind: "Link", value: url.host() ?? url.absoluteString)) }
                if let phone = result.phoneNumber { out.append(Finding(kind: "Phone", value: phone)) }
            }
        }
        if let money = text.firstMatch(of: /\$[\d,]+\.\d{2}/), let total = try? Decimal(String(money.0), format: .currency(code: "USD")) {
            out.append(Finding(kind: "Total", value: (total * 2).formatted(.currency(code: "USD")) + " for two"))
        }
        let names = NLTagger(tagSchemes: [.nameType])
        names.string = text
        names.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if tag == .personalName { out.append(Finding(kind: "Person", value: String(text[range]))) }
            if tag == .placeName { out.append(Finding(kind: "Place", value: String(text[range]))) }
            return true
        }
        return out
    }

    var language: String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "unknown"
    }

    var wordCount: Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).count
    }

    var mood: String {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (score, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        let value = Double(score?.rawValue ?? "0") ?? 0
        return value > 0.2 ? "Happy" : (value < -0.2 ? "Unhappy" : "Neutral")
    }
}
