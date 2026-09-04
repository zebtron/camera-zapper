import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General", services = "Services & Priority", videoProcessing = "Video Processing", destinations = "Destinations", networkStorage = "NAS Connections", offlineCache = "Offline Cache", coordination = "Coordination", safety = "Safety", about = "About"
    var id: String { rawValue }
    var icon: String { switch self { case .general: "gear"; case .services: "point.3.connected.trianglepath.dotted"; case .videoProcessing: "film.stack"; case .destinations: "externaldrive"; case .networkStorage: "network"; case .offlineCache: "internaldrive"; case .coordination: "point.3.filled.connected.trianglepath.dotted"; case .safety: "lock.shield"; case .about: "info.circle" } }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: SettingsSection? = .services
    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in Label(section.rawValue, systemImage: section.icon).tag(section) }
                .navigationTitle("Settings").navigationSplitViewColumnWidth(190)
        } detail: {
            switch selection ?? .services {
            case .general: GeneralSettingsView()
            case .services: ServicesSettingsView()
            case .videoProcessing: VideoProcessingSettingsView()
            case .destinations: DestinationsSettingsView()
            case .networkStorage: NASConnectionsSettingsView()
            case .offlineCache: OfflineCacheSettingsView()
            case .coordination: CoordinationSettingsView()
            case .safety: SafetySettingsView()
            case .about: AboutView()
            }
        }
        .toolbar {
            ToolbarItem { Button("Run Setup Again", systemImage: "wand.and.stars") { store.runSetupAgain() } }
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(.blue.gradient)
                Image(systemName: "camera.fill").font(.system(size: 60, weight: .medium)).foregroundStyle(.white)
                Image(systemName: "bolt.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(.yellow).offset(x: 43, y: -38)
            }.frame(width: 128, height: 128).shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            VStack(spacing: 7) {
                Text("Zebtron Camera zapper").font(.largeTitle.bold())
                Text("automated backup").font(.title3).foregroundStyle(.secondary)
                Text("move · sync · delete").font(.headline).foregroundStyle(.blue)
            }
            Text("Safely move media from cameras and phones, synchronize verified copies across prioritized destinations, and delete originals only when your required services have succeeded.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 500)
            Divider().frame(maxWidth: 420)
            VStack(spacing: 8) {
                Text("by Zebtron").font(.headline)
                Link("zebtron.com/zapper", destination: URL(string: "https://zebtron.com/zapper/")!).font(.title3)
                HStack(spacing: 16) {
                    Link("Privacy", destination: URL(string: "https://zebtron.com/zapper/#privacy")!)
                    Link("Report a Bug", destination: URL(string: "mailto:zapper@zebtron.com?subject=Camera%20Zapper%201.350%20bug%20report&body=Please%20describe%20what%20happened%3A%0A%0AWhat%20you%20expected%3A%0A%0ADevice%20model%20and%20connection%20method%3A%0A%0AmacOS%20version%3A%0A%0ALast%20visible%20error%3A%0A%0APlease%20remove%20passwords%2C%20API%20secrets%2C%20OAuth%20tokens%2C%20personal%20paths%2C%20and%20private%20filenames%20before%20sending.")!)
                    Link("Support on Ko-fi", destination: URL(string: "https://ko-fi.com/zebtron")!)
                }.font(.caption)
                Text("Bug reports are appreciated. Camera Zapper is independently maintained in limited spare time, so responses and fixes may take a while. Thank you for being patient.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                Text("Beta version 1.350").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity).navigationTitle("About")
    }
}

struct CoordinationSettingsView: View {
    @EnvironmentObject private var store: AppStore
    var onlineCount: Int { store.coordinationNodes.filter(\.isOnline).count }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) { Text("Multi-Device Coordination").font(.title.bold()); Text("Prevent duplicate work with local journals, a shared ledger, and immutable destination receipts.").foregroundStyle(.secondary) }
                    Spacer(); Label("\(onlineCount) online", systemImage: "network").foregroundStyle(.green)
                }
                Picker("Deployment", selection: $store.configuration.coordination.mode) {
                    ForEach(CoordinationMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 430)
                if store.configuration.coordination.mode == .standalone {
                    GroupBox("Standalone Mode") {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("No coordinator required", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
                            Text("This Mac keeps its authoritative ledger locally and can perform discovery, backup, verification, history, and safe deletion by itself. A coordinator can be added later without rebuilding its history.").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                } else {
                    GroupBox("Coordinator") {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack { NodePlatformIcon(platform: .macOS, online: true).frame(width: 44, height: 44); VStack(alignment: .leading) { TextField("Coordinator name", text: $store.configuration.coordination.coordinatorName).font(.headline).textFieldStyle(.plain); Text("This Mac · customize the coordinator name and address").font(.caption).foregroundStyle(.secondary) }; Spacer(); Label("Healthy", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                            LabeledContent("Address") { TextField("Address", text: $store.configuration.coordination.coordinatorAddress).textFieldStyle(.roundedBorder).frame(minWidth: 340) }
                            Button("Test Coordinator", systemImage: "bolt.horizontal.circle") { store.record("Coordinator connection test requested") }
                        }.padding(8)
                    }
                    HStack { Text("Paired Devices").font(.title2.bold()); Spacer(); Button("Pair Device…", systemImage: "plus") { } }
                    VStack(spacing: 10) { ForEach(store.coordinationNodes.filter { !$0.isPrimary }) { CoordinationNodeRow(node: $0) } }
                    HStack { Text("Connected Clients").font(.title2.bold()); Spacer(); Text("Connection audit").font(.caption).foregroundStyle(.secondary) }
                    GroupBox {
                        VStack(spacing: 0) {
                            ClientConnectionHeader()
                            Divider()
                            ForEach(store.clientConnections) { client in
                                ClientConnectionRow(client: client)
                                if client.id != store.clientConnections.last?.id { Divider().padding(.leading, 42) }
                            }
                        }.padding(4)
                    }
                    GroupBox("Coordination Safety") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Require coordinator confirmation before deleting source files", isOn: $store.configuration.coordination.requireCoordinatorForDeletion)
                            Toggle("Allow workers to cache and hash while coordinator is offline", isOn: $store.configuration.coordination.allowOfflineCaching)
                            Toggle("Write immutable recovery receipts to the NAS", isOn: $store.configuration.coordination.writeNASReceipts)
                        }.padding(8)
                    }
                }
                GroupBox("Platform Plan") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("Primary now").font(.headline); PlatformPill(name: "macOS", active: true); PlatformPill(name: "Android", active: true) }
                        HStack { Text("Protocol-ready later").font(.headline); PlatformPill(name: "Windows", active: false); PlatformPill(name: "Linux", active: false); PlatformPill(name: "iOS", active: false) }
                        Text("Future-compatible, but outside the initial build scope.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }.padding(24)
        }.navigationTitle("Coordination")
    }
}

struct ClientConnectionHeader: View {
    var body: some View {
        HStack {
            Text("Client").frame(maxWidth: .infinity, alignment: .leading)
            Text("Connection").frame(width: 150, alignment: .leading)
            Text("Last connected").frame(width: 130, alignment: .leading)
            Text("Synced sources").frame(width: 190, alignment: .leading)
        }.font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 7)
    }
}

struct ClientConnectionRow: View {
    let client: ClientConnectionRecord
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: client.platform == .android ? "smartphone" : "desktopcomputer").frame(width: 22)
                VStack(alignment: .leading, spacing: 3) { Text(client.clientName).font(.headline); Text(client.platform.rawValue).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Label(client.path.rawValue, systemImage: client.path == .lan ? "network" : client.path == .vpn ? "lock.shield" : "circle.slash").foregroundStyle(client.isOnline ? .green : .secondary)
                Text(client.address).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }.frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(client.isOnline ? "Online now" : client.lastConnected == .distantPast ? "Never" : client.lastConnected.formatted(.relative(presentation: .named))).foregroundStyle(client.isOnline ? .green : .secondary)
                if client.firstConnected != .distantPast { Text("First: \(client.firstConnected.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(.tertiary) }
            }.frame(width: 130, alignment: .leading)
            Text(client.syncedSources.isEmpty ? "None yet" : client.syncedSources.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).frame(width: 190, alignment: .leading).lineLimit(3)
        }.padding(.horizontal, 10).padding(.vertical, 11)
    }
}

struct CoordinationNodeRow: View {
    let node: CoordinationNode
    var body: some View {
        HStack(spacing: 14) {
            NodePlatformIcon(platform: node.platform, online: node.isOnline).frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) { HStack { Text(node.name).font(.headline); Text(node.role.rawValue).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule()) }; Text(node.detail).font(.caption).foregroundStyle(.secondary) }
            Spacer(); VStack(alignment: .trailing, spacing: 4) { Text(node.isOnline ? "Online" : node.lastSeen == .distantPast ? "Not paired" : "Last seen \(node.lastSeen.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(node.isOnline ? .green : .secondary); Text(node.capabilities.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }.padding(13).background(.background, in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(.separator.opacity(0.45)))
    }
}

struct NodePlatformIcon: View {
    let platform: NodePlatform; let online: Bool
    var body: some View { ZStack(alignment: .bottomTrailing) { RoundedRectangle(cornerRadius: 10).fill(.quaternary); Image(systemName: platform == .android ? "smartphone" : "desktopcomputer").font(.title2); Circle().fill(online ? .green : .gray).frame(width: 10, height: 10).overlay(Circle().stroke(.background, lineWidth: 2)) } }
}

struct PlatformPill: View {
    let name: String; let active: Bool
    var body: some View { Text(name).font(.caption.bold()).foregroundStyle(active ? .green : .secondary).padding(.horizontal, 8).padding(.vertical, 4).background((active ? Color.green : Color.secondary).opacity(0.1), in: Capsule()) }
}

struct NASConnectionsSettingsView: View {
    @EnvironmentObject private var store: AppStore
    var smbURL: String { "smb://\(store.configuration.nasHost)/\(store.configuration.nasShare)" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NAS Connections").font(.title.bold())
                        Text("macOS owns the SMB session and credentials; Camera Zapper mounts, verifies, and monitors it.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(store.nasConnectionStatus, systemImage: store.nasIsConnected ? "checkmark.circle.fill" : "network.slash")
                        .foregroundStyle(store.nasIsConnected ? .green : .orange)
                }
                GroupBox("Primary NAS") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 13) {
                        GridRow { Text("Server").foregroundStyle(.secondary); TextField("nas.local", text: $store.configuration.nasHost).textFieldStyle(.roundedBorder) }
                        GridRow { Text("Share").foregroundStyle(.secondary); TextField("photo", text: $store.configuration.nasShare).textFieldStyle(.roundedBorder) }
                        GridRow { Text("SMB address").foregroundStyle(.secondary); Text(smbURL).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
                        GridRow { Text("Expected mount").foregroundStyle(.secondary); TextField("/Volumes/NAS", text: $store.configuration.nasMountPath).textFieldStyle(.roundedBorder) }
                        GridRow { Text("Authentication").foregroundStyle(.secondary); Label(store.configuration.nasUsesKeychain ? "macOS Keychain" : "Ask when connecting", systemImage: "key.fill") }
                        GridRow { Text("Fallback").foregroundStyle(.secondary); Label(store.configuration.offlineCacheEnabled ? "Verified local cache" : "Pause backup", systemImage: "internaldrive") }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox("Mounting & Credentials") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Ask macOS to mount this share automatically", isOn: $store.configuration.mountAutomatically)
                        Toggle("Use credentials saved in macOS Keychain", isOn: $store.configuration.nasUsesKeychain)
                        Text("Camera Zapper never stores the NAS password in its database or logs. If Keychain has no matching credential, macOS presents its standard authentication dialog.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                HStack {
                    Button("Test Connection", systemImage: "bolt.horizontal.circle") { store.mockTestNASConnection() }.buttonStyle(.borderedProminent)
                    Button("Open Mount in Finder", systemImage: "folder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: store.configuration.nasMountPath))
                    }
                    Button("Reconnect", systemImage: "arrow.clockwise") { store.mockTestNASConnection() }
                    Spacer()
                }
            }.padding(24)
        }.navigationTitle("NAS Connections")
    }
}

struct OfflineCacheSettingsView: View {
    @EnvironmentObject private var store: AppStore
    var expandedCachePath: String { NSString(string: store.configuration.offlineCacheDirectory).expandingTildeInPath }
    var body: some View {
        Form {
            Section("Travel Mode") {
                Toggle("Cache media on this Mac when required storage is unavailable", isOn: $store.configuration.offlineCacheEnabled)
                Text("Camera Zapper tests the required NAS destination for reachability and write access. This works on your LAN and through a VPN without relying on a Wi‑Fi network name.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Local Cache") {
                LabeledContent("Directory") {
                    HStack {
                        TextField("Cache directory", text: $store.configuration.offlineCacheDirectory).textFieldStyle(.roundedBorder).frame(minWidth: 340)
                        Button("Choose…") { chooseCacheDirectory() }
                    }
                }
                LabeledContent("Example") {
                    Text(URL(fileURLWithPath: expandedCachePath).appending(path: "Sony_A7_IV/2026/08/IMG_8432.ARW.partial").path)
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.blue).textSelection(.enabled)
                }
                HStack { Text("Maximum cache size"); Slider(value: $store.configuration.offlineCacheMaximumGB, in: 10...2000, step: 10); Text("\(Int(store.configuration.offlineCacheMaximumGB)) GB").monospacedDigit().frame(width: 72) }
                HStack { Text("Keep at least"); Slider(value: $store.configuration.offlineCacheMinimumFreeGB, in: 5...250, step: 5); Text("\(Int(store.configuration.offlineCacheMinimumFreeGB)) GB free").monospacedDigit().frame(width: 92) }
            }
            Section("Deferred NAS Sync") {
                Toggle("Automatically retry when network paths change", isOn: $store.configuration.retrySyncAutomatically)
                Toggle("Remove cached copy after the NAS copy is SHA-256 verified", isOn: $store.configuration.releaseCacheAfterVerification)
                Text("Queued files remain in the cache until every required destination has succeeded. Network interruption resumes from a new partial transfer and never marks the NAS copy verified early.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Source Deletion") {
                Toggle("Allow deletion from camera media after local-cache verification", isOn: $store.configuration.cacheAllowsSourceDeletion)
                Text(store.configuration.cacheAllowsSourceDeletion
                     ? "Warning: this permits removal from the card before the NAS has a verified copy. The Mac cache is temporarily the only managed copy."
                     : "Recommended: keep originals on the card until the NAS copy is verified.")
                    .font(.caption).foregroundStyle(store.configuration.cacheAllowsSourceDeletion ? .orange : .secondary)
            }
        }.formStyle(.grouped).navigationTitle("Offline Cache")
            .safeAreaInset(edge: .top) {
                Toggle("Enable Offline Cache", isOn: $store.configuration.offlineCacheEnabled).font(.headline).padding(.horizontal, 20).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
            }
    }
    private func chooseCacheDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.prompt = "Use Cache Directory"
        if panel.runModal() == .OK, let url = panel.url { store.configuration.offlineCacheDirectory = url.path }
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var settingsTransferStatus: String?
    var body: some View {
        Form {
            Section("Automation") {
                Toggle("Launch at login", isOn: $store.configuration.launchAtLogin)
                Toggle("Start backup automatically when camera media is detected", isOn: $store.configuration.startAutomatically)
                Toggle("Show macOS notifications", isOn: $store.configuration.notifications)
            }
            Section("Unknown files") { Toggle("Preserve unrecognized files alongside the archive", isOn: $store.configuration.preserveUnknownFiles) }
            Section("Settings portability") {
                Text("Camera Zapper automatically keeps version-independent settings backups in Application Support. Export a copy for another Mac or before an upgrade. Passwords, API secrets, OAuth tokens, and Keychain items are never included.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Export Settings…", systemImage: "square.and.arrow.up") { exportSettings() }
                    Button("Import Settings…", systemImage: "square.and.arrow.down") { importSettings() }
                    Button("Show Automatic Backups", systemImage: "folder") {
                        try? FileManager.default.createDirectory(at: store.settingsBackupFolder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(store.settingsBackupFolder)
                    }
                }
                if let settingsTransferStatus { Text(settingsTransferStatus).font(.caption).foregroundStyle(settingsTransferStatus.hasPrefix("Failed") ? .orange : .green) }
                Text("After import, authorize Google Photos, private YouTube, and Flickr on the destination Mac. Their credentials remain in each Mac's Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).navigationTitle("General")
    }
    private func exportSettings() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Camera-Zapper-Settings-1.350.json"; panel.prompt = "Export Settings"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.exportSettings(to: url); settingsTransferStatus = "Settings exported successfully." }
        catch { settingsTransferStatus = "Failed to export settings: \(error.localizedDescription)" }
    }
    private func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.prompt = "Choose Settings"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let confirmation = NSAlert(); confirmation.messageText = "Replace current Camera Zapper settings?"; confirmation.informativeText = "The current configuration is already preserved in Settings Backups. Imported cloud services will need authorization on this Mac."; confirmation.addButton(withTitle: "Import Settings"); confirmation.addButton(withTitle: "Cancel")
        guard confirmation.runModal() == .alertFirstButtonReturn else { return }
        do { try store.importSettings(from: url); settingsTransferStatus = "Settings imported. Finish setup and reauthorize cloud accounts." }
        catch { settingsTransferStatus = "Failed to import settings: \(error.localizedDescription)" }
    }
}

struct ServicesSettingsView: View {
    @EnvironmentObject private var store: AppStore
    var ordered: [ServiceConfiguration] { store.configuration.services.filter { $0.kind != .derivative }.sorted { $0.priority < $1.priority } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Services & Priority").font(.title.bold())
            Text("Enabled services execute from top to bottom. Drag to change priority. Required services must verify successfully before originals can be deleted.").foregroundStyle(.secondary)
            if store.needsInitialSetup || !store.configurationWarnings.isEmpty {
                GroupBox("First-run destination check") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Open each enabled file-storage service with the slider button, choose its real folder, and test mounted NAS volumes before allowing source deletion.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(store.configurationWarnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
                        HStack {
                            Button("Recheck Destinations") { store.validateConfiguration() }
                            Button("I’ve Reviewed My Destinations") { store.completeInitialSetup() }
                                .buttonStyle(.borderedProminent)
                                .disabled(!store.configurationWarnings.isEmpty)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All cloud uploads are PRIVATE ONLY by design").font(.headline)
                    Text("Google Photos albums are never shared, Flickr uploads are private and hidden, and YouTube videos are always private. Camera Zapper provides no public or unlisted upload setting.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            ScrollViewReader { proxy in
                List {
                    ForEach(ordered) { service in
                        ServiceEditorRow(serviceID: service.id)
                            .id(service.id)
                            .onDrag {
                                guard service.kind != .localStorage else { return NSItemProvider() }
                                store.draggedServiceID = service.id
                                return NSItemProvider(object: service.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: ServicePriorityDropDelegate(targetID: service.id, store: store))
                    }.onMove(perform: store.moveServices)
                }.listStyle(.inset)
                    .onAppear {
                        if let serviceID = store.requestedSettingsServiceID { proxy.scrollTo(serviceID, anchor: .center) }
                    }
                    .onChange(of: store.requestedSettingsServiceID) { _, serviceID in
                        if let serviceID { withAnimation { proxy.scrollTo(serviceID, anchor: .center) } }
                    }
            }
            HStack {
                Menu("Add Service", systemImage: "plus") {
                    Section("Destinations") {
                        Button("Storage / NAS", systemImage: "externaldrive") { store.addService(.storage) }
                        Button("YouTube", systemImage: "play.rectangle.fill") { store.addService(.youtube) }
                        Button("Google Photos", systemImage: "photo.badge.arrow.down") { store.addService(.googlePhotos) }
                        Button("Flickr", systemImage: "circle.grid.2x1.fill") { store.addService(.flickr) }
                        Button("Amazon S3", systemImage: "shippingbox.fill") { store.addService(.s3) }
                        Button("Amazon Photos", systemImage: "photo.stack") { store.addService(.amazonPhotos) }
                        Button("iCloud Drive", systemImage: "icloud.fill") { store.addService(.iCloud) }
                    }
                    Section("Integrations") {
                        Button("Apple Photos", systemImage: "photo.on.rectangle.angled") { store.addService(.photos) }
                        Button("NeoFinder", systemImage: "books.vertical.fill") { store.addService(.neofinder) }
                    }
                }
                Spacer()
                Label("Configuration saves automatically", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
        }.padding(24).navigationTitle("Services")
    }
}

struct VideoProcessingSettingsView: View {
    @EnvironmentObject private var store: AppStore
    private var enabled: Binding<Bool> { .init(get: { store.configuration.transcodeIncompatibleVideos ?? false }, set: { store.configuration.transcodeIncompatibleVideos = $0 }) }
    private var destination: Binding<String> { .init(get: { store.configuration.transcodeDestination ?? "~/Movies/Camera Zapper/Compatibility Videos" }, set: { store.configuration.transcodeDestination = $0 }) }
    var body: some View {
        Form {
            Section {
                Toggle("Create MP4 compatibility copies", isOn: enabled)
                Text("Optional processing after the original has been copied and SHA-256 verified. MP4 and MKV sources are left unchanged; every other supported video format gets an additional MP4 copy. The original is always preserved.")
                    .foregroundStyle(.secondary)
            } header: { Text("Automatic Video Transcoding") }
            Section("Rules") {
                LabeledContent("Input") { Text("Videos except .mp4 and .mkv") }
                LabeledContent("Output") { Text("MP4 · hardware-accelerated HEVC when available") }
                LabeledContent("Original") { Label("Always retained", systemImage: "checkmark.shield.fill").foregroundStyle(.green) }
            }
            Section("Compatibility-copy destination") {
                HStack {
                    TextField("Destination", text: destination).textFieldStyle(.roundedBorder)
                    Button("Choose…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let url = panel.url { destination.wrappedValue = url.path }
                    }
                }
                Text("Example: \((destination.wrappedValue as NSString).expandingTildeInPath)/My Device/2026/08/VID_0001.mp4")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Button("Catch Up Existing Verified Videos…", systemImage: "arrow.triangle.2.circlepath") { store.catchUpVideoProcessing() }
                        .disabled(!enabled.wrappedValue)
                    if let status = store.videoProcessingStatus { Text(status).font(.caption).foregroundStyle(status.hasPrefix("Failed") ? .orange : .secondary) }
                }
            }
        }.formStyle(.grouped).navigationTitle("Video Processing")
    }
}

struct ServiceEditorRow: View {
    @EnvironmentObject private var store: AppStore
    let serviceID: UUID
    @State private var expanded = false
    @State private var confirmDeletion = false
    @State private var confirmReprocess = false
    @State private var chooseGoogleCredentials = false
    @State private var showFlickrSetup = false
    private var index: Int? { store.configuration.services.firstIndex { $0.id == serviceID } }
    var body: some View {
        if let index {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: store.configuration.services[index].kind == .localStorage ? "lock.fill" : "line.3.horizontal")
                        .foregroundStyle(.tertiary).frame(width: 18)
                        .help(store.configuration.services[index].kind == .localStorage ? "Local archive is always first" : "Drag to change execution priority")
                    Toggle("", isOn: Binding(get: { store.configuration.services[index].isEnabled }, set: { store.setServiceEnabled(serviceID, $0) })).labelsHidden()
                        .disabled(store.configuration.services[index].kind == .localStorage)
                    Image(systemName: icon(store.configuration.services[index].kind)).frame(width: 24).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("Service name", text: $store.configuration.services[index].name).font(.headline).textFieldStyle(.plain)
                        Text(store.configuration.services[index].detail).font(.caption).foregroundStyle(.secondary)
                        Label(store.serviceCapability(store.configuration.services[index]), systemImage: capabilityIcon(store.configuration.services[index]))
                            .font(.caption2).foregroundStyle(capabilityColor(store.configuration.services[index]))
                        if store.configuration.services[index].kind == .googlePhotos {
                            Label("Google limits uploads to about 30 write requests per minute per user. Camera Zapper deliberately uploads at a steady pace and retries temporary limits.", systemImage: "speedometer")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if store.configuration.services[index].kind == .youtube {
                            Label("YouTube currently allows 100 video uploads per project per day. Camera Zapper uploads privately and never notifies subscribers.", systemImage: "gauge.with.dots.needle.67percent")
                                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    if [.storage, .photos, .youtube, .googlePhotos, .flickr, .neofinder].contains(store.configuration.services[index].kind) {
                        if store.configuration.services[index].kind == .googlePhotos, let activationURL = store.googlePhotosAPIActivationURL {
                            Button("Enable API…", systemImage: "wrench.and.screwdriver") { NSWorkspace.shared.open(activationURL) }
                        }
                        Button(actionLabel(store.configuration.services[index]), systemImage: store.configuration.services[index].kind == .googlePhotos && !store.googlePhotosAuthorized ? "person.crop.circle.badge.plus" : "arrow.triangle.2.circlepath") {
                            if store.configuration.services[index].kind == .googlePhotos && !store.googlePhotosAuthorized { chooseGoogleCredentials = true }
                            else if store.configuration.services[index].kind == .youtube && !store.youtubeAuthorized { store.configureYouTube(serviceID: serviceID) }
                            else if store.configuration.services[index].kind == .flickr && !store.flickrAuthorized { showFlickrSetup = true }
                            else { confirmReprocess = true }
                        }
                            .disabled(store.serviceOperationIsRunning(serviceID) || (![.youtube, .googlePhotos, .flickr].contains(store.configuration.services[index].kind) && !store.canReprocess(store.configuration.services[index])))
                            .help(actionHelp(store.configuration.services[index]))
                    }
                    Toggle("Must succeed before deleting source", isOn: $store.configuration.services[index].isRequiredForDeletion)
                        .toggleStyle(.checkbox)
                        .disabled(store.configuration.services[index].kind == .localStorage || !store.configuration.services[index].isEnabled)
                        .help(store.configuration.services[index].kind == .localStorage ? "The verified local archive is always required" : "This service must succeed before originals are safe to delete")
                    Button(expanded ? "Close" : "Configure…", systemImage: expanded ? "chevron.up" : "slider.horizontal.3") { expanded.toggle() }
                        .buttonStyle(.bordered)
                        .help("Configure this service without rerunning the setup wizard")
                    if store.configuration.services[index].kind != .localStorage {
                        Button(role: .destructive) { confirmDeletion = true } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Remove service")
                    }
                }
                if store.configuration.services[index].isEnabled,
                   store.configuration.services[index].isRequiredForDeletion,
                   !store.serviceIsOperational(store.configuration.services[index]) {
                    Label("Deletion blocked — this required service is not operational", systemImage: "lock.trianglebadge.exclamationmark.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange).padding(.leading, 30)
                }
                if expanded {
                    Divider()
                    if store.configuration.services[index].kind == .googlePhotos {
                        HStack {
                            Label("OAuth setup", systemImage: "person.badge.key.fill").font(.headline)
                            Spacer()
                            Button("Choose OAuth JSON / Reauthorize…", systemImage: "doc.badge.gearshape") { chooseGoogleCredentials = true }
                            Button("Test Authorization", systemImage: "checkmark.circle") { store.testService(serviceID) }
                        }
                        Text("Choose the Desktop OAuth client JSON downloaded from Google Cloud. Camera Zapper stores the client configuration and account token securely; use this again whenever authorization expires or you change Google projects.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if store.configuration.services[index].kind == .flickr {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                            Label("Flickr authorization", systemImage: "person.badge.key.fill").font(.headline)
                            Spacer()
                            Button("Reconnect…", systemImage: "key") { showFlickrSetup = true }
                            Button("Test Live Login", systemImage: "checkmark.circle") { store.testFlickrAuthorization(serviceID: serviceID) }
                            Button("Disconnect", systemImage: "person.crop.circle.badge.minus", role: .destructive) { store.disconnectFlickr(serviceID: serviceID) }
                            }
                            Text(store.flickrAccountName.map { "Connected as \($0). The test calls Flickr directly; a saved local flag alone is not treated as proof." } ?? "Use Test Live Login to validate the saved Keychain credentials directly with Flickr.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if store.configuration.services[index].kind == .youtube {
                        HStack {
                            Label("YouTube authorization", systemImage: "person.badge.key.fill").font(.headline)
                            Spacer()
                            Button("Authorize / Reauthorize…", systemImage: "person.crop.circle.badge.checkmark") { store.configureYouTube(serviceID: serviceID) }
                            Button("Test Authorization", systemImage: "checkmark.circle") { store.testService(serviceID) }
                        }
                    }
                    ServiceConfigurationPanel(index: index)
                }
            }.padding(.vertical, 7).opacity(store.configuration.services[index].isEnabled ? 1 : 0.55)
                .onAppear { if store.requestedSettingsServiceID == serviceID { expanded = true } }
                .onChange(of: store.requestedSettingsServiceID) { _, requested in if requested == serviceID { expanded = true } }
                .confirmationDialog("Remove \(store.configuration.services[index].name)?", isPresented: $confirmDeletion, titleVisibility: .visible) {
                    Button("Remove Service", role: .destructive) { store.deleteService(serviceID) }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This removes the service configuration. Existing backup records and files will not be deleted.")
                }
                .confirmationDialog("\(store.serviceCanResume(serviceID) ? "Resume" : "Catch up") \(store.configuration.services[index].name)?", isPresented: $confirmReprocess, titleVisibility: .visible) {
                    Button(store.serviceCanResume(serviceID) ? "Resume Remaining Files" : "Process Verified Local Archive") { store.reprocessService(serviceID) }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Camera Zapper will process the 766 already-verified local files for this service and write separate receipts. It will not read or delete files on the phone.")
                }
                .fileImporter(isPresented: $chooseGoogleCredentials, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                    if case .success(let urls) = result, let url = urls.first { store.configureGooglePhotos(from: url, serviceID: serviceID) }
                }
                .sheet(isPresented: $showFlickrSetup) { FlickrSetupSheet(serviceID: serviceID).environmentObject(store) }
        }
    }
    private func icon(_ kind: ServiceKind) -> String { switch kind { case .localStorage: "internaldrive.fill"; case .storage: "externaldrive.fill"; case .s3: "shippingbox.fill"; case .youtube: "play.rectangle.fill"; case .googlePhotos: "photo.badge.arrow.down"; case .flickr: "circle.grid.2x1.fill"; case .amazonPhotos: "photo.stack"; case .iCloud: "icloud.fill"; case .photos: "photo.on.rectangle.angled"; case .neofinder: "books.vertical.fill"; case .derivative: "film.stack" } }
    private func capabilityIcon(_ service: ServiceConfiguration) -> String {
        let text = store.serviceCapability(service)
        return text.hasPrefix("Operational") ? "checkmark.circle.fill" : text.hasPrefix("Unavailable") || text.hasPrefix("Failed") || text.hasPrefix("Needs attention") ? "exclamationmark.triangle.fill" : text.hasPrefix("Not set up") ? "circle.dashed" : "gearshape.2.fill"
    }
    private func capabilityColor(_ service: ServiceConfiguration) -> Color {
        let text = store.serviceCapability(service)
        return text.hasPrefix("Operational") || text.hasPrefix("Catch-up complete") ? .green : text.hasPrefix("Unavailable") || text.hasPrefix("Failed") || text.hasPrefix("Needs attention") ? .orange : .secondary
    }
    private func actionLabel(_ service: ServiceConfiguration) -> String {
        if (service.kind == .googlePhotos && !store.googlePhotosAuthorized) || (service.kind == .youtube && !store.youtubeAuthorized) || (service.kind == .flickr && !store.flickrAuthorized) { return "Set Up & Catch Up…" }
        if store.serviceOperationIsRunning(service.id) { return service.kind == .googlePhotos ? "Uploading…" : "Working…" }
        if store.serviceCanResume(service.id) { return "Resume…" }
        return "Catch Up…"
    }
    private func actionHelp(_ service: ServiceConfiguration) -> String {
        service.kind == .googlePhotos ? "Add Google OAuth credentials and authorize an account before uploading the verified archive" : service.kind == .youtube ? "Authorize the existing Google OAuth client for private YouTube uploads" : service.kind == .flickr ? "Add a Flickr API key and authorize write access before uploading the verified archive" : "Process files already verified in Local Device Archive"
    }
}

private struct ServicePriorityDropDelegate: DropDelegate {
    let targetID: UUID
    let store: AppStore
    func dropEntered(info: DropInfo) {
        guard let draggedID = store.draggedServiceID, draggedID != targetID else { return }
        store.moveService(draggedID, before: targetID)
    }
    func performDrop(info: DropInfo) -> Bool { store.draggedServiceID = nil; return true }
    func dropExited(info: DropInfo) { }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}

private struct FlickrSetupSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let serviceID: UUID
    @State private var apiKey = ""
    @State private var apiSecret = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Connect Flickr").font(.title2.bold())
                Text("Enter the API key and secret from Flickr App Garden. They will be saved in macOS Keychain, not Camera Zapper's settings or logs.").foregroundStyle(.secondary)
            }
            Form {
                LabeledContent("API key") { TextField("Flickr API key", text: $apiKey).textFieldStyle(.roundedBorder).frame(width: 360) }
                LabeledContent("API secret") { SecureField("Flickr API secret", text: $apiSecret).textFieldStyle(.roundedBorder).frame(width: 360) }
            }.formStyle(.grouped)
            Label("Your browser will open so you can grant write access. Camera Zapper never receives your Flickr password.", systemImage: "lock.shield.fill").font(.caption).foregroundStyle(.secondary)
            HStack {
                Link("Flickr App Garden", destination: URL(string: "https://www.flickr.com/services/apps/create/")!)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Authorize Flickr") { store.configureFlickr(key: apiKey, secret: apiSecret, serviceID: serviceID) }
                    .buttonStyle(.borderedProminent).disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let operation = store.serviceOperations[serviceID] {
                Label(operation, systemImage: operation.hasPrefix("Operational") ? "checkmark.circle.fill" : operation.localizedCaseInsensitiveContains("failed") ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(operation.hasPrefix("Operational") ? .green : operation.localizedCaseInsensitiveContains("failed") ? .orange : .secondary)
                    .textSelection(.enabled)
            }
        }.padding(24).frame(width: 590)
    }
}

struct ServiceConfigurationPanel: View {
    @EnvironmentObject private var store: AppStore
    let index: Int
    private var service: ServiceConfiguration { store.configuration.services[index] }
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                Text("Description").foregroundStyle(.secondary)
                TextField("What this service does", text: $store.configuration.services[index].detail).textFieldStyle(.roundedBorder)
            }
            if service.kind == .localStorage || service.kind == .storage || service.kind == .derivative || service.kind == .iCloud {
                GridRow {
                    Text("Destination").foregroundStyle(.secondary)
                    HStack {
                        TextField("/Volumes/…", text: Binding(get: { store.configuration.services[index].destination ?? "" }, set: { store.configuration.services[index].destination = $0 })).textFieldStyle(.roundedBorder)
                        Button("Choose…") { chooseDestination() }
                    }
                }
            }
            if service.kind == .s3 || service.kind == .youtube || service.kind == .googlePhotos || service.kind == .flickr || service.kind == .amazonPhotos || service.kind == .iCloud {
                GridRow {
                    Text(remoteLabel).foregroundStyle(.secondary)
                    TextField(remotePlaceholder, text: Binding(get: { service.remoteLocation ?? "" }, set: { store.configuration.services[index].remoteLocation = $0 })).textFieldStyle(.roundedBorder)
                }
            }
            GridRow {
                Text("Media").foregroundStyle(.secondary)
                HStack {
                    ForEach(MediaKind.allCases) { kind in
                        Toggle(kind.rawValue, isOn: mediaBinding(kind)).toggleStyle(.checkbox)
                    }
                }
            }
            if service.kind == .localStorage || service.kind == .storage || service.kind == .derivative || service.kind == .youtube || service.kind == .iCloud {
                GridRow {
                    Text("Output").foregroundStyle(.secondary)
                    HStack {
                        Picker("Format", selection: Binding(get: { service.outputFormat ?? "Original" }, set: { store.configuration.services[index].outputFormat = $0 })) {
                            Text("Keep original").tag("Original")
                            Text("MP4").tag("MP4")
                            Text("FLAC").tag("FLAC")
                        }.labelsHidden().frame(width: 140)
                        Toggle("Transcode when needed", isOn: $store.configuration.services[index].transcodeEnabled).toggleStyle(.checkbox)
                    }
                }
            }
            if service.kind == .youtube || service.kind == .googlePhotos || service.kind == .flickr {
                GridRow {
                    Text("Upload visibility").foregroundStyle(.secondary)
                    Label("Private only · locked for safety", systemImage: "lock.fill")
                        .foregroundStyle(.green)
                }
            }
            if service.kind == .localStorage {
                GridRow {
                    Text("Why required?").foregroundStyle(.secondary)
                    Text("This permanent archive guarantees Camera Zapper always has one verified destination. It is separate from the temporary offline cache.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(.leading, 48).padding(.trailing, 8).padding(.bottom, 6)
    }
    private var remoteLabel: String { switch service.kind { case .s3: "Bucket / prefix"; case .youtube: "Playlist"; case .googlePhotos, .flickr, .amazonPhotos: "Album"; case .iCloud: "Cloud folder"; default: "Remote location" } }
    private var remotePlaceholder: String { switch service.kind { case .s3: "s3://bucket/prefix"; case .youtube, .googlePhotos, .flickr, .amazonPhotos: "Camera Zapper"; case .iCloud: "iCloud Drive/Camera Zapper"; default: "Location" } }
    private func mediaBinding(_ kind: MediaKind) -> Binding<Bool> {
        Binding(get: { service.acceptedMedia.contains(kind) }, set: { enabled in
            if enabled { store.configuration.services[index].acceptedMedia.insert(kind) }
            else { store.configuration.services[index].acceptedMedia.remove(kind) }
        })
    }
    private func chooseDestination() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.prompt = "Use Destination"
        if panel.runModal() == .OK, let url = panel.url { store.updateServiceDestination(service.id, path: url.path) }
    }
}

struct DestinationsSettingsView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("File Destinations").font(.title.bold())
                Text("Choose where each media type is archived. Templates support {year}, {month}, {day}, {device}, and {filename}.").foregroundStyle(.secondary)
                ForEach(store.configuration.destinations.indices, id: \.self) { index in DestinationRuleEditor(index: index) }
            }.padding(24)
        }.navigationTitle("Destinations")
    }
}

struct DestinationRuleEditor: View {
    @EnvironmentObject private var store: AppStore
    let index: Int
    var rule: DestinationRule { store.configuration.destinations[index] }
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Toggle(isOn: $store.configuration.destinations[index].enabled) { Label(rule.kind.rawValue, systemImage: rule.kind.icon).font(.headline) }; Spacer(); Button("Choose…") { chooseFolder() } }
                LabeledContent("Storage root") { TextField("/Volumes/…", text: $store.configuration.destinations[index].root).textFieldStyle(.roundedBorder).frame(minWidth: 380) }
                LabeledContent("Folder template") { TextField("{year}/{month}/{filename}", text: $store.configuration.destinations[index].pathTemplate).textFieldStyle(.roundedBorder).frame(minWidth: 380) }
                VStack(alignment: .leading, spacing: 4) { Text("Example output").font(.caption.bold()).foregroundStyle(.secondary); Text(rule.example()).font(.system(.caption, design: .monospaced)).textSelection(.enabled).foregroundStyle(.blue) }
            }.padding(6)
        }.opacity(rule.enabled ? 1 : 0.55)
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.prompt = "Use Destination"
        if panel.runModal() == .OK, let url = panel.url { store.configuration.destinations[index].root = url.path }
    }
}

struct SafetySettingsView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Form {
            Section("Originals") {
                Picker("After every required copy is SHA-256 verified", selection: $store.configuration.deletionPolicy) { ForEach(DeletionPolicy.allCases) { Text($0.rawValue).tag($0) } }
                Text("Camera Zapper never deletes a source file unless its destination exists, its size matches, and its SHA-256 hash equals the recorded source hash.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Storage") {
                HStack { Text("Free-space safety margin"); Slider(value: $store.configuration.safetyMarginPercent, in: 0...30, step: 1); Text("\(Int(store.configuration.safetyMarginPercent))%").monospacedDigit().frame(width: 36) }
            }
        }.formStyle(.grouped).navigationTitle("Safety")
    }
}
