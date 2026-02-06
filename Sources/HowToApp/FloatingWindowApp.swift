import SwiftUI

@main
struct FloatingWindowApp: App {
    @StateObject private var odysseyBridge = OdysseyBridge.shared
    @StateObject private var appState: AppState
    @StateObject private var logStore = LogStore.shared

    init() {
        let bridge = OdysseyBridge.shared
        _odysseyBridge = StateObject(wrappedValue: bridge)
        _appState = StateObject(wrappedValue: AppState(odysseyBridge: bridge))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(logStore)
                .frame(minWidth: 980, minHeight: 520)
        }
    }
}
