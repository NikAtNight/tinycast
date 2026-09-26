import SwiftUI

/// The argument form: the search field is the input, one value at a time, like a custom command.
struct QuicklinkArgumentsScreen: PaletteScreen {
    struct Row: Identifiable { let id: Int }

    let session: QuicklinkArgumentSession
    let core: AppCore
    let vm: PaletteState

    var rows: [Row] { [] }
    /// One value at a time into the search field, so ↵ still acts with no rows to select.
    var actsWithoutRows: Bool { true }

    var primaryActionTitle: String { session.isLastArgument ? "Open Quicklink" : "Next" }

    /// Nothing opens on an empty value, which also hides the footer pill.
    func hasPrimaryAction(at selection: Int) -> Bool {
        session.current != nil && !vm.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func secondary(at selection: Int) -> Bool { false }

    func activate(at selection: Int) {
        guard hasPrimaryAction(at: selection) else { return }
        core.quicklinkCoordinator.submitQuicklinkArgument(vm.query)
        // More to answer: clear the field so the next argument starts on an empty one.
        if session.isActive { vm.query = "" }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(QuicklinkArgumentsView(session: session))
    }
}

/// The chip before the search field: which quicklink the typed value belongs to.
struct QuicklinkArgumentsChip: View {
    @Environment(\.metrics) private var metrics
    let quicklink: Quicklink
    let icon: EntryIcon

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            EntryIconView(source: icon)
                .frame(width: metrics.scaled(18), height: metrics.scaled(18))
            Text(quicklink.name)
                .font(metrics.typography.searchField)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Filling \(quicklink.name)"))
    }
}

/// The link it will open, and one row per value it still wants.
struct QuicklinkArgumentsView: View {
    @Environment(\.metrics) private var metrics
    let session: QuicklinkArgumentSession

    private static let markSize: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.lg) {
            if let quicklink = session.quicklink {
                Text(quicklink.link)
                    .font(metrics.typography.code)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                ForEach(Array(session.progress.enumerated()), id: \.offset) { _, entry in
                    row(entry.argument, value: entry.value)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.spacing.md * 2)
        .padding(.top, metrics.spacing.md)
        .padding(.bottom, metrics.spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ argument: SnippetTemplateEngine.MissingArgument, value: String?) -> some View {
        HStack(spacing: metrics.spacing.sm) {
            Image(systemName: value == nil ? "circle" : "checkmark.circle.fill")
                .font(.system(size: Self.markSize))
                .foregroundStyle(value == nil ? Theme.Colors.textTertiary : Theme.Colors.success)
            Text(argument.name)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
            if let value {
                Text(value)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if !argument.options.isEmpty {
                Text(argument.options.joined(separator: " · "))
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}
