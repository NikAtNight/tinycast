import SwiftUI

struct ReposSettingsView: View {
    @Environment(ReposCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @State private var patternDraft = ""

    var body: some View {
        Form {
            FeatureCommandsSection(owner: .repos, anchor: .reposCommands)
            roots
            options
            ignorePatterns
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.repos)
    }

    private var roots: some View {
        Section {
            ForEach(settings.reposRoots, id: \.self) { root in
                LabeledContent {
                    Button {
                        coordinator.setRoots(settings.reposRoots.filter { $0 != root })
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(root)")
                } label: {
                    Label(root, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Button("Add Folder…") { coordinator.addRoots() }
        } header: {
            SettingsSectionHeader(.reposRoots)
        } footer: {
            Text("Scan these folders for repositories. An empty list scans nothing.")
        }
    }

    private var options: some View {
        Section {
            Picker(selection: Binding(
                get: { settings.reposDefaultAction },
                set: { coordinator.setDefaultAction($0) }
            )) {
                Text("Supacode").tag("supacode")
                Text("Ghostty").tag("ghostty")
            } label: {
                SettingsRowTitle(.reposOptions, "Default open action")
                Text("What Return does on a repository row.")
            }
            Toggle(isOn: Binding(
                get: { settings.reposShowWorktrees },
                set: { coordinator.setShowWorktrees($0) }
            )) {
                SettingsRowTitle(.reposOptions, "Show worktrees")
                Text("Include linked worktrees beneath their repositories.")
            }
        } header: {
            SettingsSectionHeader(.reposOptions)
        }
    }

    private var ignorePatterns: some View {
        Section {
            ForEach(settings.reposIgnorePatterns, id: \.self) { pattern in
                LabeledContent {
                    Button {
                        coordinator.setIgnorePatterns(
                            settings.reposIgnorePatterns.filter { $0 != pattern })
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(pattern)")
                } label: {
                    Text(pattern).lineLimit(1).truncationMode(.middle)
                }
            }
            TextField("Add pattern…", text: $patternDraft)
                .onSubmit(addPattern)
        } header: {
            SettingsSectionHeader(.reposIgnorePatterns)
        } footer: {
            Text("Skip matching folder names. Use * to match any text, such as *-backup-*.")
        }
    }

    private func addPattern() {
        let pattern = patternDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        coordinator.setIgnorePatterns(settings.reposIgnorePatterns + [pattern])
        patternDraft = ""
    }
}
