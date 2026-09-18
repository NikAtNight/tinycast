import SwiftUI

struct TalixScreen: PaletteScreen {
    enum Row: Identifiable {
        case timer(TalixStore.Running)
        case entry(TalixStore.ListedEntry)
        case project(TalixProject)
        case log

        var id: String {
            switch self {
            case .timer: "timer"
            case .entry(let value): "entry:" + value.id
            case .project(let value): "project:" + value.id
            case .log: "log"
            }
        }
    }

    let coordinator: TalixCoordinator
    let vm: PaletteState
    let openActions: () -> Void
    let openArgumentOptions: (String) -> Void
    let metrics: InterfaceMetrics

    var rows: [Row] {
        let query = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if coordinator.pickingProject {
            return coordinator.store.projects.filter {
                query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.client?.name.localizedCaseInsensitiveContains(query) ?? false)
            }.map(Row.project)
        }
        var rows: [Row] = coordinator.store.running.map { [.timer($0)] } ?? []
        rows += coordinator.store.entries.filter {
            query.isEmpty || $0.entry.description.localizedCaseInsensitiveContains(query)
                || $0.project.name.localizedCaseInsensitiveContains(query)
        }.map(Row.entry)
        rows.append(.log)
        return rows
    }

    private func row(at index: Int) -> Row? { rows.indices.contains(index) ? rows[index] : nil }

    var primaryActionTitle: String {
        switch row(at: vm.selection) {
        case .timer: "Stop Timer"
        case .project: "Start Timer"
        default: "Log Time"
        }
    }

    func hasPrimaryAction(at selection: Int) -> Bool {
        guard !coordinator.isBusy else { return false }
        if case .entry = row(at: selection) { return false }
        return true
    }

    func secondary(at selection: Int) -> Bool { false }

    func activate(at selection: Int) {
        switch row(at: selection) {
        case .timer: coordinator.stopTimer()
        case .project(let project): coordinator.startTimer(project: project)
        case .log:
            vm.selection = rows.count - 1
            if !coordinator.projectId.isEmpty, !coordinator.duration.isEmpty, !coordinator.description.isEmpty {
                coordinator.logTime()
            }
        default: break
        }
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        var items: [PopoverMenuItem] = []
        if case .timer = row(at: selection) {
            items.append(PopoverMenuItem(title: "Stop and Log", icon: .symbol("stop.circle")) {
                coordinator.stopTimer()
            })
            items.append(PopoverMenuItem(title: "Discard Timer", icon: .symbol("trash")) {
                coordinator.discardTimer()
            })
        }
        items.append(PopoverMenuItem(title: "Refresh", icon: .symbol("arrow.clockwise")) {
            coordinator.refresh(force: true)
        })
        items.append(PopoverMenuItem(title: "Start Timer", icon: .symbol("timer")) {
            coordinator.show(pickingProject: true)
        })
        return PopoverMenuContent(header: "Talix", items: items)
    }

    func headerAccessory(at selection: Int, focus: FocusState<String?>.Binding) -> PaletteHeaderAccessory? {
        guard case .log = row(at: selection) else { return nil }
        let arguments: [SnippetTemplateEngine.MissingArgument] = [
            .init(name: "Project", options: ["Choose project"]),
            .init(name: "Duration", options: []), .init(name: "Description", options: [])
        ]
        let value: (String) -> Binding<String> = { name in
            switch name {
            case "Project":
                Binding(get: {
                    coordinator.store.projects.first { $0.id == coordinator.projectId }?.name ?? ""
                }, set: { _ in })
            case "Duration": Binding(get: { coordinator.duration }, set: { coordinator.duration = $0 })
            default: Binding(get: { coordinator.description }, set: { coordinator.description = $0 })
            }
        }
        return PaletteHeaderAccessory(
            width: QuicklinkArgumentsRow.totalWidth(for: arguments, hasIcon: false, metrics: metrics),
            fieldNames: arguments.map(\.name),
            firstIncompleteField: arguments.first { value($0.name).wrappedValue.isEmpty }?.name,
            optionsMenu: { name in
                guard name == "Project" else { return nil }
                return PopoverMenuContent(header: "Project", items: coordinator.store.projects.map { project in
                    PopoverMenuItem(title: "\(project.name) · \(project.client?.name ?? project.id)",
                        icon: coordinator.projectId == project.id ? .symbol("checkmark") : .blank) {
                        coordinator.projectId = project.id
                    }
                })
            }, placement: .besideSearchField,
            view: AnyView(QuicklinkArgumentsRow(arguments: arguments, symbol: nil, value: value,
                focused: focus, openOptions: openArgumentOptions, onSubmit: coordinator.logTime)))
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(TalixList(rows: rows, selection: selection, scroll: scroll,
            onActivate: activate, onActions: { index in vm.selection = index; openActions() })
            .environment(coordinator))
    }
}
