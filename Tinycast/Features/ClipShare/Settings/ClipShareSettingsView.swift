import SwiftUI

struct ClipShareSettingsView: View {
    @Environment(ClipShareCoordinator.self) private var coordinator
    @State private var baseURL = ""
    @State private var token = ""

    var body: some View {
        Form {
            Section {
                TextField(text: $baseURL) {
                    SettingsRowTitle(.clipShareConnection, "Base URL")
                }
                SecureField(text: $token) {
                    SettingsRowTitle(.clipShareConnection, "Token")
                }
                Button("Save Connection") {
                    if coordinator.saveConnection(baseURL: baseURL, token: token) { token = "" }
                }
                .settingsEnabled(!coordinator.isUploading)
                Button("Remove Saved Token", role: .destructive) { coordinator.removeToken() }
                    .settingsEnabled(!coordinator.isUploading)
            } header: {
                SettingsSectionHeader(.clipShareConnection)
            } footer: {
                Text("Leave Token blank to keep the saved token. Tokens stay in Keychain. "
                    + "Set command hotkeys and visibility in the Commands pane.")
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.clipShare)
        .onAppear { baseURL = coordinator.baseURL }
        .onDisappear { token = "" }
    }
}
