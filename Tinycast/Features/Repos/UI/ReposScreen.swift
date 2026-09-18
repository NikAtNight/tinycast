import SwiftUI

struct ReposScreen: PaletteScreen {
    let index: RepoIndex
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [Repository] {
        RepoQuery.filter(
            index.repositories, query: vm.query, showWorktrees: core.settings.reposShowWorktrees)
    }

    var primaryActionTitle: String {
        core.settings.reposDefaultAction == "ghostty" ? "Open in Ghostty" : "Open in Supacode"
    }

    private func repository(at selection: Int) -> Repository? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    func activate(at selection: Int) {
        guard let repo = repository(at: selection) else { return }
        core.reposCoordinator.open(repo)
    }

    func secondary(at selection: Int) -> Bool {
        guard let repo = repository(at: selection) else { return false }
        core.reposCoordinator.reveal(repo)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard shortcut == .copyPath, let repo = repository(at: selection) else { return false }
        core.reposCoordinator.copyPath(repo)
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let repo = repository(at: selection) else { return nil }
        let coordinator = core.reposCoordinator
        var items = [
            PopoverMenuItem(
                title: "Open in Supacode",
                icon: Self.applicationIcon("/Applications/supacode.app", fallback: "chevron.left.forwardslash.chevron.right")
            ) { coordinator.openSupacode(repo) },
            PopoverMenuItem(
                title: "Open in Ghostty", icon: Self.applicationIcon("/Applications/Ghostty.app", fallback: "terminal")
            ) { coordinator.openGhostty(repo) },
            PopoverMenuItem(title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵") {
                coordinator.reveal(repo)
            }
        ]
        if repo.remoteURL != nil {
            items.append(PopoverMenuItem(title: "Open Remote", systemImage: "globe") {
                coordinator.openRemote(repo)
            })
        }
        items.append(PopoverMenuItem(
            title: "Copy Path", systemImage: "doc.on.clipboard", shortcut: "⌃⌘C"
        ) { coordinator.copyPath(repo) })
        if repo.devScript != nil {
            items.append(PopoverMenuItem(
                title: "Start dev server", systemImage: "play", startsSection: true
            ) { coordinator.startDevServer(repo) })
        }
        items.append(PopoverMenuItem(
            title: "Refresh Repositories", systemImage: "arrow.clockwise", startsSection: true
        ) { coordinator.refresh() })
        return PopoverMenuContent(header: repo.name, items: items)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            ReposList(
                repositories: rows, index: index, isVisible: vm.isVisible,
                selectedID: repository(at: selection)?.id,
                scroll: scroll,
                onSelect: { repo in vm.selection = rows.firstIndex { $0.id == repo.id } ?? 0 },
                onActivate: { core.reposCoordinator.open($0) },
                onActions: { repo in
                    vm.selection = rows.firstIndex { $0.id == repo.id } ?? 0
                    openActions()
                }
            )
            .task(id: vm.isVisible) {
                if vm.isVisible {
                    await core.reposCoordinator.prepare()
                } else {
                    core.reposCoordinator.endShow()
                }
            }
            .onChange(of: index.repositories) { previous, _ in
                let previousRows = RepoQuery.filter(
                    previous, query: vm.query, showWorktrees: core.settings.reposShowWorktrees)
                guard previousRows.indices.contains(vm.selection),
                    let position = rows.firstIndex(where: { $0.id == previousRows[vm.selection].id })
                else { return }
                vm.selection = position
            }
            .onDisappear { core.reposCoordinator.endShow() })
    }

    private static func applicationIcon(_ path: String, fallback: String) -> PopoverMenuIcon {
        FileManager.default.fileExists(atPath: path) ? .file(path: path) : .symbol(fallback)
    }
}

private struct ReposList: View {
    @Environment(\.metrics) private var metrics
    let repositories: [Repository]
    let index: RepoIndex
    let isVisible: Bool
    let selectedID: Repository.ID?
    let scroll: ScrollIntent
    let onSelect: (Repository) -> Void
    let onActivate: (Repository) -> Void
    let onActions: (Repository) -> Void

    var body: some View {
        if repositories.isEmpty {
            EmptyResults(text: emptyMessage)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(repositories.enumerated()), id: \.element.id) { offset, repo in
                            if offset == 0 || repositories[offset - 1].rootPath != repo.rootPath {
                                SectionHeader(
                                    title: URL(fileURLWithPath: repo.rootPath).lastPathComponent,
                                    isFirst: offset == 0)
                            }
                            RepoRow(repository: repo, selected: repo.id == selectedID)
                                .selectionFrame(repo.id == selectedID)
                                .contentShape(Rectangle())
                                .onRowClick(select: { onSelect(repo) }, activate: { onActivate(repo) })
                                .onRightClick { onActions(repo) }
                                .task(id: "\(repo.id)|\(index.showRevision)|\(isVisible)") {
                                    guard isVisible else { return }
                                    await index.loadStatus(repo)
                                }
                        }
                    }
                    .padding(.horizontal, metrics.spacing.md)
                    .padding(.top, metrics.spacing.xs)
                    .padding(.bottom, metrics.spacing.md)
                    .hideNativeScrollers()
                    .scrollOriginAnchor()
                }
                .edgeDissolve()
                .thinScrollbar()
                .scrollFollowsSelection(
                    scroll, row: selectedID,
                    atOrigin: selectedID != nil && selectedID == repositories.first?.id, proxy: proxy)
            }
        }
    }

    private var emptyMessage: String {
        if index.isScanning { return "Scanning repositories…" }
        if let error = index.error { return error }
        return "No repositories found"
    }
}

private struct RepoRow: View {
    @Environment(\.metrics) private var metrics
    let repository: Repository
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var subtitle: String {
        let name = repository.org.map { "\($0)/\(repository.name)" } ?? repository.name
        return [name, repository.branch].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            if repository.isWorktree {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
                    .frame(width: metrics.size.rowIcon)
            }
            Image(systemName: "folder.badge.gearshape")
                .font(metrics.typography.rowTitle)
                .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                Text(repository.name)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                Text(subtitle)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if repository.isDirty == true {
                Text("●")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Uncommitted changes")
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill))
        .armedHover($hovered)
        .help(repository.path)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }}
