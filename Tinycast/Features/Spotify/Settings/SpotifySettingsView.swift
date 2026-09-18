import SwiftUI

struct SpotifySettingsView: View {
    @Environment(SpotifyCoordinator.self) private var coordinator
    @State private var clientID = ""
    @State private var clientSecret = ""

    var body: some View {
        Form {
            Section {
                TextField(text: $clientID) {
                    SettingsRowTitle(.spotifyCredentials, "Client ID")
                }
                SecureField(text: $clientSecret) {
                    SettingsRowTitle(.spotifyCredentials, "Client Secret")
                }
                HStack {
                    Text(coordinator.store.hasCredentials
                        ? "Credentials are saved in Keychain." : "No credentials saved.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") {
                        coordinator.saveCredentials(clientID: clientID, clientSecret: clientSecret)
                        clientSecret = ""
                    }
                    .settingsEnabled(!clientID.isEmpty && !coordinator.isBusy)
                    Button("Remove", role: .destructive) {
                        coordinator.removeCredentials()
                        clientID = ""
                        clientSecret = ""
                    }
                    .settingsEnabled(coordinator.store.hasCredentials && !coordinator.isBusy)
                }
                HStack {
                    Button(action: coordinator.testConnection) {
                        SettingsRowTitle(.spotifyCredentials, "Test Connection")
                    }
                    .settingsEnabled(coordinator.store.hasCredentials && !coordinator.isBusy)
                    if let report = coordinator.connectionReport {
                        Text(report)
                            .foregroundStyle(coordinator.connectionSucceeded ? .secondary : Color.red)
                    }
                }
            } header: {
                SettingsSectionHeader(.spotifyCredentials)
            } footer: {
                Text("Create an app at developer.spotify.com to get a Client ID and Client Secret. "
                    + "Leave the secret blank to keep the saved one. Both stay in Keychain and never "
                    + "travel in a settings backup.")
            }
            FeatureCommandsSection(owner: .spotify, anchor: .spotifyCommands)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.spotify)
        .task { clientID = await coordinator.store.clientID() ?? "" }
        .onDisappear {
            clientSecret = ""
            coordinator.clearReport()
        }
    }
}
