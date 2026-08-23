import SwiftUI

struct DeviceDetailView: View {
    @EnvironmentObject private var store: AppStore
    let deviceID: UUID
    var device: CameraDevice? { store.devices.first { $0.id == deviceID } }
    var body: some View {
        ScrollView {
            if let device {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 20) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16).fill(.quaternary.opacity(0.5))
                            DeviceImageView(device: device).padding(10)
                        }.frame(width: 180, height: 135)
                        VStack(alignment: .leading, spacing: 9) {
                            TextField("Device nickname", text: nicknameBinding).font(.largeTitle.bold()).textFieldStyle(.plain)
                            Text("\(device.manufacturer) · \(device.model)").foregroundStyle(.secondary)
                            Label("Facts detected automatically", systemImage: "sparkles").font(.caption).foregroundStyle(.blue)
                            HStack {
                                Button("Choose Custom Image…") { chooseImage() }
                                if device.customImagePath != nil { Button("Use Model Image") { store.setDeviceImage(deviceID, path: nil) } }
                            }.controlSize(.small)
                        }
                        Spacer()
                        Text(device.isConnected ? "Connected" : "Offline").foregroundStyle(device.isConnected ? .green : .secondary)
                    }
                    GroupBox(device.category == .androidPhone ? "Device & Camera Facts" : "Camera Facts") {
                        Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 12) {
                            GridRow { fact("Introduced", icon: "calendar"); Text(device.releaseYear.map(String.init) ?? "Unknown") }
                            GridRow { fact("Sensor", icon: "camera.aperture"); Text(device.sensorDescription) }
                            GridRow { fact("RAW photos", icon: "photo.badge.checkmark"); Text(device.shootsRAW ? "Yes · \(device.rawFormats.joined(separator: ", "))" : "No RAW files detected") }
                            GridRow { fact("Video", icon: "video"); Text(device.videoCapability) }
                            GridRow { fact("Video formats", icon: "film"); Text(device.videoFormats.joined(separator: ", ")) }
                            GridRow { fact(device.category == .androidPhone ? "Storage seen" : "Card sizes seen", icon: device.category == .androidPhone ? "internaldrive" : "sdcard"); Text(device.observedCardCapacitiesGB.map { "\($0) GB" }.joined(separator: ", ")) }
                            GridRow { fact("Card type", icon: "sdcard"); Text(device.supportedCardTypes.joined(separator: " · ")) }
                            GridRow { fact("Card speed", icon: "gauge.with.dots.needle.67percent"); Text(device.recommendedCardSpeed) }
                            if !device.recommendedCardMakers.isEmpty {
                                GridRow { fact("Recommended", icon: "checkmark.seal"); Text(device.recommendedCardMakers.joined(separator: ", ")) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    if device.category == .androidPhone { AndroidConnectionView(deviceID: deviceID) }
                    GroupBox("Device Identity") {
                        Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 10) {
                            GridRow { Text("Volume").foregroundStyle(.secondary); Text(device.volumeName) }
                            GridRow { Text("Volume UUID").foregroundStyle(.secondary); Text(device.volumeUUID).monospaced() }
                            GridRow { Text("Last seen").foregroundStyle(.secondary); Text(device.lastSeen.formatted(date: .long, time: .shortened)) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    Text("Backup History").font(.title2.bold())
                    if let latest = store.sessions.filter({ $0.deviceID == deviceID }).sorted(by: { $0.startedAt > $1.startedAt }).first {
                        GroupBox("Last Backup Contents") {
                            VStack(alignment: .leading, spacing: 10) {
                                MediaOutcomeBadges(session: latest)
                                HStack(spacing: 22) {
                                    Label("\(latest.imageCount) images", systemImage: "photo")
                                    Label("\(latest.videoCount) videos", systemImage: "film")
                                    if latest.audioCount > 0 { Label("\(latest.audioCount) audio", systemImage: "waveform") }
                                    if latest.transcodedCount > 0 { Label("\(latest.transcodedCount) transcoded", systemImage: "arrow.triangle.2.circlepath") }
                                }
                                Text("Formats: \(latest.outputFormats.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }
                    }
                    ForEach(store.sessions.filter { $0.deviceID == deviceID }) { SessionRow(session: $0) }
                }.padding(28)
            } else { ContentUnavailableView("Device not found", systemImage: "questionmark") }
        }
    }
    private var nicknameBinding: Binding<String> {
        Binding(get: { device?.displayName ?? "" }, set: { value in
            guard let index = store.devices.firstIndex(where: { $0.id == deviceID }) else { return }
            store.devices[index].displayName = value
        })
    }
    private func fact(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
    }
    private func chooseImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.prompt = "Use Device Image"
        if panel.runModal() == .OK, let url = panel.url { store.setDeviceImage(deviceID, path: url.path) }
    }
}

struct AndroidConnectionView: View {
    @EnvironmentObject private var store: AppStore
    let deviceID: UUID
    @State private var confirmBackup = false
    @State private var confirmFullWorkflow = false
    @State private var confirmDeletion = false
    @State private var confirmFullWorkflowDeletion = false
    private var device: CameraDevice? { store.devices.first { $0.id == deviceID } }
    private var method: Binding<AndroidConnectionMethod> {
        Binding(get: { device?.androidConnectionMethod ?? .mtp }, set: { store.setAndroidConnectionMethod(deviceID, method: $0) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Live Phone Details") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(device?.connectionProvider ?? "Not connected", systemImage: "cable.connector.horizontal")
                                .font(.headline).foregroundStyle(device?.isConnected == true ? .green : .secondary)
                            Text(device?.connectionDetail ?? "Connect the phone to inspect it").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label(device?.isConnected == true ? "Connected" : "Offline", systemImage: device?.isConnected == true ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(device?.isConnected == true ? .green : .secondary)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                        GridRow { detailLabel("Model", icon: "smartphone"); Text(device?.model ?? "Unknown") }
                        GridRow { detailLabel("Software", icon: "gearshape.2"); Text(device?.operatingSystem ?? "Unknown") }
                        GridRow { detailLabel("Device ID", icon: "number"); Text(device?.volumeUUID ?? "Unknown").monospaced() }
                    }
                    if let usable = device?.usableStorageGiB, let used = device?.usedStorageGiB, let free = device?.freeStorageGiB {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text("Internal Storage").font(.headline); Spacer(); Text("\(used) GiB used · \(free) GiB free").font(.caption).foregroundStyle(.secondary) }
                            ProgressView(value: Double(used), total: Double(usable))
                            Text("512 GB model · approximately \(usable) GiB usable").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 12) {
                        MediaCountTile(count: device?.detectedImageCount ?? 0, title: "Images in DCIM", icon: "photo.fill", color: .blue)
                        MediaCountTile(count: device?.detectedVideoCount ?? 0, title: "Videos in DCIM", icon: "video.fill", color: .purple)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("Connection & Media Folders") {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Picker("Preferred connection", selection: method) { ForEach(AndroidConnectionMethod.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 380)
                        Spacer()
                        Button("Probe Again", systemImage: "arrow.clockwise") { Task { await store.refreshSources() } }
                    }
                    Text(connectionExplanation).font(.caption).foregroundStyle(.secondary)
                    if method.wrappedValue == .automatic { AndroidConnectionAssistant() }
                    Divider()
                    Text("Available on this Mac").font(.headline)
                    FlowTagView(values: device?.availableConnectionMethods ?? [])
                    Text("Folders to ingest").font(.headline).padding(.top, 3)
                    ForEach(device?.sourceFolders ?? [], id: \.self) { folder in
                        Label(folder.replacingOccurrences(of: "/sdcard/DCIM/", with: ""), systemImage: "folder.fill")
                            .help(folder)
                    }
                    Button("Add Folder…", systemImage: "plus") { }
                    Divider()
                    if let transfer = store.transferProgress {
                        AndroidTransferStatus(progress: transfer, log: store.transferLog, destination: localDestination, isRunning: store.status == .scanning || store.status == .backingUp) {
                            store.cancelBackup()
                        }
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Button("RUN COMPLETE BACKUP, VERIFY & DELETE…", systemImage: "checkmark.shield.fill", role: .destructive) { confirmFullWorkflowDeletion = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.large)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .disabled(device?.isConnected != true || store.status == .scanning || store.status == .backingUp || store.status == .verifying)

                        HStack {
                            Text("Advanced actions").font(.caption).foregroundStyle(.secondary)
                            Button(store.status == .scanning ? "Scanning…" : "Scan & Preview", systemImage: store.status == .scanning ? "hourglass" : "magnifyingglass") { store.previewAndroid(deviceID: deviceID) }
                                .controlSize(.small)
                                .disabled(device?.isConnected != true || store.status == .scanning || store.status == .backingUp)
                            Button(store.status == .backingUp ? "Backup Running…" : "Local Verified Backup", systemImage: "externaldrive.badge.checkmark") { confirmBackup = true }
                                .controlSize(.small)
                                .disabled(!store.previewedDeviceIDs.contains(deviceID) || store.status == .scanning || store.status == .backingUp)
                            Button("Sync All Services", systemImage: "play.circle.fill") { confirmFullWorkflow = true }
                                .controlSize(.small)
                                .disabled(device?.isConnected != true || store.status == .scanning || store.status == .backingUp)
                            Button("Verify & Delete Only…", systemImage: "checkmark.shield", role: .destructive) { confirmDeletion = true }
                                .controlSize(.small)
                                .disabled(device?.isConnected != true || store.status == .scanning || store.status == .backingUp || store.status == .verifying)
                            Spacer()
                            if let count = device?.filesWaiting, store.previewedDeviceIDs.contains(deviceID) { Text("\(count) files ready").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if method.wrappedValue == .mtp {
                        Label("Quit OpenMTP, Commander One, and MacDroid before direct MTP connects; only one app can control that interface.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    .confirmationDialog("Start verified backup?", isPresented: $confirmBackup, titleVisibility: .visible) {
                        Button("Start Backup") { store.startAndroidBackup(deviceID: deviceID) }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Camera Zapper will copy the previewed files to Local Device Archive, compare SHA-256 hashes, and write receipts. Nothing will be deleted from the phone.")
                    }
                    .confirmationDialog(fullWorkflowTitle, isPresented: $confirmFullWorkflow, titleVisibility: .visible) {
                        Button(device.map(store.isDeviceApproved) == true ? "Run Enabled Services" : "Add Device and Run") { store.runFullWorkflow(deviceID: deviceID) }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Camera Zapper will scan and preview, create the verified local archive, then run every enabled operational service in priority order. This workflow never deletes source files; deletion is a separate confirmed action on this device page.")
                    }
                    .confirmationDialog("Run everything, verify every required destination, then delete originals from \(device?.displayName ?? "this device")?", isPresented: $confirmFullWorkflowDeletion, titleVisibility: .visible) {
                        Button(device.map(store.isDeviceApproved) == true ? "Run Everything & Delete Verified Originals" : "Add Device, Run Everything & Delete Verified Originals", role: .destructive) { store.runFullWorkflowAndDelete(deviceID: deviceID) }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Camera Zapper will scan, create and verify the local staging copy, run every enabled service in priority order, and perform a complete deletion preflight. All cloud uploads are PRIVATE ONLY by design. Source files are deleted only if every applicable service marked ‘Must succeed before deleting source’ has a verified receipt. Optional failures are logged and later services continue. Deletion from this connected device cannot be undone.")
                    }
                    .confirmationDialog("Verify required copies, then delete originals from \(device?.displayName ?? "this device")?", isPresented: $confirmDeletion, titleVisibility: .visible) {
                        Button("Verify All Required Copies & Delete Originals", role: .destructive) { store.verifyAndDelete(deviceID: deviceID) }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("All candidate files and every enabled service marked ‘Must succeed before deleting source’ are checked before deletion begins. If any preflight check fails, nothing is deleted. Once checks pass, deletion from this specific connected device cannot be undone.")
                    }
            }
        }
    }
    private func detailLabel(_ title: String, icon: String) -> some View { Label(title, systemImage: icon).foregroundStyle(.secondary).frame(width: 105, alignment: .leading) }
    private var fullWorkflowTitle: String {
        guard let device else { return "Run full workflow?" }
        return store.isDeviceApproved(device) ? "Run full workflow?" : "Add this new device and run its first workflow?"
    }
    private var localDestination: String {
        store.configuration.services.first(where: { $0.kind == .localStorage })?.destination ?? "Local Device Archive"
    }
    private var connectionExplanation: String {
        switch method.wrappedValue {
        case .automatic: "Camera Zapper detects installed adapters, tests them without changing files, and chooses the best working connection. It automatically falls back if that method becomes unavailable."
        case .mtp: "Uses direct open-source MTP access. Unlock the phone and choose File Transfer when connected by USB. Developer Mode is not required."
        case .adbUSB: "Uses Android Debug Bridge over USB. Requires Developer Options, USB debugging, and one-time authorization of this Mac."
        case .adbWiFi: "Uses Android 11+ wireless debugging. The phone and Mac must be reachable on the same network or VPN."
        }
    }
}

private struct AndroidTransferStatus: View {
    let progress: EngineProgress
    let log: [AppStore.TransferLogEntry]
    let destination: String
    let isRunning: Bool
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(progress.phase, systemImage: phaseIcon).font(.headline)
                    .foregroundStyle(progress.failedFiles > 0 ? .orange : (["Complete", "Preview complete"].contains(progress.phase) ? .green : .primary))
                Spacer()
                Text(progress.totalFiles == 0 && isRunning ? "Discovering files…" : "\(progress.completedFiles) of \(progress.totalFiles) files")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            if progress.totalFiles == 0 && isRunning {
                ProgressView().progressViewStyle(.linear).tint(.blue)
            } else {
                ProgressView(value: progress.fraction).tint(progress.failedFiles > 0 ? .orange : .blue)
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.currentFile ?? progress.message).font(.subheadline).lineLimit(1).truncationMode(.middle)
                    Text(progress.message).font(.caption).foregroundStyle(.secondary)
                    Label((destination as NSString).expandingTildeInPath, systemImage: "externaldrive")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(progress.totalBytes == 0 && isRunning ? "Calculating media total…" : byteSummary).monospacedDigit()
                        Text(speed(at: context.date)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if isRunning { Button("Cancel", role: .cancel, action: cancel) }
            }
            HStack(spacing: 16) {
                if progress.phase.contains("Deletion") {
                    Label("\(progress.completedFiles) preflight checks passed", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                    Label("0 deleted until all checks pass", systemImage: "lock.fill").foregroundStyle(.blue)
                } else {
                    Label("\(progress.completedFiles) processed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Label("\(max(0, progress.completedFiles - progress.skippedFiles)) copied this run", systemImage: "doc.on.doc.fill").foregroundStyle(.blue)
                    Label("\(progress.skippedFiles) previously verified", systemImage: "forward.fill").foregroundStyle(.secondary)
                }
                Label("\(progress.failedFiles) failed", systemImage: "exclamationmark.triangle.fill").foregroundStyle(progress.failedFiles == 0 ? Color.secondary : Color.orange)
                Spacer()
                Text("Deletion requires the separate Verify & Delete action").font(.caption).foregroundStyle(.secondary)
            }.font(.caption)
            Divider()
            HStack {
                Text("Operation log").font(.caption.weight(.semibold))
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(isRunning ? "Active · elapsed \(elapsed(at: context.date))" : "Last operation")
                        .font(.caption.monospacedDigit()).foregroundStyle(isRunning ? .green : .secondary)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(log.suffix(25)) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                    .foregroundStyle(.secondary).monospacedDigit().frame(width: 70, alignment: .leading)
                                Text(entry.message).textSelection(.enabled)
                            }.font(.caption).id(entry.id)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 72, maxHeight: 140)
                    .onChange(of: log.count) { _, _ in if let last = log.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }.padding(.vertical, 3)
    }

    private var byteSummary: String {
        "\(ByteCountFormatter.string(fromByteCount: progress.completedBytes, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file))"
    }
    private func speed(at date: Date) -> String {
        guard isRunning, progress.completedBytes > 0 else { return isRunning ? "Calculating speed…" : "Finished" }
        let elapsed = max(1, date.timeIntervalSince(progress.startedAt))
        return ByteCountFormatter.string(fromByteCount: Int64(Double(progress.completedBytes) / elapsed), countStyle: .file) + "/s average"
    }
    private func elapsed(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(progress.startedAt)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    private var phaseIcon: String {
        switch progress.phase {
        case "Scanning": "magnifyingglass"
        case "Scanning phone": "magnifyingglass"
        case "Hashing source", "Verifying SHA-256": "number.square"
        case "Copying": "arrow.right.doc.on.clipboard"
        case "Deduplicating": "forward.fill"
        case "Complete": "checkmark.seal.fill"
        case "Preview complete": "checkmark.circle.fill"
        case "Preview failed": "exclamationmark.triangle.fill"
        case "Needs attention": "exclamationmark.triangle.fill"
        case "Cancelled": "xmark.circle"
        default: "gearshape.2"
        }
    }
}

struct AndroidConnectionAssistant: View {
    @State private var expandedHelp: String?
    private let adapters: [(name: String, status: String, icon: String, color: Color, detail: String)] = [
        ("ADB over USB", "Selected", "checkmark.circle.fill", .green, "Authorized and responding. Best direct, scriptable connection for this phone."),
        ("MacDroid File Provider", "Ready fallback", "checkmark.circle", .green, "Mounted in macOS CloudStorage. Useful when direct ADB is unavailable."),
        ("OpenMTP / direct MTP", "Busy", "exclamationmark.triangle.fill", .orange, "Installed, but MacDroid currently owns the MTP USB interface."),
        ("ADB over Wi-Fi", "Not paired", "wifi.exclamationmark", .secondary, "Supported by Android 11+, but this Mac has not been paired for wireless debugging.")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Label("Automatic connection check", systemImage: "wand.and.stars").font(.headline); Spacer(); Text("4 methods detected").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(adapters.enumerated()), id: \.offset) { index, adapter in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: adapter.icon).foregroundStyle(adapter.color).frame(width: 20)
                        Text("\(index + 1). \(adapter.name)").fontWeight(index == 0 ? .semibold : .regular)
                        Spacer()
                        Text(adapter.status).font(.caption.bold()).foregroundStyle(adapter.color)
                        Button { expandedHelp = expandedHelp == adapter.name ? nil : adapter.name } label: { Image(systemName: "info.circle") }.buttonStyle(.borderless).help("Setup details")
                    }
                    if expandedHelp == adapter.name {
                        Text(adapter.detail).font(.caption).foregroundStyle(.secondary).padding(.leading, 28)
                        AdapterSetupHelp(adapterName: adapter.name).padding(.leading, 28)
                    }
                }
            }
        }.padding(12).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct AdapterSetupHelp: View {
    let adapterName: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What it is: \(purpose)").font(.caption)
            Text("Setup: \(steps)").font(.caption)
        }.textSelection(.enabled)
    }
    private var purpose: String {
        switch adapterName {
        case "ADB over USB": "Android’s authorized developer connection for reliable device discovery and file transfer."
        case "MacDroid File Provider": "A third-party bridge that exposes Android storage as a macOS filesystem location."
        case "OpenMTP / direct MTP": "The standard Android File Transfer protocol; direct MTP avoids Developer Mode."
        default: "ADB carried over the local network, allowing cable-free synchronization."
        }
    }
    private var steps: String {
        switch adapterName {
        case "ADB over USB": "Install Android Platform Tools if no adb executable is available. Enable Developer options → USB debugging, connect with a data cable, and approve this Mac."
        case "MacDroid File Provider": "Install and open MacDroid, connect the phone, then confirm its device folder appears under ~/Library/CloudStorage."
        case "OpenMTP / direct MTP": "Install OpenMTP or Camera Zapper’s libmtp component, unlock the phone, choose File Transfer, and quit other apps currently controlling MTP."
        default: "On Android 11+, enable Developer options → Wireless debugging → Pair device with pairing code. Keep the Mac and phone reachable on the same LAN or VPN."
        }
    }
}

struct MediaCountTile: View {
    let count: Int
    let title: String
    let icon: String
    let color: Color
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            VStack(alignment: .leading) { Text(count.formatted()).font(.title2.bold()).monospacedDigit(); Text(title).font(.caption).foregroundStyle(.secondary) }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct FlowTagView: View {
    let values: [String]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { tags }
            VStack(alignment: .leading) { tags }
        }
    }
    @ViewBuilder private var tags: some View {
        ForEach(values, id: \.self) { value in
            Label(value, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 5).background(.quaternary, in: Capsule())
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Backup History").font(.largeTitle.bold())
            List(store.sessions) { SessionRow(session: $0).listRowSeparator(.hidden) }.listStyle(.plain)
        }.padding(28)
    }
}

struct ActivityView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var severity: ActivityEvent.Severity?
    var filtered: [ActivityEvent] {
        store.events.filter { (severity == nil || $0.severity == severity) && (search.isEmpty || $0.message.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Live Activity").font(.largeTitle.bold())
            Picker("Filter", selection: $severity) {
                Text("All").tag(ActivityEvent.Severity?.none)
                ForEach(ActivityEvent.Severity.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }.pickerStyle(.segmented).frame(maxWidth: 460)
            List(filtered) { event in
                HStack(alignment: .firstTextBaseline) {
                    Text(event.timestamp.formatted(date: .omitted, time: .standard)).monospacedDigit().foregroundStyle(.secondary).frame(width: 85, alignment: .leading)
                    Text(event.severity.rawValue.uppercased()).font(.caption.bold()).foregroundStyle(color(for: event.severity)).frame(width: 70, alignment: .leading)
                    Text(event.message)
                }
            }.listStyle(.plain).searchable(text: $search, prompt: "Search logs")
        }.padding(28)
    }
    private func color(for value: ActivityEvent.Severity) -> Color { switch value { case .info: .secondary; case .success: .green; case .warning: .orange; case .error: .red } }
}
