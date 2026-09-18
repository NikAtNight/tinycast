import SwiftUI

struct SpotifyView: View {
    @Environment(SpotifyCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    let rows: [SpotifyItem]
    let selection: Int
    let scroll: ScrollIntent
    let vm: PaletteState
    let openActions: () -> Void

    private var selected: SpotifyItem? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    var body: some View {
        Group {
            if !coordinator.store.hasCredentials {
                SpotifyCredentialsNeeded(openSettings: coordinator.openSettings)
            } else if let error = coordinator.session.error {
                EmptyResults(text: error)
            } else if rows.isEmpty {
                EmptyResults(text: emptyText)
            } else {
                list
            }
        }
        .onChange(of: vm.query, initial: true) { _, query in coordinator.session.search(query) }
        .task(id: vm.isVisible) {
            if vm.isVisible {
                await coordinator.store.refreshCredentialPresence()
            } else {
                coordinator.session.reset()
            }
        }
        .onDisappear { coordinator.session.reset() }
    }

    private var emptyText: String {
        if SpotifyAPI.normalizedQuery(vm.query) == nil { return "Type to search Spotify" }
        return coordinator.session.isSearching ? "Searching Spotify…" : "No results on Spotify"
    }

    /// Each kind's rows with their flat indices, so a header never consumes a selection slot.
    private var sections: [(kind: SpotifyItem.Kind, rows: [(index: Int, item: SpotifyItem)])] {
        var next = 0
        return SpotifyItem.Kind.allCases.compactMap { kind in
            let items = coordinator.session.results.items(of: kind)
            guard !items.isEmpty else { return nil }
            let indexed = items.enumerated().map { (index: next + $0.offset, item: $0.element) }
            next += items.count
            return (kind, indexed)
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sections, id: \.kind) { section in
                        SectionHeader(title: section.kind.sectionTitle, isFirst: section.rows.first?.index == 0)
                        ForEach(section.rows, id: \.item.uri) { row in
                            SpotifyRow(item: row.item, selected: row.index == selection)
                                .selectionFrame(row.index == selection)
                                .contentShape(Rectangle())
                                .onRowClick(
                                    select: { vm.selection = row.index },
                                    activate: { coordinator.play(row.item) })
                                .onRightClick {
                                    vm.selection = row.index
                                    openActions()
                                }
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
            .scrollFollowsSelection(scroll, row: selected?.uri, atOrigin: selection == 0, proxy: proxy)
        }
    }
}

private struct SpotifyRow: View {
    @Environment(\.metrics) private var metrics
    let item: SpotifyItem
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            SpotifyArtworkView(item: item)
                .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
            Text(item.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            Text(item.subtitle)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(item.kind.label)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(selected ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear))
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The kind's glyph until the 64 px artwork is on disk, then the same tile every app row draws.
private struct SpotifyArtworkView: View {
    let item: SpotifyItem
    @State private var path: String?

    var body: some View {
        Group {
            if let path {
                EntryIconView(source: .artwork(path: path, extent: IconCache.appIconExtent))
            } else {
                EntryIconView(source: .symbol(item.kind.symbol))
            }
        }
        .task(id: item.artworkURL) {
            guard let url = item.artworkURL else {
                path = nil
                return
            }
            let found = await SpotifyArtworkCache.path(id: item.id, url: url)
            guard !Task.isCancelled else { return }
            path = found
        }
    }
}

private struct SpotifyCredentialsNeeded: View {
    @Environment(\.metrics) private var metrics
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: metrics.spacing.md) {
            Image(systemName: "music.note.list").font(.largeTitle)
                .symbolRenderingMode(.hierarchical).foregroundStyle(.tertiary)
            Text("Spotify needs a Client ID and Client Secret to search.")
                .foregroundStyle(.secondary)
            Button("Open Spotify Settings", action: openSettings)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
