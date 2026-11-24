import SwiftUI
import UIKit
import RegexBuilder
import NaturalLanguage

// Round 2A in one app: text parsing (Regex, RegexBuilder, NSDataDetector,
// Decimal, NaturalLanguage), units (Measurement and its formatting),
// haptics (.sensoryFeedback, UIKit's generators) and sharing (ShareLink,
// UIPasteboard, text selection).

struct Detected {
    var links = 0
    var phones = 0
}

struct ContentView: View {
    @State private var note = "Flight to Zurich on 2026-12-03 at 09:30. Hotel +41 44 668 18 00, https://www.example.com/hotel. Budget $1,250.00 #zurich #ski"
    @State private var travelers = 2
    @State private var distanceKm = 12.0
    @State private var packed = 0
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("From the note") {
                    LabeledContent("Tags", value: tags.joined(separator: ", "))
                    LabeledContent("Date", value: dateText)
                    LabeledContent("Time", value: timeText)
                    LabeledContent("Links", value: "\(detected.links)")
                    LabeledContent("Phones", value: "\(detected.phones)")
                    LabeledContent("Words", value: "\(wordCount)")
                    LabeledContent("Language", value: language)
                }
                Section("Budget") {
                    LabeledContent("Each", value: perPerson)
                    Button("Add traveler") { travelers += 1 }
                        .sensoryFeedback(.increase, trigger: travelers)
                    Text("Travelers: \(travelers)")
                }
                Section("Distance") {
                    Text(distanceText)
                    Text(milesText)
                    Button("Walk 2 km more") { distanceKm += 2 }
                        .sensoryFeedback(trigger: distanceKm) { old, new in new > old ? .success : nil }
                    LabeledContent("Base value", value: baseMeters)
                }
                Section("Pack") {
                    Button("Pack a bag") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        packed += 1
                    }
                    Text("Bags packed: \(packed)")
                    Button("Copy plan") {
                        UIPasteboard.general.string = summary
                        copied = UIPasteboard.general.hasStrings
                    }
                    Text(copied ? "Copied" : "Not copied").textSelection(.enabled)
                    ShareLink("Share plan", item: summary)
                }
            }
            .navigationTitle("Trip Notes")
        }
    }

    var tags: [String] {
        let tag = Regex {
            "#"
            Capture { OneOrMore(.word) }
        }
        return note.matches(of: tag).map { String($0.1) }
    }

    var dateText: String {
        let date = Regex {
            TryCapture { Repeat(.digit, count: 4) } transform: { Int($0) }
            "-"
            TryCapture { Repeat(.digit, count: 2) } transform: { Int($0) }
            "-"
            TryCapture { Repeat(.digit, count: 2) } transform: { Int($0) }
        }
        guard let m = note.firstMatch(of: date) else { return "none" }
        return "day \(m.3) of month \(m.2), \(m.1)"
    }

    var timeText: String {
        guard let m = note.firstMatch(of: #/(\d{2}):(\d{2})/#) else { return "none" }
        return "\(m.1)h \(m.2)m"
    }

    var detected: Detected {
        var found = Detected()
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue) else { return found }
        for result in detector.matches(in: note, options: [], range: NSRange(note.startIndex..., in: note)) {
            if result.resultType == .link { found.links += 1 }
            if result.resultType == .phoneNumber { found.phones += 1 }
        }
        return found
    }

    var wordCount: Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = note
        return tokenizer.tokens(for: note.startIndex..<note.endIndex).count
    }

    var language: String {
        NLLanguageRecognizer.dominantLanguage(for: note)?.rawValue ?? "unknown"
    }

    var perPerson: String {
        guard let m = note.firstMatch(of: #/\$[\d,]+\.\d{2}/#),
              let total = try? Decimal(String(m.0), format: .currency(code: "USD")) else { return "none" }
        return (total / Decimal(travelers)).formatted(.currency(code: "USD"))
    }

    var distance: Measurement<UnitLength> { Measurement(value: distanceKm, unit: UnitLength.kilometers) }

    var distanceText: String {
        distance.formatted(.measurement(width: .wide, usage: .asProvided))
    }

    var milesText: String {
        distance.converted(to: .miles).formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    var baseMeters: String {
        let total = distance + Measurement(value: 500, unit: UnitLength.meters)
        return "\(Int(total.converted(to: .meters).value)) m"
    }

    var summary: String {
        "Trip with \(travelers) people, \(distanceText), tags \(tags.joined(separator: " "))"
    }
}
