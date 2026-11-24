import Kiln
import SwiftUI

/// What Kiln said when an app's source wouldn't compile, in a shape a person
/// can read or paste back to a model.
struct CompileError: Equatable {
    /// 1-based, when Kiln named a line.
    var line: Int?
    var message: String
    /// The lines around the failing one, numbered.
    var excerpt: [(number: Int, text: String)]
    /// Kiln's other errors, each "Line N: message", for Copy Error.
    var others: [String] = []

    static func == (a: CompileError, b: CompileError) -> Bool {
        a.line == b.line && a.message == b.message
    }

    /// Kiln reports `"Line N: message"`, sometimes followed by its own echo of
    /// the line, which is dropped here in favour of the wider excerpt.
    init(errors: [String], source: String) {
        let first = (errors.first ?? "The app has no view to show.").split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        if let match = first.firstMatch(of: /^Line (\d+): ?(.*)$/), let number = Int(match.1) {
            line = number
            message = String(match.2)
            let lines = source.components(separatedBy: "\n")
            if number >= 1, number <= lines.count {
                let range = max(number - RunnerMetrics.errorContext, 1)...min(number + RunnerMetrics.errorContext, lines.count)
                excerpt = range.map { ($0, lines[$0 - 1]) }
            } else {
                // A line past the end of the file: there is nothing to show around it.
                excerpt = []
            }
        } else {
            line = nil
            message = first
            excerpt = []
        }
    }

    /// What `Kiln.check` found: its first error, with the others for Copy Error.
    init(issue: KilnIssue, others: [String] = [], source: String) {
        self.init(errors: [issue.description], source: source)
        self.others = others
    }

    /// The excerpt as the screen shows it: each line's indent apart from
    /// its text, in spaces (tabs count as four), less the indent the
    /// lines share, and halved, so a line four levels deep still starts
    /// near the left on a phone. The report keeps the lines as they are.
    var shownExcerpt: [(number: Int, indent: Int, text: String)] {
        let lines = excerpt.map { line -> (Int, Int, String) in
            let text = line.text.replacingOccurrences(of: "\t", with: "    ")
            let indent = text.prefix { $0 == " " }.count
            let rest = String(text.dropFirst(indent))
            return (line.number, rest.isEmpty ? -1 : indent, rest)
        }
        let shared = lines.map(\.1).filter { $0 >= 0 }.min() ?? 0
        return lines.map { ($0.0, $0.1 < 0 ? 0 : ($0.1 - shared) / 2, $0.2) }
    }

    /// The error and its surroundings as text, for Copy Error.
    var report: String {
        var text = line.map { "Line \($0): \(message)" } ?? message
        if !excerpt.isEmpty {
            text += "\n\n" + excerpt.map { "\($0.number == line ? ">" : " ") \($0.number) | \($0.text)" }.joined(separator: "\n")
        }
        if !others.isEmpty {
            text += "\n\nAlso:\n" + others.map { "- " + $0 }.joined(separator: "\n")
        }
        return text
    }
}

/// What failed in an app, Shelf's way: shown in the card when Kiln can't
/// start an app or part of it fails while it runs, and as the New App
/// sheet itself when a reply can't be installed.
///
/// Read top to bottom, it says what happened and what to do: the app's
/// icon with a warning badge on it, "<name> stopped", Kiln's message in plain
/// words, then the code around the failing line (nothing technical is
/// hidden, but it's the quietest thing on the screen), and one button.
/// Copy for Agents copies a prompt a coding agent can fix the app with on
/// its own (`prompt`): the error, the code and, when there is one, a key
/// to install the fix with. The line under it says so.
///
/// The code wraps as an editor's does, each line under its own start, so
/// all of the failing line shows. It's marked by its number in red and a
/// tint, so the line number isn't said twice.
///
/// It scrolls when it's taller than the screen; its button stays at the
/// bottom, clear of the card's swipe up. It has no background of its own.
struct ErrorScreen: View {
    var face: IconFace
    var name: String
    var error: CompileError
    /// The line under the icon; by default "<name> couldn’t open".
    var title: String?
    /// What Copy for Agents copies. It may wait, for a key that lets the
    /// agent install its fix.
    var prompt: @MainActor () async -> String

    @State private var isPreparing = false
    @State private var didCopy = false
    @State private var copies = 0

    var body: some View {
        ScrollView {
            VStack(spacing: RunnerMetrics.errorSpacing) {
                heading
                if !error.excerpt.isEmpty {
                    excerpt
                }
                if !error.others.isEmpty {
                    others
                }
            }
            .padding(RunnerMetrics.errorPadding)
            .frame(maxWidth: RunnerMetrics.errorWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            action
                .padding(.horizontal, RunnerMetrics.errorPadding)
                .padding(.bottom, RunnerMetrics.errorButtonsBottom)
                .frame(maxWidth: RunnerMetrics.errorWidth)
        }
        .dynamicTypeSize(...ShelfMetrics.textSizeCap)
        .sensoryFeedback(.success, trigger: copies)
    }

    // MARK: Heading

    private var heading: some View {
        VStack(spacing: RunnerMetrics.errorHeadingSpacing) {
            IconImage(face: face, size: RunnerMetrics.errorIconSize)
                .frame(width: RunnerMetrics.errorIconSize, height: RunnerMetrics.errorIconSize)
                .overlay(alignment: .bottomTrailing) { badge }
                .padding(.bottom, RunnerMetrics.errorIconGap)
                .accessibilityHidden(true)
            Text(title ?? "\(name) couldn’t open")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(error.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
    }

    /// A warning on the icon's corner, cut out of it by a ring of the
    /// background, as a badge sits on a Home Screen icon.
    private var badge: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: RunnerMetrics.errorBadgeSize, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .red)
            .background(Circle().fill(Color(.systemBackground)).padding(-RunnerMetrics.errorBadgeRim))
            .offset(x: RunnerMetrics.errorBadgeOffset, y: RunnerMetrics.errorBadgeOffset)
            .accessibilityHidden(true)
    }

    // MARK: Code

    private var excerpt: some View {
        let shape = RoundedRectangle(cornerRadius: RunnerMetrics.codeRadius, style: .continuous)
        let widest = String(error.excerpt.last?.number ?? 0)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(error.shownExcerpt, id: \.number) { line in
                let failing = line.number == error.line
                HStack(alignment: .firstTextBaseline, spacing: RunnerMetrics.gutterGap) {
                    // Every gutter is as wide as the largest number, so the code lines up.
                    Text(widest).hidden().overlay(alignment: .trailing) {
                        Text(String(line.number))
                            .foregroundStyle(failing ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                            .fontWeight(failing ? .semibold : .regular)
                    }
                    // A line that wraps goes on under its own start, as in an
                    // editor: the indent is a column of its own.
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        if line.indent > 0 {
                            Text(String(repeating: "\u{00A0}", count: line.indent)).hidden()
                        }
                        Text(line.text.isEmpty ? " " : Self.breakable(line.text))
                            .foregroundStyle(failing ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, RunnerMetrics.codePadding)
                .padding(.vertical, RunnerMetrics.codeLineSpacing)
                .background(failing ? Color.red.opacity(RunnerMetrics.failingLineOpacity) : .clear)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(failing ? "Line \(line.number), where it failed: \(line.text)" : "Line \(line.number): \(line.text)")
            }
        }
        .padding(.vertical, RunnerMetrics.codePadding - RunnerMetrics.codeLineSpacing)
        .font(.footnote.monospaced())
        .textSelection(.enabled)
        .background(Color(.secondarySystemFill).opacity(RunnerMetrics.codeFillOpacity))
        .clipShape(shape)
    }

    /// Code wraps where code does, after a `(` or a member's `.` (`a.b`,
    /// `f().b`, not `.now`), rather than in the middle of a name, which the
    /// text system would hyphenate: a zero-width space gives it the place.
    static func breakable(_ code: String) -> String {
        var out = ""
        var previous: Character = " "
        for c in code {
            out.append(c)
            if c == "(" || (c == "." && (previous.isLetter || previous.isNumber || previous == ")" || previous == "]")) {
                out.append("\u{200B}")
            }
            previous = c
        }
        return out
    }

    /// Kiln's other errors, each with its line.
    private var others: some View {
        VStack(alignment: .leading, spacing: RunnerMetrics.codeLineSpacing * 2) {
            Text(error.others.count == 1 ? "1 more error" : "\(error.others.count) more errors")
                .font(.footnote.weight(.semibold))
            ForEach(Array(error.others.enumerated()), id: \.offset) { _, other in
                Text(other)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, RunnerMetrics.codePadding)
    }

    // MARK: Copy for Agents

    /// One button, as wide as the column, and what it's for under it.
    private var action: some View {
        VStack(spacing: RunnerMetrics.errorHeadingSpacing) {
            Button {
                copyForAgents()
            } label: {
                ZStack {
                    Label(didCopy ? "Copied" : "Copy for Agents", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .opacity(isPreparing ? 0 : 1)
                    // Getting the key that lets the agent install its fix.
                    if isPreparing { ProgressView() }
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: CreateMetrics.buttonHeight)
            }
            .buttonStyle(.glassProminent)
            .disabled(isPreparing)

            Text("Paste it into a coding agent, and it can fix \(name) for you.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: Motion.copiedStay)
            didCopy = false
        }
    }

    private func copyForAgents() {
        isPreparing = true
        Task {
            let text = await prompt()
            UIPasteboard.general.string = text
            isPreparing = false
            didCopy = true
            copies += 1
        }
    }
}
