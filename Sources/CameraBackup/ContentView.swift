import SwiftUI

enum SidebarSelection: Hashable {
    case dashboard, device(UUID), history, activity, help, settings
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: SidebarSelection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: SidebarSelection.dashboard) { Label("Dashboard", systemImage: "square.grid.2x2") }
                Section("Devices") {
                    ForEach(store.devices) { device in
                        NavigationLink(value: SidebarSelection.device(device.id)) {
                            DeviceSidebarRow(device: device)
                        }
                    }
                }
                Section("Library") {
                    NavigationLink(value: SidebarSelection.history) { Label("Backup History", systemImage: "clock.arrow.circlepath") }
                    NavigationLink(value: SidebarSelection.activity) { Label("Activity", systemImage: "text.alignleft") }
                    NavigationLink(value: SidebarSelection.help) { Label("Help & User Guide", systemImage: "questionmark.circle") }
                }
                Section("Configuration") {
                    NavigationLink(value: SidebarSelection.settings) { Label("Settings", systemImage: "gearshape") }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            switch selection {
            case .dashboard, .none: DashboardView(onSetUpDestinations: { selection = .settings })
            case .device(let id): DeviceDetailView(deviceID: id)
            case .history: HistoryView()
            case .activity: ActivityView()
            case .help: HelpUserGuideView()
            case .settings: SettingsView()
            }
        }
    }
}

struct DeviceSidebarRow: View {
    let device: CameraDevice
    var body: some View {
        HStack {
            Circle().fill(device.isConnected ? .green : .secondary.opacity(0.45)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                Text(device.isConnected ? "Connected" : "Offline").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.displayName), \(device.isConnected ? "connected" : "offline")")
        .accessibilityHint(device.isConnected ? "Open device details and backup controls" : "Open saved device history and details")
        .accessibilityAddTraits(.isButton)
    }
}
