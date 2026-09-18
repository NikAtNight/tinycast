import SwiftUI

struct InboxSettingsView: View {
    @Environment(InboxCoordinator.self) private var coordinator
    @State private var organizations = ""
    @State private var refreshMinutes = 5
    @State private var site = ""
    @State private var email = ""
    @State private var token = ""
    @State private var isSaving = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                TextField(text: $organizations) { SettingsRowTitle(.inboxGitHub, "Organizations") }
                Text("Comma-separated owners. An empty list stops GitHub fetching. Sign in using gh auth login.")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper(value: $refreshMinutes, in: 1...60) {
                    SettingsRowTitle(.inboxGitHub, "Refresh interval")
                    Text("\(refreshMinutes) minutes")
                }
                Button("Save Inbox settings") {
                    saveTask = Task {
                        isSaving = true
                        defer { isSaving = false }
                        _ = await coordinator.save(organizations: organizations, refreshMinutes: refreshMinutes)
                    }
                }
                Text("Enable Inbox and record its hotkey in Commands settings.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { SettingsSectionHeader(.inboxGitHub) }
            Section {
                TextField(text: $site) { SettingsRowTitle(.inboxJira, "Site URL") }
                TextField(text: $email) { SettingsRowTitle(.inboxJira, "Email") }
                SecureField(text: $token) { SettingsRowTitle(.inboxJira, "API token") }
                Text(coordinator.store.jiraConnected ? "Connected. Enter a token to replace this connection."
                     : "Disabled until a site URL, email, and API token are saved.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Save Jira connection") {
                    saveTask = Task {
                        isSaving = true
                        defer { isSaving = false }
                        if await coordinator.connectJira(site: site, email: email, token: token) { token = "" }
                    }
                }
                .disabled(site.isEmpty || email.isEmpty || token.isEmpty)
                if coordinator.store.jiraConnected {
                    Button("Disconnect Jira") {
                        saveTask = Task {
                            isSaving = true
                            defer { isSaving = false }
                            await coordinator.disconnectJira()
                            token = ""
                        }
                    }
                }
                Text("Site, email, and token are stored in Keychain and excluded from settings backups.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { SettingsSectionHeader(.inboxJira) }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.inbox)
        .disabled(isSaving || coordinator.store.isLoading)
        .task(id: coordinator.store.isLoading) {
            guard !coordinator.store.isLoading else { return }
            organizations = coordinator.store.preferences.organizations.joined(separator: ", ")
            refreshMinutes = coordinator.store.preferences.refreshMinutes
            site = coordinator.store.jiraSite
            email = coordinator.store.jiraEmail
        }
        .onDisappear { saveTask?.cancel(); token = "" }
    }
}
