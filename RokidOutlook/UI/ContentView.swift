import SwiftUI

struct ContentView: View {
    @StateObject private var settings:    SettingsStore
    @StateObject private var authManager: OutlookAuthManager
    @StateObject private var vm:          OutlookViewModel

    init() {
        let s    = SettingsStore()
        let auth = OutlookAuthManager(settings: s)
        _settings    = StateObject(wrappedValue: s)
        _authManager = StateObject(wrappedValue: auth)
        _vm          = StateObject(wrappedValue: OutlookViewModel(settings: s, authManager: auth))
    }

    var body: some View {
        TabView {
            InboxView()
                .tabItem { Label("Inbox", systemImage: "envelope") }

            GlassesPreviewView()
                .tabItem { Label("Glasses", systemImage: "eyeglasses") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .environmentObject(vm)
        .environmentObject(authManager)
        .environmentObject(settings)
        .tint(Color(red: 0.0, green: 0.47, blue: 0.83))
        .task {
            if vm.authManager.isSignedIn { vm.startPolling() }
        }
        .onChange(of: vm.authManager.isSignedIn) { _, signedIn in
            if signedIn { vm.startPolling() } else { vm.stopPolling() }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil || authManager.error != nil },
            set: { if !$0 { vm.errorMessage = nil; authManager.error = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil; authManager.error = nil }
        } message: {
            Text(vm.errorMessage ?? authManager.error ?? "")
        }
    }
}
