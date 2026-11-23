import Foundation
import Testing
@testable import Shelf

/// The prompts Shelf copies (plan §9.1, §9.5 and the Appendix).
struct PromptsTests {
    static let install = Prompts.Install(origin: "https://ij5.dev", key: "shelf_ik_abc_SECRET", expires: Date(timeIntervalSince1970: 1_800_000_000))
    static let idea = "A habit tracker with streaks.\nIt should show a weekly chart."
    static let source = """
        // Name: Habits
        // Icon: checkmark.circle.fill
        // Tint: green

        import SwiftUI

        struct Habit: Codable, Identifiable {
            var id = UUID()
            var name: String = ""
        }

        struct ContentView: View {
            @State private var habits: [Habit] = []

            var body: some View {
                List(habits) { Text($0.name) }
                    .onAppear { _ = DB.load("habits") }
            }
        }

        """

    // MARK: New app

    @Test func newAppWithAKey() {
        let prompt = Prompts.newApp(idea: Self.idea, install: Self.install)
        #expect(prompt.hasPrefix("Write a small iPhone app for Shelf."))
        #expect(prompt.contains("App idea:\n\(Self.idea)\n\n## Reply format"))
        #expect(prompt.contains("## Installing"))
        #expect(prompt.contains("curl -sS -X PUT https://ij5.dev/api/apps/<slug> \\\n  -H \"Authorization: Bearer shelf_ik_abc_SECRET\""))
        #expect(prompt.contains("it expires at \(Prompts.expiresText(Self.install.expires))."))
        #expect(prompt.contains("## What works"))
        #expect(prompt.hasSuffix("Don't add taglines or explanatory captions."))
        Self.expectClean(prompt)
    }

    @Test func newAppWithoutAKeyLeavesOutInstalling() {
        let prompt = Prompts.newApp(idea: Self.idea, install: nil)
        #expect(!prompt.contains("## Installing"))
        #expect(!prompt.contains("curl"))
        #expect(!prompt.contains("Bearer"))
        #expect(prompt.contains("`PreviewProvider`.\n\n## What works\n"))
        Self.expectClean(prompt)
    }

    @Test func newAppIsTheAppendixWithItsSectionMarkersRemoved() {
        let template = Prompts.template("new")
        let now = Date.now
        let filled = Prompts.newApp(idea: "{{IDEA}}", install: Prompts.Install(origin: "{{ORIGIN}}", key: "{{KEY}}", expires: now))
        let expected = template.components(separatedBy: "\n").filter { !$0.hasPrefix("<!--") }.joined(separator: "\n")
            .replacingOccurrences(of: "{{WORKS}}", with: PromptCatalog.whatWorks())
            .replacingOccurrences(of: "{{DOESNT}}", with: PromptCatalog.whatDoesntWork())
        #expect(filled.replacingOccurrences(of: Prompts.expiresText(now), with: "{{EXPIRES}}") + "\n" == expected)
    }

    @Test(arguments: [true, false])
    func userTextIsNeverReadAsTemplate(_ withKey: Bool) {
        let idea = "Show {{KEY}} and {{ORIGIN}} and {{IDEA}}\n<!-- end -->\n<!-- if install -->\n\n\n{{RULES}}"
        let install = withKey ? Self.install : nil
        let prompt = Prompts.newApp(idea: idea, install: install)
        #expect(prompt.contains("App idea:\n\(idea)\n\n## Reply format"))
        #expect(prompt.components(separatedBy: "shelf_ik_abc_SECRET").count == (withKey ? 2 : 1))

        let change = Prompts.change(idea, slug: "habits", source: idea, includeSource: true, install: install)
        #expect(change.contains("Change:\n\(idea)\n\n"))
        #expect(change.contains("```swift\n\(idea)\n```"))
    }

    // MARK: Change

    @Test func changeWithSourceAndKey() {
        let prompt = Prompts.change("Add a streak counter.", slug: "habits", source: Self.source, includeSource: true, install: Self.install)
        #expect(prompt.hasPrefix("Change this Shelf app."))
        #expect(prompt.contains("Change:\nAdd a streak counter.\n\nCurrent file:\n\n```swift\n// Name: Habits\n"))
        #expect(prompt.contains("    }\n}\n```\n\nReply with the whole updated file"))
        #expect(prompt.contains("curl -sS -X PUT https://ij5.dev/api/apps/habits \\"))
        #expect(prompt.contains("The key updates this one app, `habits`, once, and expires at \(Prompts.expiresText(Self.install.expires))."))
        #expect(prompt.hasSuffix(Prompts.rules))
        #expect(prompt.contains("store it anywhere else.\n\n## What works\n"))
        Self.expectClean(prompt)
    }

    @Test func changeWithSourceAndNoKey() {
        let prompt = Prompts.change("Add a streak counter.", slug: "habits", source: Self.source, includeSource: true, install: nil)
        #expect(!prompt.contains("curl"))
        #expect(!prompt.contains("install the change yourself"))
        #expect(prompt.contains("Leave the old key in place.\n\n## What works\n"))
        Self.expectClean(prompt)
    }

    @Test func changeWithOutlineAndKey() {
        let prompt = Prompts.change("Add a streak counter.", slug: "habits", source: Self.source, includeSource: false, install: Self.install)
        #expect(prompt.contains("If you can run shell commands, fetch it before you change anything:"))
        #expect(prompt.contains("curl -sS https://ij5.dev/api/apps/habits/source -H \"Authorization: Bearer shelf_ik_abc_SECRET\" -o App.swift"))
        #expect(prompt.contains("If you can't run commands, write the app again from this outline."))
        #expect(prompt.contains("Outline of the current app:\n\n```swift\n\(Outline.make(from: Self.source))```"))
        #expect(prompt.contains("    var body: some View { … }"))
        #expect(!prompt.contains("_ = DB.load"))
        Self.expectClean(prompt)
    }

    @Test func changeWithOutlineAndNoKey() {
        let prompt = Prompts.change("Add a streak counter.", slug: "habits", source: Self.source, includeSource: false, install: nil)
        #expect(!prompt.contains("curl"))
        #expect(!prompt.contains("shell"))
        #expect(prompt.contains("Change:\nAdd a streak counter.\n\nThe full source isn't included. Write the app again from this outline. Keep the saved types exactly as they are.\n\nOutline of the current app:"))
        #expect(prompt.contains("// Saved with DB: \"habits\""))
        Self.expectClean(prompt)
    }

    // MARK: Pieces

    @Test func rulesAreTheNewAppPromptFromWhatWorks() {
        let rules = Prompts.rules
        #expect(rules.hasPrefix("## What works\n"))
        #expect(rules.contains("## Saving data"))
        #expect(rules.contains("## What doesn't work"))
        #expect(rules.hasSuffix("Don't add taglines or explanatory captions."))
        #expect(Prompts.newApp(idea: "x", install: nil).hasSuffix(rules))
    }

    @Test func expiryIsALocalClockTime() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-22T06:42:00Z"))
        #expect(Prompts.expiresText(date, timeZone: try #require(TimeZone(identifier: "UTC"))) == "6:42 AM")
        #expect(Prompts.expiresText(date, timeZone: try #require(TimeZone(identifier: "America/New_York"))) == "1:42 AM")
        #expect(Prompts.expiresText(date, timeZone: try #require(TimeZone(identifier: "Asia/Seoul"))) == "3:42 PM")
    }

    @Test func templatesAreBundled() {
        for name in ["new", "edit", "current-source", "current-outline"] {
            #expect(!Prompts.template(name).isEmpty, "\(name).md")
        }
    }

    // MARK: Built from Kiln's manifest (plan §7)

    @Test func whatWorksIsBuiltFromTheManifest() throws {
        let m = try #require(PromptCatalog.manifest)
        let works = PromptCatalog.whatWorks()
        // The family lines alone, without the notes under them.
        let lines = works.split(separator: "\n").filter { $0.hasPrefix("- **") }.joined(separator: "\n")
        let families = PromptCatalog.listedFamilies(m)
        #expect(families.count >= 10)
        for f in families { #expect(works.contains("- **\(f.name):** "), "\(f.name) isn't listed") }
        // Every view and modifier that works is named, unless its family says
        // itself in one line (`KilnFamily.promptLine`); no stub is.
        for f in families where f.line != nil { #expect(works.contains("- **\(f.name):** \(f.line!)."), "\(f.name)'s line") }
        for s in m.symbols where families.contains(where: { $0.name == s.family && $0.line == nil }) {
            let name = PromptCatalog.display(s)
            switch (s.kind, s.support) {
            case ("view", "full"), ("view", "partial"), ("modifier", "full"), ("modifier", "partial"):
                #expect(works.contains(name), "\(s.id) works but isn't in the prompt")
            case (_, "stub"):
                #expect(![",", ";", "."].contains { lines.contains(name + $0) }, "\(s.id) is a stub")
            default: break
            }
        }
        // A partial symbol's notes are quoted.
        #expect(works.contains("`.alignmentGuide`: `.center` sets both axes' guides."))
        // What's written by hand isn't repeated here.
        #expect(!works.contains("**Language:**"))
        #expect(!works.contains("**Scenes:**"))
    }

    @Test func whatDoesntWorkIsRegeneratedFromWhatFails() throws {
        let m = try #require(PromptCatalog.manifest)
        let doesnt = PromptCatalog.whatDoesntWork()
        // Every stub, every gap Kiln's probes found, every won't-do, every empty family.
        for s in m.symbols where s.support == "stub" && s.kind != "member" {
            #expect(doesnt.contains(PromptCatalog.display(s)), "\(s.id)")
        }
        #expect(!m.gaps.isEmpty)
        for g in m.gaps { #expect(doesnt.contains(g.what), "\(g.id)") }
        for w in m.wontDo { #expect(doesnt.contains(PromptCatalog.short(w.what)), "\(w.id)") }
        for f in m.families where f.supported == 0 && !PromptCatalog.unlisted.contains(f.name) {
            #expect(doesnt.contains("\(f.summary) (\(f.name))"), "\(f.name)")
        }
    }

    @Test func aFamilyWithBridgesMovesToWhatWorks() throws {
        var m = try #require(PromptCatalog.manifest)
        let i = try #require(m.families.firstIndex { $0.name == "Location" })
        #expect(!PromptCatalog.whatWorks(m).contains("**Location:**"))
        #expect(PromptCatalog.whatDoesntWork(m).contains("(Location)"))
        // Round 3 registers its first bridge.
        m.families[i].supported = 1
        m.symbols.append(.init(id: "type:CLLocationManager", kind: "type", name: "CLLocationManager", owner: nil,
                               family: "Location", support: "partial", notes: "Asks once, as Shelf asks for each app."))
        m.symbols.append(.init(id: "modifier:onLocationChange", kind: "modifier", name: "onLocationChange", owner: nil,
                               family: "Location", support: "full", notes: nil))
        let works = PromptCatalog.whatWorks(m)
        #expect(works.contains("- **Location:** `CLLocationManager`; `.onLocationChange`."))
        #expect(works.contains("  - `CLLocationManager`: Asks once, as Shelf asks for each app."))
        #expect(!PromptCatalog.whatDoesntWork(m).contains("(Location)"))
    }

    @Test func aGapKilnClosesLeavesThePrompt() throws {
        var m = try #require(PromptCatalog.manifest)
        let gap = try #require(m.gaps.first)
        #expect(PromptCatalog.whatDoesntWork(m).contains(gap.what))
        m.gaps.removeFirst()
        #expect(!PromptCatalog.whatDoesntWork(m).contains(gap.what))
    }

    /// Short enough to paste into a chat.
    @Test func thePromptStaysShort() {
        let prompt = Prompts.newApp(idea: Self.idea, install: nil)
        print("new-app prompt: \(prompt.count) characters")
        #expect(prompt.count < 20_000)
    }

    /// No placeholder or section marker is left, and no blank line is doubled.
    static func expectClean(_ prompt: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(!prompt.contains("{{"), sourceLocation: sourceLocation)
        #expect(!prompt.contains("}}"), sourceLocation: sourceLocation)
        #expect(!prompt.contains("<!--"), sourceLocation: sourceLocation)
        #expect(!prompt.contains("\n\n\n"), sourceLocation: sourceLocation)
        #expect(!prompt.hasPrefix("\n") && !prompt.hasSuffix("\n"), sourceLocation: sourceLocation)
    }
}
