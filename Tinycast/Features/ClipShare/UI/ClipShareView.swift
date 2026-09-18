import SwiftUI

struct ClipShareView: View {
    @Environment(ClipShareCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    let videos: [ClipShareVideo]
    let selection: Int
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let openActions: () -> Void

    private var selectedID: String? {
        videos.indices.contains(selection) ? videos[selection].id : nil
    }

    var body: some View {
        if let failure = coordinator.failure {
            EmptyResults(text: failure)
        } else if coordinator.isLoading && videos.isEmpty {
            Color.clear
        } else if videos.isEmpty {
            EmptyResults(text: "No recent uploads")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        SectionHeader(title: "Recent Uploads", isFirst: true)
                        ForEach(videos) { video in
                            ClipShareRow(video: video, selected: video.id == selectedID)
                                .selectionFrame(video.id == selectedID)
                                .contentShape(Rectangle())
                                .onRowClick(
                                    select: { select(video) }, activate: { coordinator.copy(video) })
                                .onRightClick { select(video); openActions() }
                                .accessibilityAction(named: "Copy Share URL") { coordinator.copy(video) }
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
                .scrollFollowsSelection(scroll, row: selectedID, atOrigin: selection == 0, proxy: proxy)
            }
        }
    }

    private func select(_ video: ClipShareVideo) {
        if let index = videos.firstIndex(where: { $0.id == video.id }) { onSelect(index) }
    }
}

private struct ClipShareRow: View {
    @Environment(\.metrics) private var metrics
    let video: ClipShareVideo
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            SymbolImage(name: "video", size: metrics.size.rowIcon)
                .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
            Text(video.title).font(metrics.typography.rowTitle).lineLimit(1)
            Spacer(minLength: 0)
            Text(video.status == .ready ? (video.shareEnabled ? "Ready" : "Link disabled") : video.status.rawValue)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(video.createdAt, style: .date)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill))
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
