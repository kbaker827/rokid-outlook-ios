import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var vm: OutlookViewModel
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Account
                Section("Microsoft Account") {
                    if vm.authManager.isSignedIn {
                        if let user = vm.authManager.currentUser {
                            LabeledContent("Signed in as", value: user.name)
                            LabeledContent("Email",        value: user.email)
                        }
                        Button("Sign Out", role: .destructive) { vm.authManager.signOut() }
                    } else {
                        Button("Sign in with Microsoft") { Task { await vm.authManager.signIn() } }
                            .disabled(settings.clientId.isEmpty)
                    }
                }

                // MARK: Azure App Registration
                Section {
                    TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $settings.clientId)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.footnote, design: .monospaced))
                    TextField("common  (or your tenant ID)", text: $settings.tenantId)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.footnote, design: .monospaced))
                } header: {
                    Text("Azure App Registration")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Register a free app at portal.azure.com")
                        Text("2. Add redirect URI: \(SettingsStore.redirectURI)")
                        Text("3. Platform: Mobile and desktop applications")
                        Text("4. Permissions: Mail.Read, Calendars.Read, Contacts.Read, User.Read")
                        Link("Azure Portal →", destination: URL(string: "https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps")!)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }

                // MARK: Inbox
                Section("Inbox") {
                    HStack {
                        Text("Emails to fetch")
                        Spacer()
                        Text("\(settings.maxEmails)").foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(settings.maxEmails) },
                        set: { settings.maxEmails = Int($0) }
                    ), in: 10...100, step: 10)
                    Toggle("Show unread only", isOn: $settings.showUnreadOnly)
                }

                // MARK: Polling
                Section("Polling") {
                    HStack {
                        Text("Refresh every")
                        Spacer()
                        Text("\(settings.pollInterval)s").foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(settings.pollInterval) },
                        set: { settings.pollInterval = Int($0) }
                    ), in: 30...600, step: 30) {
                        Text("Interval")
                    } minimumValueLabel: { Text("30s").font(.caption) }
                      maximumValueLabel: { Text("10m").font(.caption) }
                }

                // MARK: Glasses Alerts
                Section("Glasses Alerts") {
                    Toggle("New email",            isOn: $settings.alertNewEmail)
                    Toggle("High-importance email", isOn: $settings.alertImportant)
                    Toggle("Flagged email",         isOn: $settings.alertFlagged)
                    Toggle("Event starting soon",   isOn: $settings.alertEventStart)
                    if settings.alertEventStart {
                        HStack {
                            Text("Alert before event")
                            Spacer()
                            Text("\(settings.eventAlertMinutes) min").foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(settings.eventAlertMinutes) },
                            set: { settings.eventAlertMinutes = Int($0) }
                        ), in: 1...30, step: 1)
                    }
                }

                // MARK: Glasses Integration
                Section("Glasses Integration") {
                    Toggle("Accept queries from glasses", isOn: $settings.glassesQueryEnabled)
                    Picker("Display format", selection: $settings.glassesFormat) {
                        ForEach(GlassesFormat.allCases) { fmt in
                            VStack(alignment: .leading) {
                                Text(fmt.displayName)
                                Text(fmt.description).font(.caption).foregroundStyle(.secondary)
                            }.tag(fmt)
                        }
                    }
                    LabeledContent("TCP port", value: "8099").foregroundStyle(.secondary)
                }

                // MARK: About
                Section("About") {
                    LabeledContent("App",     value: "Rokid Outlook HUD")
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("API",     value: "Microsoft Graph v1.0")
                    Link("Microsoft Graph docs",
                         destination: URL(string: "https://learn.microsoft.com/en-us/graph/overview")!)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
