import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    var onSetUpDestinations: () -> Void = {}
    private let columns = [GridItem(.adaptive(minimum: 285, maximum: 380), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing: 10) {
                            Text("Zebtron Camera zapper").font(.largeTitle.bold())
                            Text("BETA 1.350").font(.caption.bold()).foregroundStyle(.green).padding(.horizontal, 7).padding(.vertical, 4).background(.green.opacity(0.12), in: Capsule())
                        }
                        Text("move · sync · delete").font(.headline).foregroundStyle(.secondary)
                        Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(status: store.status, hasProblem: store.activeProblemSummary != nil)
                }

                if store.status != .idle { ProgressView(value: store.progress) }

                if let summary = store.activeProblemSummary {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Action needed", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline).foregroundStyle(.orange)
                        if store.activeServiceProblems.isEmpty {
                            Text(summary).textSelection(.enabled)
                        }
                        ForEach(store.activeServiceProblems) { problem in
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(problem.service.name): \(problem.detail)")
                                    .font(.callout).textSelection(.enabled)
                                Spacer()
                                Button("Open \(problem.service.name) Settings…", systemImage: "slider.horizontal.3") {
                                    store.openServiceSettings(problem.service.id)
                                }
                            }
                        }
                        Text("Completed receipts remain valid. Resume from the connected device to retry unfinished work, recheck every required location, and delete only after all required checks pass.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.35)))
                }

                if store.setupIncomplete {
                    InitialSetupCard(onSetUp: onSetUpDestinations)
                }

                if !store.adbAvailable {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "cable.connector.slash").font(.title2).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Android Platform Tools are required for Android devices").font(.headline)
                            Text("Install ADB with Homebrew (`brew install android-platform-tools`) or Android Studio, then relaunch Camera Zapper. ADB detects the device, scans media, verifies hashes on the device, copies files, and performs confirmed source deletion.")
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                CacheStatusCard()

                NASStatusCard()

                CoordinationStatusCard()

                Text("Devices").font(.title2.bold())
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.devices) { DeviceCard(device: $0) }
                }

                HStack {
                    Text("Recent Backups").font(.title2.bold())
                    Spacer()
                    Text("Required services run in priority order").font(.caption).foregroundStyle(.secondary)
                }
                if store.sessions.isEmpty {
                    ContentUnavailableView("No backups yet", systemImage: "externaldrive", description: Text("Insert a camera card containing a DCIM folder."))
                } else {
                    ForEach(store.sessions.prefix(5)) { session in SessionRow(session: session) }
                }
            }.padding(28)
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusMessage: String {
        switch store.status {
        case .idle: "Monitoring for camera media"
        case .review: "A verified backup is ready for review"
        default: store.currentFile ?? store.status.rawValue
        }
    }
}

struct InitialSetupCard: View {
    @EnvironmentObject private var store: AppStore
    let onSetUp: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "wand.and.stars").font(.title2).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 5) {
                Text("Finish setup").font(.headline)
                Text("Choose only the destinations you want. Services you have not set up stay quiet and never block deletion.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(store.configurationWarnings, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            Button("Run Setup", action: { store.runSetupAgain() }).buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.blue.opacity(0.35)))
        .accessibilityElement(children: .combine)
    }
}

struct CoordinationStatusCard: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: store.configuration.coordination.mode == .coordinated ? "point.3.filled.connected.trianglepath.dotted" : "desktopcomputer").font(.title2).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.configuration.coordination.mode == .coordinated ? "Coordinated by \(store.configuration.coordination.coordinatorName)" : "Standalone on This Mac").font(.headline)
                Text(store.configuration.coordination.mode == .coordinated ? "Shared deduplication ledger · \(store.coordinationNodes.filter(\.isOnline).count) devices online · NAS receipts enabled" : "Local authoritative ledger · all backup features available").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(); Label("Healthy", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.5)))
    }
}

struct NASStatusCard: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        let nas = store.configuration.services.first { $0.kind == .storage && $0.isEnabled }
        HStack(spacing: 14) {
            Image(systemName: nas == nil ? "externaldrive.badge.plus" : store.nasIsConnected ? "externaldrive.connected.to.line.below.fill" : "network.slash")
                .font(.title2).foregroundStyle(nas == nil ? Color.secondary : store.nasIsConnected ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(nas == nil ? "NAS not set up" : "Primary NAS Archive").font(.headline)
                Text(nas == nil ? "Optional · choose it in Setup when you want a mounted NAS destination" : store.nasConnectionStatus).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if nas != nil { Button("Test Connection") { store.mockTestNASConnection() } }
        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.5)))
    }
}

struct CacheStatusCard: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        if store.configuration.offlineCacheEnabled {
            HStack(spacing: 14) {
                Image(systemName: store.cachedFileCount > 0 ? "internaldrive.fill.badge.clock" : "internaldrive.fill")
                    .font(.title2).foregroundStyle(store.cachedFileCount > 0 ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Offline Cache").font(.headline)
                    Text(store.cachedFileCount > 0
                         ? "\(store.cachedFileCount) files (\(ByteCountFormatter.string(fromByteCount: store.cachedBytes, countStyle: .file))) queued · \(store.cacheSyncStatus.rawValue)"
                         : "Ready for travel · no files waiting for NAS sync")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.cachedFileCount > 0 { Button("Sync Now") { store.record("Manual deferred NAS sync requested") } }
            }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.5)))
        }
    }
}

struct StatusBadge: View {
    let status: BackupStatus
    var hasProblem = false
    var body: some View {
        Label(hasProblem ? "Action needed" : status.rawValue, systemImage: hasProblem || status == .failed ? "exclamationmark.triangle.fill" : status == .idle ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .help(hasProblem ? storeProblemHelp : status.rawValue)
    }
    private var storeProblemHelp: String { "Open the visible problem details for the affected service and repair action." }
}

struct DeviceCard: View {
    @EnvironmentObject private var store: AppStore
    let device: CameraDevice
    private var sessions: [BackupSession] { store.sessions.filter { $0.deviceID == device.id } }
    private var latest: BackupSession? { sessions.sorted { $0.startedAt > $1.startedAt }.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                DeviceImageView(device: device).frame(width: 76, height: 58)
                Spacer()
                Circle().fill(device.isConnected ? .green : .gray).frame(width: 9, height: 9).padding(.top, 4)
            }
            Text(device.displayName).font(.headline)
            Text(device.model).font(.caption).foregroundStyle(.secondary)
            Divider()
            Text(device.isConnected ? "\(device.filesWaiting) files waiting" : "Last seen \(device.lastSeen.formatted(.relative(presentation: .named)))")
                .font(.caption).foregroundStyle(.secondary)
            if let latest { DeviceMediaSummary(session: latest) }
        }.padding(16).frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.5)))
    }
}

struct DeviceImageView: View {
    let device: CameraDevice
    private var image: NSImage? {
        if let path = device.customImagePath, let custom = NSImage(contentsOfFile: path) { return custom }
        if device.category == .androidPhone { return nil }
        guard let url = Bundle.main.url(forResource: "camera-default", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: device.category == .androidPhone ? "smartphone" : "camera.fill").resizable().scaledToFit().padding(10).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DeviceMediaSummary: View {
    let session: BackupSession
    private var formats: String { session.outputFormats.joined(separator: " · ") }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 16) {
                if session.imageCount > 0 {
                    Label("\(session.imageCount) images", systemImage: "photo").lineLimit(1)
                }
                if session.videoCount > 0 {
                    Label("\(session.videoCount) videos", systemImage: "film").lineLimit(1)
                }
                if session.audioCount > 0 {
                    Label("\(session.audioCount) audio", systemImage: "waveform").lineLimit(1)
                }
            }.font(.caption)
            HStack(spacing: 7) {
                Text(formats).lineLimit(1).truncationMode(.tail)
                if session.transcodedCount > 0 {
                    Text("·").foregroundStyle(.tertiary)
                    Label("\(session.transcodedCount) transcoded", systemImage: "arrow.triangle.2.circlepath")
                        .lineLimit(1)
                }
            }.font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SessionRow: View {
    let session: BackupSession
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: session.filesFailed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(session.filesFailed == 0 ? .green : .orange)
            VStack(alignment: .leading) { Text(session.deviceName).font(.headline); Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(session.filesVerified) files").monospacedDigit()
                MediaOutcomeBadges(session: session, compact: true)
            }
            Text(ByteCountFormatter.string(fromByteCount: session.bytesTransferred, countStyle: .file)).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct MediaOutcomeBadges: View {
    let session: BackupSession
    var compact = false
    var body: some View {
        HStack(spacing: 5) {
            if session.imageCount > 0 { badge("Images", icon: "photo") }
            if session.videoCount > 0 { badge("Video", icon: "film") }
            ForEach(session.outputFormats.filter { ["MP4", "FLAC"].contains($0.uppercased()) }, id: \.self) { format in badge(format, icon: "doc.badge.gearshape") }
            if session.transcodedCount > 0 { badge("\(session.transcodedCount) transcoded", icon: "arrow.triangle.2.circlepath") }
        }
    }
    @ViewBuilder private func badge(_ text: String, icon: String) -> some View {
        if compact {
            Label(text, systemImage: icon).labelStyle(.iconOnly)
                .font(.caption2).help(text)
                .padding(.horizontal, 4).padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        } else {
            Label(text, systemImage: icon)
                .font(.caption2)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
    }
}
