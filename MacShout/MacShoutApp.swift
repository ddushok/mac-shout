import SwiftUI

@main
struct MacShoutApp: App {
    @StateObject private var appState = AppStateManager()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.state == .recording ? "mic.fill" : "waveform")
                .foregroundColor(appState.state == .recording ? .red : .primary)
        }
        .menuBarExtraStyle(.window)
    }
}
