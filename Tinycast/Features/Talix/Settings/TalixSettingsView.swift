import SwiftUI

struct TalixSettingsView: View {
    @Environment(AppCore.self) private var core

    var body: some View {
        TalixSettingsForm().environment(core.talixCoordinator)
    }
}

private struct TalixSettingsForm: View {
    @Environment(TalixCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @State private var apiKey = ""

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                SecureField(text: $apiKey) {
                    SettingsRowTitle(.talixConnection, "API key")
                }
                HStack {
                    Text(coordinator.hasKey ? "A key is saved in Keychain." : "No key saved.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save Key") {
                        coordinator.saveKey(apiKey)
                        apiKey = ""
                    }
                    .settingsEnabled(!apiKey.isEmpty && !coordinator.isBusy && coordinator.store.running == nil)
                    Button("Remove Key") { coordinator.saveKey("") }
                        .settingsEnabled(coordinator.hasKey && !coordinator.isBusy && coordinator.store.running == nil)
                }
                Picker(selection: $settings.talixEnvironment) {
                    ForEach(TalixEnvironment.allCases, id: \.self) { environment in
                        Text(environment.title).tag(environment)
                    }
                } label: { SettingsRowTitle(.talixConnection, "Environment") }
                .settingsEnabled(!coordinator.isBusy && !coordinator.store.isLoading)
                Button("Refresh Projects") { coordinator.refresh(force: true) }
                    .settingsEnabled(!coordinator.store.isLoading && coordinator.hasKey)
                if let error = coordinator.store.errorMessage { Text(error).foregroundStyle(.secondary) }
            } header: { SettingsSectionHeader(.talixConnection) }

            Section {
                Picker(selection: $settings.talixRounding) {
                    Text("None").tag(TalixTimer.Rounding.none)
                    Text("Round up to 6 minutes").tag(TalixTimer.Rounding.sixMinutes)
                    Text("Round up to 15 minutes").tag(TalixTimer.Rounding.fifteenMinutes)
                } label: { SettingsRowTitle(.talixDefaults, "Rounding") }
                Toggle(isOn: $settings.talixDefaultBillable) {
                    SettingsRowTitle(.talixDefaults, "Billable by default")
                }
            } header: { SettingsSectionHeader(.talixDefaults) }

            Section {
                if coordinator.store.projects.isEmpty {
                    Text("Save a key and refresh projects to set hourly rates.").foregroundStyle(.secondary)
                }
                ForEach(coordinator.store.projects) { project in
                    TalixProjectSettingsRow(project: project)
                        .id(coordinator.rateKey(project.id))
                }
            } header: { SettingsSectionHeader(.talixProjects) }
            footer: { Text("Projects without a server rate require an explicit hourly rate. Zero is allowed.") }
            FeatureCommandsSection(owner: .talix, anchor: .talixCommands)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.talix)
        .onAppear { coordinator.refresh() }
        .onChange(of: settings.talixEnvironment) { _, _ in coordinator.refresh(force: true) }
    }
}

private struct TalixProjectSettingsRow: View {
    @Environment(TalixCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    let project: TalixProject
    @State private var rate = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text(project.name)
            if let client = project.client { Text(client.name).foregroundStyle(.secondary) }
            TextField("Hourly rate", text: $rate)
                .settingsEnabled(project.rate == nil)
                .onChange(of: rate) { _, value in
                    let key = coordinator.rateKey(project.id)
                    if value.isEmpty {
                        settings.talixProjectRates[key] = nil
                    } else if let number = Double(value), number.isFinite, number >= 0 {
                        settings.talixProjectRates[key] = number
                    } else { settings.talixProjectRates[key] = nil }
                }
            if !rate.isEmpty, Double(rate).map({ !$0.isFinite || $0 < 0 }) ?? true {
                Text("Enter a nonnegative number.").foregroundStyle(.red)
            }
            Picker("Billable", selection: Binding(
                get: { settings.talixProjectBillable[coordinator.rateKey(project.id)].map { $0 ? 1 : 2 } ?? 0 },
                set: { settings.talixProjectBillable[coordinator.rateKey(project.id)] = $0 == 0 ? nil : $0 == 1 }
            )) {
                Text("Use default").tag(0)
                Text("Billable").tag(1)
                Text("Non-billable").tag(2)
            }
        }
        .onAppear { rate = (try? coordinator.rate(for: project)).map { String($0) } ?? "" }
    }
}
