import SwiftUI

/// The inline argument fields beside the search field, one per `{argument}` the link declares.
struct QuicklinkArgumentsRow: View {
    @Environment(\.metrics) private var metrics
    let arguments: [SnippetTemplateEngine.MissingArgument]
    /// The quicklink's glyph, anchoring the strip to the row; nil where that row is already listed.
    let symbol: String?
    /// Binding factory keyed by argument name — the values live in `PaletteState.commandArguments`.
    let value: (String) -> Binding<String>
    @FocusState.Binding var focused: String?
    /// A field declaring `options=` is chosen, not typed, so it hands the palette its menu instead.
    let openOptions: (String) -> Void
    /// ↵ from inside a field opens the quicklink, like ↵ on the row itself.
    let onSubmit: () -> Void
    /// Fields the caret has left behind. Nothing is owed until one was visited and not answered.
    @State private var visited: Set<String> = []

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            if let symbol {
                Image(nsImage: IconCache.symbolIcon(named: symbol))
                    .resizable()
                    .frame(width: Self.height(metrics), height: Self.height(metrics))
            }
            ForEach(arguments, id: \.name) { argument in
                if argument.options.isEmpty {
                    ArgumentField(
                        argument: argument, text: value(argument.name),
                        isFocused: focused == argument.name,
                        isOwed: visited.contains(argument.name), onSubmit: onSubmit
                    )
                    .focused($focused, equals: argument.name)
                } else {
                    ArgumentChoiceField(
                        argument: argument, text: value(argument.name),
                        isFocused: focused == argument.name,
                        isOwed: visited.contains(argument.name),
                        onOpen: { openOptions(argument.name) }
                    )
                    .focused($focused, equals: argument.name)
                }
            }
        }
        // Only a field the caret has been in and left may say it is still owed a value.
        .onChange(of: focused) { previous, _ in
            if let previous, arguments.contains(where: { $0.name == previous }) {
                visited.insert(previous)
            }
        }
    }

    static func height(_ metrics: InterfaceMetrics) -> CGFloat { metrics.scaled(26) }

    /// The header shrinks the search field to exactly the room left over.
    static func totalWidth(
        for arguments: [SnippetTemplateEngine.MissingArgument], hasIcon: Bool,
        metrics: InterfaceMetrics
    ) -> CGFloat {
        let fields = arguments.reduce(0) { $0 + fieldWidth(for: $1, metrics: metrics) }
        let gaps = CGFloat(arguments.count + (hasIcon ? 0 : -1)) * metrics.spacing.xs
        return fields + gaps + (hasIcon ? height(metrics) : 0)
    }

    static func fieldWidth(
        for argument: SnippetTemplateEngine.MissingArgument, metrics: InterfaceMetrics
    ) -> CGFloat {
        let name = CGFloat(argument.name.count) * metrics.scaled(9)
        return min(max(name + metrics.scaled(24), metrics.scaled(96)), metrics.scaled(220))
    }
}

/// Shared chrome, so a typed field and a chosen one read as the same control. It draws no edge:
/// the field continues the query, and only the caret's faint highlight says where typing lands.
private struct ArgumentFieldChrome: ViewModifier {
    @Environment(\.metrics) private var metrics
    let argument: SnippetTemplateEngine.MissingArgument
    let isFocused: Bool
    /// Visited, left, and still empty — the only state that earns a warning edge.
    let isOwed: Bool
    @Binding var hovered: Bool

    func body(content: Content) -> some View {
        content
            .frame(width: QuicklinkArgumentsRow.fieldWidth(for: argument, metrics: metrics))
            .padding(.horizontal, metrics.spacing.sm)
            .frame(height: QuicklinkArgumentsRow.height(metrics))
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
            )
            .onHover { hovered = $0 }
            .help(isOwed ? "\(argument.name), required" : argument.name)
    }

    private var fill: Color {
        if isFocused { return Theme.Colors.rowHover }
        return .clear
    }
}

/// The prompt's colour: a field left behind unanswered warns in the text itself, not with an edge.
private func promptColor(isOwed: Bool) -> Color {
    isOwed ? Theme.Colors.destructive.opacity(0.8) : Theme.Colors.textTertiary
}

private struct ArgumentField: View {

    @Environment(\.metrics) private var metrics
    let argument: SnippetTemplateEngine.MissingArgument
    @Binding var text: String
    let isFocused: Bool
    let isOwed: Bool
    let onSubmit: () -> Void
    @State private var hovered = false

    var body: some View {
        TextField(
            "", text: $text,
            prompt: Text(argument.name).foregroundStyle(promptColor(isOwed: isOwed && text.isEmpty))
        )
        .textFieldStyle(.plain)
        .font(metrics.typography.searchField)
        .foregroundStyle(Theme.Colors.textPrimary)
        .tint(Theme.Colors.textPrimary)
        .onSubmit(onSubmit)
        .multilineTextAlignment(.leading)
        .modifier(
            ArgumentFieldChrome(
                argument: argument, isFocused: isFocused, isOwed: isOwed && text.isEmpty,
                hovered: $hovered))
    }
}

/// An `options=` argument: the value is picked from the palette's own menu, never typed.
private struct ArgumentChoiceField: View {
    @Environment(\.metrics) private var metrics
    let argument: SnippetTemplateEngine.MissingArgument
    @Binding var text: String
    let isFocused: Bool
    let isOwed: Bool
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: metrics.spacing.xxs) {
            Text(text.isEmpty ? argument.name : text)
                .font(metrics.typography.searchField)
                .foregroundStyle(
                    text.isEmpty ? promptColor(isOwed: isOwed) : Theme.Colors.textPrimary
                )
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .modifier(
            ArgumentFieldChrome(
                argument: argument, isFocused: isFocused, isOwed: isOwed && text.isEmpty,
                hovered: $hovered)
        )
        .contentShape(Rectangle())
        .focusable()
        // The chrome draws the focused fill, so AppKit's blue ring would be a second cue.
        .focusEffectDisabled()
        .onTapGesture(perform: onOpen)
        .onKeyPress(.return) {
            onOpen()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(argument.name))
        .accessibilityValue(Text(text.isEmpty ? "No value" : text))
        .accessibilityHint(Text("Opens a list of choices"))
        .accessibilityAddTraits(.isButton)
    }
}
