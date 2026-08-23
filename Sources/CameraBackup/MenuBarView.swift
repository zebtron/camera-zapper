import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: "camera.fill").font(.title2); VStack(alignment: .leading) { Text("Zebtron Camera zapper").font(.headline); Text(store.status == .idle ? "No active backups" : store.status.rawValue).font(.caption).foregroundStyle(.secondary) }; Spacer() }
            Divider()
            Text("Devices").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(store.devices) { device in
                HStack { Circle().fill(device.isConnected ? .green : .gray).frame(width: 7, height: 7); Text(device.displayName); Spacer(); Text(device.isConnected ? "Connected" : "Offline").foregroundStyle(.secondary) }
            }
            if store.configuration.offlineCacheEnabled && store.cachedFileCount > 0 {
                Divider()
                Label("\(store.cachedFileCount) cached files waiting for NAS", systemImage: "internaldrive.badge.clock")
                    .foregroundStyle(.orange)
            }
            if let last = store.sessions.first {
                Divider(); Text("Last backup").font(.caption.bold()).foregroundStyle(.secondary)
                HStack { Text(last.deviceName); Spacer(); Label("\(last.filesVerified) verified", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            Divider()
            Button("Open Camera Zapper") { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }.keyboardShortcut("o")
            SettingsLink { Text("Settings…") }
            Button("Quit Camera Zapper") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }.padding(14).frame(width: 330)
    }
}
