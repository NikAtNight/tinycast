import Foundation

/// The quicklink waiting on its values, asked one at a time in the palette's search field.
@MainActor
@Observable
final class QuicklinkArgumentSession {
    private struct Request {
        let quicklink: Quicklink
        let arguments: [SnippetTemplateEngine.MissingArgument]
        var values: [String: String]
        /// Still unanswered, in the order the link declares them.
        var pending: [SnippetTemplateEngine.MissingArgument] {
            arguments.filter { values[$0.name] == nil }
        }
    }

    private var request: Request?
    /// The names answered here, newest last, so ⌫ steps back through them and never a seed.
    private var answered: [String] = []

    var isActive: Bool { request != nil }
    var quicklink: Quicklink? { request?.quicklink }

    /// The argument being asked for; nil once every one has an answer.
    var current: SnippetTemplateEngine.MissingArgument? { request?.pending.first }

    /// True when submitting opens rather than advances, which is what the ↵ pill announces.
    var isLastArgument: Bool { request?.pending.count == 1 }

    /// Nil once nothing is pending, which leaves the mode's own placeholder in the search field.
    var prompt: String? { current.map { "\($0.name)…" } }

    /// Every argument in order, paired with what has been entered so far.
    var progress: [(argument: SnippetTemplateEngine.MissingArgument, value: String?)] {
        guard let request else { return [] }
        return request.arguments.map { ($0, request.values[$0.name]) }
    }

    /// `values` are answers already known, such as a fallback row's query; they are never asked.
    func begin(
        quicklink: Quicklink, arguments: [SnippetTemplateEngine.MissingArgument],
        values: [String: String] = [:]
    ) {
        request = Request(quicklink: quicklink, arguments: arguments, values: values)
        answered = []
    }

    /// Records `value`, returning every value once the last one lands.
    func submit(_ value: String) -> [String: String]? {
        guard var request, let current else { return nil }
        request.values[current.name] = value
        answered.append(current.name)
        self.request = request
        return request.pending.isEmpty ? request.values : nil
    }

    /// Steps back, returning the held value so the field refills; nil at the first argument.
    func retreat() -> String? {
        guard var request, let name = answered.popLast() else { return nil }
        let previous = request.values.removeValue(forKey: name)
        self.request = request
        return previous
    }

    func cancel() {
        request = nil
        answered = []
    }
}
