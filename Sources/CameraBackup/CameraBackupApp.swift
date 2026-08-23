import SwiftUI

@main
struct CameraBackupApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("Zebtron Camera zapper - automated backup", id: "dashboard") {
            ContentView().environmentObject(store)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1120, height: 720)

        MenuBarExtra("Zebtron Camera zapper", systemImage: menuIcon) {
            MenuBarView().environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(store)
                .frame(width: 760, height: 600)
        }
    }

    private var menuIcon: String {
        switch store.status {
        case .idle: "camera"
        case .failed: "exclamationmark.triangle"
        case .review: "checkmark.circle"
        default: "arrow.triangle.2.circlepath"
        }
    }
}
