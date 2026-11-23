import SwiftUI
import Testing
import UIKit
@testable import Shelf

/// Search as App Library's (PLAN.md §0.3): its sections, its index, what
/// Return opens, and the one spring the pull runs on.
@MainActor
@Suite struct SearchTests {
    private func items(_ names: [String]) -> [HomeItem] {
        names.enumerated().map { index, name in
            .app(CachedApp(meta: AppMeta(slug: "app-\(index)", name: name, icon: nil, tint: .blue, version: "1"),
                           cachedVersion: "1", isNew: false))
        } + [.settings]
    }

    private func titles(_ sections: SearchSections) -> [String?] { sections.sections.map(\.title) }

    private func names(_ sections: SearchSections, in all: [HomeItem]) -> [[String]] {
        sections.sections.map { section in section.ids.map { id in all.first { $0.id == id }!.name } }
    }

    // MARK: Sections

    /// Nothing typed: a section per first letter, A to Z then #, each
    /// alphabetical, Settings among them.
    @Test func anEmptyQueryIsSectionedByFirstLetter() {
        let all = items(["Timer", "habits", "Água", "2048", "Tip Jar", "Ébauche", "zebra", "Ångström", "Notes"])
        let sections = SearchSections(all, query: "")
        #expect(sections.isIndexed)
        #expect(titles(sections) == ["A", "E", "H", "N", "S", "T", "Z", "#"])
        #expect(names(sections, in: all) == [["Ångström", "Água"].sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                                              ["Ébauche"], ["habits"], ["Notes"], ["Settings"], ["Timer", "Tip Jar"], ["zebra"], ["2048"]])
    }

    @Test func lettersFoldCaseAndAccents() {
        #expect(SearchSections.letter(for: "émile") == "E")
        #expect(SearchSections.letter(for: "Ølsen") == "#" || SearchSections.letter(for: "Ølsen") == "O")
        #expect(SearchSections.letter(for: "  quiet") == "Q")
        #expect(SearchSections.letter(for: "42") == "#")
        #expect(SearchSections.letter(for: "★ Stars") == "#")
        #expect(SearchSections.letter(for: "") == "#")
        #expect(SearchSections.letter(for: "日記") == "#")
    }

    /// Typed: App Library drops the letters and the index for one list,
    /// best match first.
    @Test func typingGivesOneListBestFirst() {
        let all = items(["Habits", "Notes", "Todos", "Tip Jar", "Reset", "Mist"])
        let sections = SearchSections(all, query: "t")
        #expect(!sections.isIndexed)
        #expect(titles(sections) == [nil])
        #expect(names(sections, in: all) == [["Tip Jar", "Todos", "Habits", "Mist", "Notes", "Reset", "Settings"]])
        #expect(SearchSections(all, query: "xyz").sections.isEmpty)
        // Spaces alone are nothing typed.
        #expect(SearchSections(all, query: "  ").isIndexed)
    }

    // MARK: The index

    @Test func theIndexIsAlwaysEveryLetterThenHash() {
        #expect(SearchSections.indexTitles.count == 27)
        #expect(SearchSections.indexTitles.first == "A")
        #expect(SearchSections.indexTitles[25] == "Z")
        #expect(SearchSections.indexTitles.last == "#")
    }

    /// A letter with no apps goes to the next one that has some, or the last.
    @Test func anIndexLetterScrollsToItsSectionOrTheNext() {
        let all = items(["Budget", "Dice", "Timer", "2048"])
        let sections = SearchSections(all, query: "")
        #expect(titles(sections) == ["B", "D", "S", "T", "#"])
        #expect(sections.section(forIndexTitle: "A") == 0)
        #expect(sections.section(forIndexTitle: "B") == 0)
        #expect(sections.section(forIndexTitle: "C") == 1)
        #expect(sections.section(forIndexTitle: "S") == 2)
        #expect(sections.section(forIndexTitle: "U") == 4)
        #expect(sections.section(forIndexTitle: "#") == 4)
        #expect(SearchSections(items(["Budget"]), query: "").section(forIndexTitle: "Z") == 1)
        #expect(SearchSections(all, query: "t").section(forIndexTitle: "T") == nil)
    }

    @Test func theIndexViewFindsTheLetterUnderAFinger() {
        let index = SearchIndexView(frame: CGRect(x: 0, y: 0, width: 30, height: 600))
        index.layoutIfNeeded()
        let pitch = SearchMetrics.indexPitch
        let top = 300 - pitch * 27 / 2
        #expect(index.title(at: top + pitch / 2) == "A")
        #expect(index.title(at: top + pitch * 25.5) == "Z")
        #expect(index.title(at: top + pitch * 26.5) == "#")
        #expect(index.title(at: -50) == "A")
        #expect(index.title(at: 900) == "#")
    }

    // MARK: Return

    @Test func returnOpensTheTopMatchOnlyWhenSomethingIsTyped() {
        let all = items(["Habits", "Settle", "Reset"])
        #expect(SearchSections.topMatch(all, query: "set")?.name == "Settings")
        #expect(SearchSections.topMatch(all, query: "res")?.name == "Reset")
        #expect(SearchSections.topMatch(all, query: "") == nil)
        #expect(SearchSections.topMatch(all, query: "zzz") == nil)
    }

    // MARK: The list

    /// The UIKit list with the demo library: the right rows, and an icon
    /// frame to open a card from and land it on.
    @Test func theListShowsItsRowsAndKnowsWhereTheirIconsAre() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let apps = ["habits", "dice", "notes"].map { slug in
            CachedApp(meta: AppMeta(slug: slug, name: slug.capitalized, icon: nil, tint: .blue, version: "1"),
                      cachedVersion: slug == "notes" ? nil : "1", isNew: false)
        }
        let library = LibraryStore(demo: apps, cache: AppCache(root: folder))
        let model = HomeModel()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIViewController()
        window.rootViewController = host
        let list = SearchList(model: model, library: library)
        list.frame = host.view.bounds
        list.top = 90
        list.fieldTop = 694
        host.view.addSubview(list)
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<3 {
            list.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        #expect(list.shown.ids == ["dice", "habits", "notes", Layout.settings])
        let first = try #require(list.iconFrame(for: "dice", in: host.view))
        #expect(first.width == SearchMetrics.iconSize)
        #expect(abs(first.minX - SearchMetrics.iconLeading) < 0.01)
        // Under its letter: the header's band, then the row's padding.
        #expect(abs(first.minY - (90 + SearchMetrics.headerHeight + (SearchMetrics.rowHeight - SearchMetrics.iconSize) / 2)) < 0.5)
        let second = try #require(list.iconFrame(for: "habits", in: host.view))
        #expect(abs(second.minY - first.minY - SearchMetrics.rowHeight - SearchMetrics.headerHeight) < 0.5)

        model.query = "no"
        for _ in 0..<3 {
            list.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        #expect(list.shown.ids == ["notes"])
    }

    // MARK: The spring

    /// A spring retargeted mid-flight starts from where it is and as fast
    /// as it is going: sampling either side of the hand-over agrees.
    @Test func theSpringIsContinuousAcrossARetarget() {
        let spring = SwiftUI.Spring(duration: 0.45, bounce: 0.18)
        let mid = ValueSpring.sample(from: 0, to: 1, velocity: 3, spring: spring, time: 0.1)
        let after = ValueSpring.sample(from: mid.value, to: 0, velocity: mid.velocity, spring: spring, time: 0)
        #expect(abs(after.value - mid.value) < 0.0001)
        #expect(abs(after.velocity - mid.velocity) < 0.0001)
        let end = ValueSpring.sample(from: 0, to: 1, velocity: 0, spring: spring, time: 3)
        #expect(abs(end.value - 1) < 0.001 && abs(end.velocity) < 0.01)
    }

    @Test func rampsRunZeroToOneOverTheirPart() {
        #expect(SearchMetrics.listFade.ramp(0.2) == 0)
        #expect(SearchMetrics.listFade.ramp(0.75) == 0.5)
        #expect(SearchMetrics.listFade.ramp(1.2) == 1)
        // The grid is gone before the list starts to show: never both.
        #expect(SearchMetrics.homeFade.upperBound <= SearchMetrics.listFade.lowerBound)
    }
}
