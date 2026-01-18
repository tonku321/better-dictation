import SwiftUI

@main
struct BetterDictationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            Label {
                Text("BetterDictation")
            } icon: {
                Image(systemName: appState.isRecording ? "waveform.circle.fill" : "waveform.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(appState.isRecording ? .red : .primary)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
