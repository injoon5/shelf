import Foundation

/// What search's list shows, apart from any view: App Library's sections.
///
/// With nothing typed, every icon (Settings included), one section per first
/// letter, A to Z, then # for names that don't start with a letter, each
/// alphabetical, under its letter, with the A–Z # index beside them. Once
/// something is typed, App Library drops the letters and the index for one
/// list of matches, best first (`[HomeItem].matching`).
struct SearchSections: Equatable {
    struct Section: Equatable {
        /// The letter over the section, or nil for the matches of a query.
        var title: String?
        var ids: [String]
    }

    var sections: [Section]

    /// Whether the letters and the index show: only with nothing typed.
    var isIndexed: Bool { sections.first?.title != nil }

    /// The index's titles, every one of them always, as App Library's: a
    /// letter with no apps still has its place.
    static let indexTitles: [String] = (UnicodeScalar("A").value...UnicodeScalar("Z").value)
        .map { String(Character(UnicodeScalar($0)!)) } + [other]

    /// The section for names that don't start with a letter A–Z.
    static let other = "#"

    init(_ items: [HomeItem], query: String) {
        let matches = items.matching(query)
        guard query.trimmingCharacters(in: .whitespaces).isEmpty else {
            sections = matches.isEmpty ? [] : [Section(title: nil, ids: matches.map(\.id))]
            return
        }
        var byLetter: [String: [String]] = [:]
        for item in matches {
            byLetter[Self.letter(for: item.name), default: []].append(item.id)
        }
        sections = Self.indexTitles.compactMap { title in
            byLetter[title].map { Section(title: title, ids: $0) }
        }
    }

    /// The section a name goes under: its first letter, without case or
    /// accents ("é" is E), or # for a digit, a symbol, or a letter outside A–Z.
    static func letter(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return other }
        let folded = String(first).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
        guard folded.count == 1, let scalar = folded.unicodeScalars.first,
              scalar.value >= UnicodeScalar("A").value, scalar.value <= UnicodeScalar("Z").value else { return other }
        return folded
    }

    /// The section a touch on the index's `title` scrolls to: that letter's,
    /// or the next one after it that has apps, or failing that the last.
    func section(forIndexTitle title: String) -> Int? {
        guard isIndexed, !sections.isEmpty, let wanted = Self.indexTitles.firstIndex(of: title) else { return nil }
        for (index, section) in sections.enumerated() {
            if let place = section.title.flatMap(Self.indexTitles.firstIndex(of:)), place >= wanted { return index }
        }
        return sections.count - 1
    }

    /// Every id, in order: the first is what Return opens.
    var ids: [String] { sections.flatMap(\.ids) }

    /// What Return opens: the best match for what's typed. Nothing typed,
    /// there's no best match, and Return does nothing.
    static func topMatch(_ items: [HomeItem], query: String) -> HomeItem? {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return items.matching(query).first
    }
}
