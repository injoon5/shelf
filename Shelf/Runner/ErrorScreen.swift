import SwiftUI

/// What Kiln said when an app's source wouldn't compile, in a shape a person
/// can read or paste back to a model.
struct CompileError: Equatable {
    /// 1-based, when Kiln named a line.
    var line: Int?
    var message: String
    /// The lines around the failing one, numbered.
    var excerpt: [(number: Int, text: String)]

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

    /// The error and its surroundings as text, for Copy Error.
    var report: String {
        var text = line.map { "Line \($0): \(message)" } ?? message
        if !excerpt.isEmpty {
            text += "\n\n" + excerpt.map { "\($0.number == line ? ">" : " ") \($0.number) | \($0.text)" }.joined(separator: "\n")
        }
        return text
    }
}

/// Shown inside the runner when an app can't start. The icon, one line, the
/// code around the failure and Kiln's message; dragging down closes it.
struct ErrorScreen: View {
    var face: IconFace
    var name: String
    var error: CompileError

    var body: some View {
        ScrollView {
            VStack(spacing: RunnerMetrics.errorSpacing) {
                IconArt(face: face, size: RunnerMetrics.errorIconSize)
                Text("\(name) couldn’t open")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                if !error.excerpt.isEmpty {
                    excerpt
                }
                Text(error.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: error.excerpt.isEmpty ? .center : .leading)
                    .multilineTextAlignment(error.excerpt.isEmpty ? .center : .leading)
                    .textSelection(.enabled)
            }
            .padding(RunnerMetrics.errorPadding)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var excerpt: some View {
        let shape = RoundedRectangle(cornerRadius: RunnerMetrics.codeRadius, style: .continuous)
        let widest = String(error.excerpt.last?.number ?? 0)
        return VStack(spacing: 0) {
            ForEach(error.excerpt, id: \.number) { line in
                HStack(alignment: .firstTextBaseline, spacing: RunnerMetrics.gutterGap) {
                    // Every gutter is as wide as the largest number, so the code lines up.
                    Text(widest).hidden().overlay(alignment: .trailing) {
                        Text(String(line.number)).foregroundStyle(.secondary)
                    }
                    Text(line.text.isEmpty ? " " : line.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, RunnerMetrics.codePadding)
                .padding(.vertical, RunnerMetrics.codeLineSpacing)
                .background(line.number == error.line ? Color.red.opacity(RunnerMetrics.failingLineOpacity) : .clear)
            }
        }
        .font(.footnote.monospaced())
        .padding(.vertical, RunnerMetrics.codePadding - RunnerMetrics.codeLineSpacing)
        .background(Color(.secondarySystemBackground))
        .clipShape(shape)
    }
}
