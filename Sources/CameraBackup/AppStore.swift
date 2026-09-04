import Foundation
import SwiftUI
import CryptoKit

@MainActor
final class AppStore: ObservableObject {
    struct TransferLogEntry: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let message: String
    }
    @Published var configuration: AppConfiguration { didSet { scheduleSave() } }
    @Published var status: BackupStatus = .idle
    @Published var progress = 0.0
    @Published var currentFile: String?
    @Published var transferProgress: EngineProgress?
    @Published var transferLog: [TransferLogEntry] = []
    @Published var serviceOperations: [UUID: String] = [:]
    @Published var googlePhotosAuthorized = false
    @Published var googlePhotosAPIActivationURL: URL?
    @Published var flickrAuthorized = false
    @Published var youtubeAuthorized = false
    @Published var videoProcessingStatus: String?
    @Published var draggedServiceID: UUID?
    @Published var cacheSyncStatus: CacheSyncStatus = .idle
    @Published var cachedFileCount = 0
    @Published var cachedBytes: Int64 = 0
    @Published var nasConnectionStatus = "Not tested"
    @Published var nasIsConnected = false
    @Published var devices: [CameraDevice] { didSet { scheduleDeviceSave() } }
    @Published var sessions: [BackupSession]
    @Published var events: [ActivityEvent]
    @Published var selectedDeviceID: UUID?
    @Published var coordinationNodes: [CoordinationNode]
    @Published var clientConnections: [ClientConnectionRecord]
    @Published var previewedDeviceIDs: Set<UUID> = []
    @Published var needsInitialSetup: Bool
    @Published var configurationWarnings: [String] = []
    let adbAvailable: Bool

    private let configurationURL: URL
    private let settingsBackupDirectory: URL
    private let deviceRegistryURL: URL
    private let engine: BackupEngine?
    private let reprocessor: ServiceReprocessor?
    private let googlePhotos: GooglePhotosClient
    private let flickr: FlickrClient
    private var saveTask: Task<Void, Never>?
    private var deviceSaveTask: Task<Void, Never>?
    private var backupTask: Task<Void, Never>?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "Zebtron Camera Zapper", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        configurationURL = support.appending(path: "configuration.json")
        settingsBackupDirectory = support.appending(path: "Settings Backups", directoryHint: .isDirectory)
        deviceRegistryURL = support.appending(path: "device-registry.json")
        var loadedConfiguration = (try? Data(contentsOf: configurationURL)).flatMap { try? JSONDecoder().decode(AppConfiguration.self, from: $0) } ?? AppConfiguration()
        if !loadedConfiguration.services.contains(where: { $0.kind == .googlePhotos }) {
            loadedConfiguration.services.append(.init(id: UUID(), kind: .googlePhotos, name: "Google Photos", isEnabled: false, priority: loadedConfiguration.services.count, isRequiredForDeletion: false, detail: "Upload verified photos and videos to Google Photos", destination: nil, acceptedMedia: [.photo, .raw, .video], outputFormat: "Original", transcodeEnabled: false, remoteLocation: "Camera Zapper", privacy: "Private"))
        }
        if !loadedConfiguration.services.contains(where: { $0.kind == .flickr }) {
            loadedConfiguration.services.append(.init(id: UUID(), kind: .flickr, name: "Flickr", isEnabled: false, priority: loadedConfiguration.services.count, isRequiredForDeletion: false, detail: "Upload verified photos and videos directly to Flickr without Flickr Uploadr", destination: nil, acceptedMedia: [.photo, .video], outputFormat: "Original", transcodeEnabled: false, remoteLocation: "Camera Zapper", privacy: "Private"))
        }
        if let legacyIndex = loadedConfiguration.services.firstIndex(where: { $0.kind == .derivative }) {
            let legacy = loadedConfiguration.services[legacyIndex]
            if loadedConfiguration.transcodeIncompatibleVideos == nil { loadedConfiguration.transcodeIncompatibleVideos = legacy.isEnabled }
            if loadedConfiguration.transcodeDestination == nil { loadedConfiguration.transcodeDestination = legacy.destination }
            // Video processing is optional transformation, never a durable
            // destination that may authorize or block source deletion.
            loadedConfiguration.services[legacyIndex].isRequiredForDeletion = false
        }
        for index in loadedConfiguration.services.indices {
            if loadedConfiguration.services[index].kind == .localStorage {
                loadedConfiguration.services[index].setupState = .operational
            } else if !loadedConfiguration.services[index].isEnabled {
                loadedConfiguration.services[index].isRequiredForDeletion = false
                loadedConfiguration.services[index].setupState = .notSetUp
            } else if loadedConfiguration.services[index].setupState == nil {
                // Existing enabled services are migrated without inventing an
                // error. Validation below promotes them to Operational or
                // Needs attention using their saved, real configuration.
                loadedConfiguration.services[index].setupState = .configuring
            }
        }
        for index in loadedConfiguration.services.indices where [.googlePhotos, .flickr, .youtube].contains(loadedConfiguration.services[index].kind) {
            // Cloud publishing is intentionally not a Camera Zapper feature.
            // These adapters are private-only at both configuration and request level.
            loadedConfiguration.services[index].privacy = "Private (locked)"
        }
        configuration = loadedConfiguration
        let adb = ADBAdapter()
        adbAvailable = adb != nil
        needsInitialSetup = !UserDefaults.standard.bool(forKey: "completedInitialDestinationSetup")

        devices = ((try? Data(contentsOf: deviceRegistryURL)).flatMap { try? JSONDecoder().decode([CameraDevice].self, from: $0) } ?? []).map {
            var device = $0
            device.isConnected = false
            device.connectionDetail = "Offline · reconnect this device to scan or sync"
            return device
        }
        sessions = []
        let localName = Host.current().localizedName ?? "This Mac"
        coordinationNodes = [.init(id: UUID(), name: localName, platform: .macOS, role: loadedConfiguration.coordination.mode == .coordinated ? .coordinator : .ingest, detail: "Local production node", isOnline: true, isPrimary: true, capabilities: ["Ledger", "Verification", "Local cache"], lastSeen: .now)]
        clientConnections = []
        events = []
        let database = try? CameraZapperDatabase(url: support.appending(path: "CameraZapper.sqlite"))
        let googleClient = GooglePhotosClient()
        googlePhotos = googleClient
        let flickrClient = FlickrClient()
        flickr = flickrClient
        engine = database.map { BackupEngine(database: $0, adb: adb, applicationSupport: support) }
        reprocessor = database.map { ServiceReprocessor(database: $0, googlePhotos: googleClient, flickr: flickrClient) }
        let defaults = UserDefaults.standard
        googlePhotosAuthorized = defaults.object(forKey: "authorized.googlePhotos") == nil
            ? loadedConfiguration.services.contains(where: { $0.kind == .googlePhotos && $0.isEnabled })
            : defaults.bool(forKey: "authorized.googlePhotos")
        flickrAuthorized = defaults.object(forKey: "authorized.flickr") == nil
            ? loadedConfiguration.services.contains(where: { $0.kind == .flickr && $0.isEnabled })
            : defaults.bool(forKey: "authorized.flickr")
        youtubeAuthorized = defaults.bool(forKey: "authorized.youtube")
        if let database {
            if devices.isEmpty { devices = (try? database.fetchDevices()) ?? [] }
            sessions = (try? database.fetchSessions()) ?? []
            events = (try? database.fetchEvents()) ?? []
            events.insert(.init(id: UUID(), timestamp: .now, severity: .info, message: "Production engine started. No backup runs without explicit confirmation."), at: 0)
        } else { events = [.init(id: UUID(), timestamp: .now, severity: .error, message: "Could not open the Camera Zapper database.")] }
        // Never touch protected Keychain data during launch. Ad-hoc development
        // signatures change between builds and would otherwise trigger a prompt
        // for every stored OAuth record before the user starts an operation.
        validateConfiguration()
        if configuration.services.contains(where: { $0.isEnabled && $0.isRequiredForDeletion && !serviceIsOperational($0) }) {
            needsInitialSetup = true
        }
        if adb == nil {
            events.insert(.init(id: UUID(), timestamp: .now, severity: .warning, message: "Android support needs ADB. Install Android Platform Tools with Homebrew (`brew install android-platform-tools`) or Android Studio, then relaunch Camera Zapper."), at: 0)
        }
        Task { await refreshSources() }
    }

    var activeDevice: CameraDevice? { devices.first(where: { $0.isConnected }) }
    var enabledServices: [ServiceConfiguration] { configuration.services.filter(\.isEnabled).sorted { $0.priority < $1.priority } }
    var setupIncomplete: Bool {
        !UserDefaults.standard.bool(forKey: "completedInitialDestinationSetup") || configuration.services.contains {
            $0.isEnabled && $0.isRequiredForDeletion && !serviceIsOperational($0)
        }
    }

    func runSetupAgain() { needsInitialSetup = true }

    func skipSetupForNow() {
        needsInitialSetup = false
        record("Setup wizard skipped; Finish setup remains available", severity: .info)
    }

    var settingsBackupFolder: URL { settingsBackupDirectory }

    func exportSettings(to url: URL) throws {
        let data = try JSONEncoder.pretty.encode(SettingsExport(configuration: configuration))
        try data.write(to: url, options: .atomic)
        record("Settings exported without passwords, API secrets, or OAuth tokens", severity: .success)
    }

    func importSettings(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoded: AppConfiguration
        if let envelope = try? JSONDecoder().decode(SettingsExport.self, from: data) {
            decoded = envelope.configuration
        } else {
            decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)
        }
        try persistPreImportSettingsBackup(configuration)
        configuration = decoded
        for index in configuration.services.indices {
            let service = configuration.services[index]
            if service.kind == .localStorage {
                configuration.services[index].isEnabled = true
                configuration.services[index].isRequiredForDeletion = true
                configuration.services[index].setupState = .operational
            } else if !service.isEnabled {
                configuration.services[index].isRequiredForDeletion = false
                configuration.services[index].setupState = .notSetUp
            } else if [.googlePhotos, .youtube, .flickr].contains(service.kind) {
                configuration.services[index].setupState = .configuring
            }
        }
        googlePhotosAuthorized = false
        youtubeAuthorized = false
        flickrAuthorized = false
        UserDefaults.standard.set(false, forKey: "authorized.googlePhotos")
        UserDefaults.standard.set(false, forKey: "authorized.youtube")
        UserDefaults.standard.set(false, forKey: "authorized.flickr")
        UserDefaults.standard.set(false, forKey: "completedInitialDestinationSetup")
        needsInitialSetup = true
        validateConfiguration()
        persistSettingsBackup(configuration)
        record("Settings imported; cloud services need authorization on this Mac", severity: .success)
    }

    func setServiceEnabled(_ id: UUID, _ enabled: Bool) {
        guard let index = configuration.services.firstIndex(where: { $0.id == id }) else { return }
        configuration.services[index].isEnabled = enabled
        if enabled {
            configuration.services[index].setupState = .configuring
        } else {
            configuration.services[index].isRequiredForDeletion = false
            configuration.services[index].setupState = .notSetUp
            serviceOperations.removeValue(forKey: id)
        }
        validateConfiguration()
    }

    func moveServices(from source: IndexSet, to destination: Int) {
        var ordered = configuration.services.sorted { $0.priority < $1.priority }
        ordered.move(fromOffsets: source, toOffset: destination)
        if let localIndex = ordered.firstIndex(where: { $0.kind == .localStorage }) {
            let local = ordered.remove(at: localIndex)
            ordered.insert(local, at: 0)
        }
        for index in ordered.indices { ordered[index].priority = index }
        configuration.services = ordered
    }

    func moveService(_ draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID else { return }
        var ordered = configuration.services.sorted { $0.priority < $1.priority }
        guard let source = ordered.firstIndex(where: { $0.id == draggedID }),
              let target = ordered.firstIndex(where: { $0.id == targetID }),
              ordered[source].kind != .localStorage else { return }
        let moved = ordered.remove(at: source)
        let adjustedTarget = ordered.firstIndex(where: { $0.id == targetID }) ?? target
        ordered.insert(moved, at: max(1, adjustedTarget))
        for index in ordered.indices { ordered[index].priority = index }
        configuration.services = ordered
    }

    func addStorageService() {
        addService(.storage)
    }

    func addService(_ kind: ServiceKind) {
        let template: ServiceConfiguration
        switch kind {
        case .storage:
            template = .init(id: UUID(), kind: kind, name: "Additional Storage", isEnabled: true, priority: configuration.services.count, isRequiredForDeletion: false, detail: "Additional verified archive destination", destination: "/Volumes/Backup", acceptedMedia: Set(MediaKind.allCases), outputFormat: "Original", transcodeEnabled: false, remoteLocation: nil, privacy: nil)
        case .s3:
            template = .init(id: UUID(), kind: kind, name: "Amazon S3", isEnabled: true, priority: configuration.services.count, isRequiredForDeletion: false, detail: "Upload verified originals to an S3 bucket", destination: nil, acceptedMedia: Set(MediaKind.allCases), outputFormat: "Original", transcodeEnabled: false, remoteLocation: "s3://camera-backup", privacy: "Private bucket")
        case .youtube:
            template = .init(id: UUID(), kind: kind, name: "YouTube Video Backup", isEnabled: true, priority: configuration.services.count, isRequiredForDeletion: false, detail: "Upload new videos privately to YouTube", destination: nil, acceptedMedia: [.video], outputFormat: "MP4", transcodeEnabled: true, remoteLocation: "Camera Zapper", privacy: "Private")
        case .googlePhotos:
            template = .init(id: UUID(), kind: kind, name: "Google Photos", isEnabled: true, priority: configuration.services.count, isRequiredForDeletion: false, detail: "Upload verified photos and videos to Google Photos", destination: nil, acceptedMedia: [.photo, .raw, .video], outputFormat: "Original", transcodeEnabled: false, remoteLocation: "Camera Zapper", privacy: "Private")
        case .flickr:
            template = .init(id: UUID(), kind: kind, name: "Flickr", isEnabled: true, priority: configuration.services.count, isRequiredForDeletion: false, detail: "Upload verified photos and videos directly to Flickr without Flickr Uploadr", destination: nil, acceptedMedia: [.photo, .video], outputFormat: "Original", transcodeEnabled: false, remoteLocation: "Camera Zapper", privacy: "Private")
        case .amazonPhotos:
            template = .init(id: UUID(), kind: kind, name: "Amazon Photos", isEnabled: true, priority: configuration.services.count, isRequiredForDeletion: false, detail: "Upload compatible media to Amazon Photos", destination: nil, acceptedMedia: [.photo, .video], outputFormat: "Original", transcodeEnabled: false, remoteLocation: "Camera Zapper", privacy: "Private")
        case .iCloud:
            template = .init(id: UUID(), kind: kind, name: "iCloud Drive", isEnabled: true, priority: configuration.services.count, isRequiredForDeletion: false, detail: "Copy verified media into iCloud Drive", destination: "~/Library/Mobile Documents/com~apple~CloudDocs/Camera Zapper", acceptedMedia: Set(MediaKind.allCases), outputFormat: "Original", transcodeEnabled: false, remoteLocation: "iCloud Drive/Camera Zapper", privacy: "Private")
        case .photos:
            template = .init(id: UUID(), kind: kind, name: "Apple Photos", isEnabled: true, priority: configuration.services.count, isRequiredForDeletion: false, detail: "Import compatible photos into Photos", destination: nil, acceptedMedia: [.photo], outputFormat: "Original", transcodeEnabled: false, remoteLocation: nil, privacy: nil)
        case .derivative:
            template = .init(id: UUID(), kind: kind, name: "Compatibility Video Copies", isEnabled: true, priority: configuration.services.count, isRequiredForDeletion: false, detail: "Create easy-to-play MP4 copies while preserving the original video", destination: "~/Movies/Camera Zapper/Compatibility Videos", acceptedMedia: [.video], outputFormat: "MP4", transcodeEnabled: true, remoteLocation: nil, privacy: nil)
        case .neofinder:
            template = .init(id: UUID(), kind: kind, name: "NeoFinder", isEnabled: true, priority: configuration.services.count, isRequiredForDeletion: false, detail: "Catalog verified destination files", destination: nil, acceptedMedia: Set(MediaKind.allCases), outputFormat: nil, transcodeEnabled: false, remoteLocation: nil, privacy: nil)
        case .localStorage: return
        }
        configuration.services.append(template)
    }

    func deleteService(_ id: UUID) {
        guard let service = configuration.services.first(where: { $0.id == id }), service.kind != .localStorage else { return }
        configuration.services.removeAll { $0.id == id }
        for index in configuration.services.indices { configuration.services[index].priority = index }
    }

    func serviceCapability(_ service: ServiceConfiguration) -> String {
        if let operation = serviceOperations[service.id] { return operation }
        if service.kind != .localStorage && (!service.isEnabled || service.setupState == .notSetUp) { return "Not set up" }
        if service.setupState == .configuring { return "Configuring · complete setup and test" }
        if service.setupState == .needsAttention {
            return switch service.kind {
            case .storage: "Needs attention · volume not mounted or folder not writable"
            case .neofinder: "Needs attention · NeoFinder is not installed"
            case .googlePhotos: "Needs attention · Google authorization must be repaired"
            case .youtube: "Needs attention · private YouTube authorization must be repaired"
            case .flickr: "Needs attention · Flickr authorization must be repaired"
            default: "Needs attention · open configuration for the next step"
            }
        }
        switch service.kind {
        case .localStorage: return "Operational · verified local archive"
        case .storage: return FileManager.default.isWritableFile(atPath: NSString(string: service.destination ?? "").expandingTildeInPath) ? "Operational · catch-up available" : "Unavailable · destination not mounted/writable"
        case .photos: return "Operational · macOS will request Photos permission"
        case .neofinder: return FileManager.default.fileExists(atPath: "/Applications/NeoFinder.app") ? "Operational · catalog/update automation available" : "Unavailable · NeoFinder is not installed"
        case .youtube: return youtubeAuthorized ? "Operational · private uploads authorized · limit 100 uploads/day" : "Setup required · authorize private YouTube uploads"
        case .googlePhotos: return googlePhotosAuthorized ? "Operational · Google account authorized" : "Setup required · select downloaded OAuth JSON"
        case .flickr: return flickrAuthorized ? "Operational · Flickr account authorized" : "Setup required · Flickr API key and write authorization"
        case .derivative: return FileManager.default.isExecutableFile(atPath: "/usr/bin/avconvert") ? "Operational · uses the macOS avconvert tool" : "Unavailable · macOS avconvert was not found"
        case .s3, .amazonPhotos, .iCloud: return "Unavailable · transfer adapter is not implemented yet"
        }
    }

    func serviceIsOperational(_ service: ServiceConfiguration) -> Bool {
        if service.kind != .localStorage && (!service.isEnabled || service.setupState == .notSetUp) { return false }
        return switch service.kind {
        case .localStorage, .photos: true
        case .storage: FileManager.default.isWritableFile(atPath: NSString(string: service.destination ?? "").expandingTildeInPath)
        case .googlePhotos: googlePhotosAuthorized
        case .neofinder: FileManager.default.fileExists(atPath: "/Applications/NeoFinder.app")
        case .flickr: flickrAuthorized
        case .youtube: youtubeAuthorized
        case .derivative: FileManager.default.isExecutableFile(atPath: "/usr/bin/avconvert")
        case .s3, .amazonPhotos, .iCloud: false
        }
    }

    func configureYouTube(serviceID: UUID) {
        serviceOperations[serviceID] = "Waiting for YouTube authorization in your browser…"
        Task { [weak self] in
            do {
                try await self?.googlePhotos.authorizeYouTube()
                self?.youtubeAuthorized = true
                self?.markService(serviceID, state: .operational)
                UserDefaults.standard.set(true, forKey: "authorized.youtube")
                self?.serviceOperations.removeValue(forKey: serviceID)
                self?.record("YouTube authorized for private video uploads", severity: .success)
            } catch {
                self?.serviceOperations[serviceID] = "Setup failed · \(error.localizedDescription)"
                self?.markService(serviceID, state: .needsAttention)
                self?.record("YouTube setup failed: \(error.localizedDescription)", severity: .error)
            }
        }
    }

    func configureFlickr(key: String, secret: String, serviceID: UUID) {
        serviceOperations[serviceID] = "Waiting for Flickr authorization in your browser…"
        Task { [weak self] in
            do {
                try await self?.flickr.configureAndAuthorize(key: key, secret: secret)
                self?.flickrAuthorized = true
                self?.markService(serviceID, state: .operational)
                UserDefaults.standard.set(true, forKey: "authorized.flickr")
                self?.serviceOperations.removeValue(forKey: serviceID)
                self?.record("Flickr account authorized with write access", severity: .success)
            } catch {
                self?.serviceOperations[serviceID] = "Setup failed · \(error.localizedDescription)"
                self?.markService(serviceID, state: .needsAttention)
                self?.record("Flickr setup failed: \(error.localizedDescription)", severity: .error)
            }
        }
    }

    func canReprocess(_ service: ServiceConfiguration) -> Bool {
        service.isEnabled && (service.kind == .storage || service.kind == .photos || service.kind == .neofinder || (service.kind == .googlePhotos && googlePhotosAuthorized) || (service.kind == .flickr && flickrAuthorized) || (service.kind == .youtube && youtubeAuthorized)) && !serviceOperationIsRunning(service.id)
    }

    func serviceOperationIsRunning(_ id: UUID) -> Bool {
        guard let status = serviceOperations[id] else { return false }
        return !status.hasPrefix("Failed") && !status.hasPrefix("Skipped") && status != "Catch-up complete" && !status.hasPrefix("Catch-up complete ·")
    }

    func serviceCanResume(_ id: UUID) -> Bool {
        guard let status = serviceOperations[id] else { return false }
        return status.hasPrefix("Failed") || status.hasPrefix("Skipped")
    }

    func configureGooglePhotos(from url: URL, serviceID: UUID) {
        serviceOperations[serviceID] = "Reading OAuth client file…"
        Task { [weak self] in
            do {
                let accessing = url.startAccessingSecurityScopedResource(); defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                self?.serviceOperations[serviceID] = "Waiting for Google authorization in your browser…"
                try await self?.googlePhotos.importAndAuthorize(data: data)
                self?.googlePhotosAuthorized = true
                self?.markService(serviceID, state: .operational)
                UserDefaults.standard.set(true, forKey: "authorized.googlePhotos")
                self?.serviceOperations.removeValue(forKey: serviceID)
                self?.record("Google Photos account authorized", severity: .success)
            } catch {
                self?.serviceOperations[serviceID] = "Setup failed · \(error.localizedDescription)"
                self?.markService(serviceID, state: .needsAttention)
                self?.record("Google Photos setup failed: \(error.localizedDescription)", severity: .error)
            }
        }
    }

    func reprocessService(_ id: UUID) {
        guard let service = configuration.services.first(where: { $0.id == id }),
              let local = configuration.services.first(where: { $0.kind == .localStorage }),
              let reprocessor else { return }
        serviceOperations[id] = "Starting catch-up…"
        Task { [weak self] in
            do {
                try await reprocessor.run(service: service, localService: local) { completed, total, message in
                    await MainActor.run {
                        self?.serviceOperations[id] = completed == total && message.hasPrefix("Flickr complete") ? "Catch-up complete · \(message)" : "\(completed) of \(total) · \(message)"
                        if message.hasPrefix("Already on Flickr") { self?.record(message) }
                    }
                }
                if service.kind != .flickr { self?.serviceOperations[id] = "Catch-up complete" }
                self?.record("\(service.name) catch-up completed", severity: .success)
            } catch {
                if let googleError = error as? GooglePhotosError { self?.googlePhotosAPIActivationURL = googleError.activationURL }
                self?.serviceOperations[id] = "Failed · \(error.localizedDescription)"
                self?.record("\(service.name) catch-up failed: \(error.localizedDescription)", severity: .error)
            }
        }
    }

    func catchUpVideoProcessing() {
        guard configuration.transcodeIncompatibleVideos ?? false,
              let local = configuration.services.first(where: { $0.kind == .localStorage }), let reprocessor else { return }
        let config = configuration
        videoProcessingStatus = "Starting…"
        Task { [weak self] in
            do {
                try await reprocessor.transcodeCompatibilityCopies(configuration: config, localService: local) { completed, total, message in
                    await MainActor.run { self?.videoProcessingStatus = "\(completed) of \(total) · \(message)" }
                }
                self?.record("Video processing catch-up completed", severity: .success)
            } catch {
                self?.videoProcessingStatus = "Failed · \(error.localizedDescription)"
                self?.record("Video processing catch-up failed: \(error.localizedDescription)", severity: .error)
            }
        }
    }

    func record(_ message: String, severity: ActivityEvent.Severity = .info) {
        events.insert(.init(id: UUID(), timestamp: .now, severity: severity, message: message), at: 0)
    }

    func setDeviceImage(_ id: UUID, path: String?) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[index].customImagePath = path
    }

    func setAndroidConnectionMethod(_ id: UUID, method: AndroidConnectionMethod) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[index].androidConnectionMethod = method
    }

    func isDeviceApproved(_ device: CameraDevice) -> Bool { UserDefaults.standard.bool(forKey: "approvedDevice.\(device.volumeUUID)") }

    func runFullWorkflow(deviceID: UUID) {
        runFullWorkflow(deviceID: deviceID, deleteAfterSuccess: false)
    }

    func runFullWorkflowAndDelete(deviceID: UUID) {
        runFullWorkflow(deviceID: deviceID, deleteAfterSuccess: true)
    }

    private func runFullWorkflow(deviceID: UUID, deleteAfterSuccess: Bool) {
        guard backupTask == nil, let engine, let reprocessor, let device = devices.first(where: { $0.id == deviceID }) else { return }
        UserDefaults.standard.set(true, forKey: "approvedDevice.\(device.volumeUUID)")
        let config = configuration
        transferLog = []; appendTransferLog("Full workflow\(deleteAfterSuccess ? " with verified source deletion" : "") requested for \(device.displayName)")
        transferProgress = .init(status: .scanning, completedFiles: 0, totalFiles: 0, currentFile: nil, fraction: 0, message: "Scanning configured phone folders", phase: "Scanning phone")
        backupTask = Task { [weak self] in
            do {
                let preview = try await engine.scanAndroid(serial: device.volumeUUID, folders: device.sourceFolders) { [weak self] message in Task { @MainActor in self?.appendTransferLog(message) } }
                guard let self else { return }
                if let index = self.devices.firstIndex(where: { $0.id == deviceID }) { self.devices[index].filesWaiting = preview.count }
                self.previewedDeviceIDs.insert(deviceID); self.appendTransferLog("Preview complete: \(preview.count) supported files")
                let result = try await engine.backupAndroid(device: device, serial: device.volumeUUID, folders: device.sourceFolders, configuration: config) { [weak self] value in await self?.applyEngineProgress(value) }
                self.sessions.insert(result.session, at: 0); self.events.insert(contentsOf: result.events, at: 0)
                guard let local = config.services.first(where: { $0.kind == .localStorage }) else { throw EngineError.destinationUnavailable("Local Device Archive") }
                var requiredFailures: [String] = []
                for service in config.services.filter(\.isEnabled).sorted(by: { $0.priority < $1.priority }) where service.kind != .localStorage && service.kind != .derivative {
                    guard self.serviceIsOperational(service), [.storage, .photos, .googlePhotos, .flickr, .neofinder, .youtube].contains(service.kind) else {
                        self.serviceOperations[service.id] = "Skipped · setup or adapter required"
                        self.appendTransferLog("Skipped service: \(service.name) — setup or adapter required")
                        if service.isRequiredForDeletion { requiredFailures.append(service.name) }
                        continue
                    }
                    self.serviceOperations[service.id] = "Starting…"; self.appendTransferLog("Starting service: \(service.name)")
                    do {
                        try await reprocessor.run(service: service, localService: local) { completed, total, message in await MainActor.run { self.serviceOperations[service.id] = "\(completed) of \(total) · \(message)" } }
                        self.serviceOperations[service.id] = "Catch-up complete"; self.appendTransferLog("Completed service: \(service.name)")
                    } catch {
                        self.serviceOperations[service.id] = "Failed · \(error.localizedDescription)"
                        self.appendTransferLog("Service failed: \(service.name) — \(error.localizedDescription)")
                        self.record("\(service.name) catch-up failed: \(error.localizedDescription)", severity: .error)
                        if service.isRequiredForDeletion { requiredFailures.append(service.name) }
                    }
                }
                if deleteAfterSuccess {
                    guard requiredFailures.isEmpty else {
                        throw EngineError.deletionBlocked("Required services did not complete: \(requiredFailures.joined(separator: ", "))")
                    }
                    self.appendTransferLog("All required services completed; starting final deletion preflight")
                    let deleted = try await engine.verifyAndDeleteAndroid(device: device, configuration: config) { [weak self] value in await self?.applyEngineProgress(value) }
                    self.appendTransferLog("Deletion complete: \(deleted) verified originals removed from \(device.displayName)")
                    self.record("Full workflow completed and deleted \(deleted) verified originals from \(device.displayName)", severity: .success)
                    if let index = self.devices.firstIndex(where: { $0.id == deviceID }) { self.devices[index].filesWaiting = max(0, self.devices[index].filesWaiting - deleted) }
                }
                if var value = self.transferProgress { value.phase = deleteAfterSuccess ? "Workflow and deletion complete" : "Full workflow complete"; value.message = deleteAfterSuccess ? "All required services verified; source originals deleted" : "All operational enabled services finished in priority order"; value.fraction = 1; self.transferProgress = value }
                self.status = .review
                if !deleteAfterSuccess { self.record("Full workflow completed for \(device.displayName)", severity: .success) }
                self.backupTask = nil
            } catch {
                self?.status = .failed; self?.appendTransferLog("Full workflow stopped: \(error.localizedDescription)")
                self?.record("Full workflow failed: \(error.localizedDescription)", severity: .error); self?.backupTask = nil
            }
        }
    }

    func refreshSources() async {
        guard let engine else { return }
        do {
            let snapshots = try await engine.discoverAndroid()
            var merged = devices.map { device -> CameraDevice in
                var offline = device
                offline.isConnected = false
                offline.connectionDetail = "Offline · reconnect this device to scan or sync"
                return offline
            }
            for snapshot in snapshots {
                if let index = merged.firstIndex(where: { $0.volumeUUID == snapshot.serial }) {
                    let previous = merged[index]
                    var refreshed = androidDevice(from: snapshot, nickname: previous.displayName)
                    refreshed.id = previous.id
                    refreshed.customImagePath = previous.customImagePath
                    refreshed.androidConnectionMethod = previous.androidConnectionMethod
                    refreshed.sourceFolders = previous.sourceFolders
                    refreshed.filesWaiting = previous.filesWaiting
                    refreshed.detectedImageCount = previous.detectedImageCount
                    refreshed.detectedVideoCount = previous.detectedVideoCount
                    if refreshed.releaseYear == nil { refreshed.releaseYear = previous.releaseYear }
                    if refreshed.observedCardCapacitiesGB.isEmpty { refreshed.observedCardCapacitiesGB = previous.observedCardCapacitiesGB }
                    if refreshed.rawFormats.isEmpty { refreshed.rawFormats = previous.rawFormats; refreshed.shootsRAW = previous.shootsRAW }
                    merged[index] = refreshed
                } else {
                    merged.append(androidDevice(from: snapshot, nickname: nil))
                }
            }
            devices = merged.sorted {
                if $0.isConnected != $1.isConnected { return $0.isConnected && !$1.isConnected }
                return $0.lastSeen > $1.lastSeen
            }
            let authorized = snapshots.filter(\.isAuthorized).count
            record("Detected \(authorized) authorized Android device\(authorized == 1 ? "" : "s")", severity: authorized > 0 ? .success : .info)
        } catch {
            record("Android discovery failed: \(error.localizedDescription)", severity: .error)
        }
    }

    func previewAndroid(deviceID: UUID) {
        guard let engine, let device = devices.first(where: { $0.id == deviceID }), device.category == .androidPhone else { return }
        status = .scanning; currentFile = "Reading selected folders"; progress = 0
        let startedAt = Date()
        transferLog = []
        appendTransferLog("Scan requested for \(device.displayName)")
        appendTransferLog("Reading \(device.sourceFolders.count) configured folders over ADB; no files will be copied")
        transferProgress = .init(status: .scanning, completedFiles: 0, totalFiles: 0, currentFile: nil, fraction: 0, message: "Reading Camera, Expert RAW, Google Photos, and Screenshots", phase: "Scanning phone", startedAt: startedAt)
        Task { [weak self] in
            do {
                let files = try await engine.scanAndroid(serial: device.volumeUUID, folders: device.sourceFolders) { [weak self] message in
                    Task { @MainActor in
                        guard let self else { return }
                        if var value = self.transferProgress {
                            value.message = message
                            value.phase = "Scanning phone"
                            self.transferProgress = value
                        }
                        if self.transferLog.last?.message != message { self.appendTransferLog(message) }
                    }
                }
                guard let self else { return }
                if let index = self.devices.firstIndex(where: { $0.id == deviceID }) {
                    self.devices[index].filesWaiting = files.count
                    self.devices[index].detectedImageCount = files.filter { $0.kind == .photo || $0.kind == .raw }.count
                    self.devices[index].detectedVideoCount = files.filter { $0.kind == .video }.count
                }
                self.previewedDeviceIDs.insert(deviceID)
                self.status = .idle; self.currentFile = nil; self.progress = 0
                self.transferProgress = .init(status: .idle, completedFiles: files.count, totalFiles: files.count, currentFile: nil, fraction: 1, message: "Preview found \(files.count) supported files; no files were copied", phase: "Preview complete", totalBytes: files.reduce(Int64(0)) { $0 + $1.size }, startedAt: startedAt)
                self.appendTransferLog("Preview complete: \(files.count) supported files, \(ByteCountFormatter.string(fromByteCount: files.reduce(Int64(0)) { $0 + $1.size }, countStyle: .file)) total")
                self.record("Preview complete: \(files.count) supported files found on \(device.displayName)", severity: .success)
            } catch {
                self?.status = .failed; self?.currentFile = nil
                self?.transferProgress = .init(status: .failed, completedFiles: 0, totalFiles: 0, currentFile: nil, fraction: 0, message: error.localizedDescription, phase: "Preview failed", startedAt: startedAt)
                self?.appendTransferLog("Preview failed: \(error.localizedDescription)")
                self?.record("Preview failed: \(error.localizedDescription)", severity: .error)
            }
        }
    }

    func startAndroidBackup(deviceID: UUID) {
        guard backupTask == nil, previewedDeviceIDs.contains(deviceID), let engine, let device = devices.first(where: { $0.id == deviceID }), device.category == .androidPhone else { return }
        let config = configuration
        transferLog = []
        appendTransferLog("Verified backup requested for \(device.displayName)")
        appendTransferLog("Scanning the phone again to create an exact transfer manifest")
        transferProgress = .init(status: .scanning, completedFiles: 0, totalFiles: devices.first(where: { $0.id == deviceID })?.filesWaiting ?? 0, currentFile: nil, fraction: 0, message: "Preparing verified backup", phase: "Preparing")
        backupTask = Task { [weak self] in
            do {
                let result = try await engine.backupAndroid(device: device, serial: device.volumeUUID, folders: device.sourceFolders, configuration: config) { [weak self] value in
                    await self?.applyEngineProgress(value)
                }
                guard let self else { return }
                self.sessions.insert(result.session, at: 0)
                self.events.insert(contentsOf: result.events, at: 0)
                self.backupTask = nil
            } catch {
                if Task.isCancelled || error is CancellationError {
                    self?.status = .idle; self?.currentFile = nil
                    if var value = self?.transferProgress { value.status = .idle; value.phase = "Cancelled"; value.message = "Backup cancelled safely; source files were not changed"; self?.transferProgress = value }
                    self?.record("Backup cancelled safely", severity: .warning)
                } else {
                    self?.status = .failed; self?.currentFile = nil
                    self?.record("Backup failed: \(error.localizedDescription)", severity: .error)
                }
                self?.backupTask = nil
            }
        }
    }

    func cancelBackup() {
        backupTask?.cancel(); backupTask = nil; status = .idle; currentFile = nil
        if var value = transferProgress { value.status = .idle; value.phase = "Cancelled"; value.message = "Backup cancelled safely; source files were not changed"; transferProgress = value }
    }

    func verifyAndDelete(deviceID: UUID) {
        guard backupTask == nil, let engine, let device = devices.first(where: { $0.id == deviceID }), device.isConnected else { return }
        let config = configuration
        transferLog = []
        appendTransferLog("Verify & Delete requested for \(device.displayName)")
        appendTransferLog("Every preflight check must pass before the first source file is deleted")
        backupTask = Task { [weak self] in
            do {
                let count = try await engine.verifyAndDeleteAndroid(device: device, configuration: config) { [weak self] value in await self?.applyEngineProgress(value) }
                guard let self else { return }
                self.appendTransferLog("Deletion complete: \(count) verified originals removed from \(device.displayName)")
                self.record("Deleted \(count) verified originals from \(device.displayName)", severity: .success)
                if let index = self.devices.firstIndex(where: { $0.id == deviceID }) { self.devices[index].filesWaiting = max(0, self.devices[index].filesWaiting - count) }
                self.backupTask = nil
            } catch {
                self?.status = .failed
                if var value = self?.transferProgress {
                    value.status = .failed
                    value.phase = "Deletion blocked"
                    value.message = error.localizedDescription
                    value.failedFiles = 1
                    self?.transferProgress = value
                }
                self?.appendTransferLog(error.localizedDescription)
                self?.record(error.localizedDescription, severity: .error)
                self?.backupTask = nil
            }
        }
    }

    private func applyEngineProgress(_ value: EngineProgress) {
        status = value.status; progress = value.fraction; currentFile = value.currentFile ?? value.message; transferProgress = value
        let detail = value.currentFile.map { "\(value.phase): \($0) — \(value.message)" } ?? "\(value.phase): \(value.message)"
        if transferLog.last?.message != detail { appendTransferLog(detail) }
    }

    private func appendTransferLog(_ message: String) {
        transferLog.append(.init(message: message))
        if transferLog.count > 100 { transferLog.removeFirst(transferLog.count - 100) }
    }

    private func androidDevice(from snapshot: AndroidDeviceSnapshot, nickname: String?) -> CameraDevice {
        let isS22 = snapshot.model.uppercased().contains("SM-S908")
        let id = stableDeviceID(for: snapshot.serial)
        return CameraDevice(id: id, displayName: nickname ?? (isS22 ? "Samsung Galaxy S22 Ultra" : snapshot.model), model: isS22 ? "Galaxy S22 Ultra · \(snapshot.model)" : snapshot.model, volumeName: snapshot.model, volumeUUID: snapshot.serial, isConnected: snapshot.isAuthorized, lastSeen: .now, filesWaiting: 0, manufacturer: snapshot.manufacturer.capitalized, releaseYear: isS22 ? 2022 : nil, sensorDescription: isS22 ? "108 MP wide + multi-camera system" : "Detected from media metadata after first scan", observedCardCapacitiesGB: isS22 ? [512] : [], videoCapability: isS22 ? "8K video · 4K up to 60p" : "Detected after first scan", shootsRAW: isS22, rawFormats: isS22 ? ["DNG", "Expert RAW"] : [], videoFormats: ["MP4", "HEVC"], customImagePath: nil, category: .androidPhone, androidConnectionMethod: .automatic, sourceFolders: isS22 ? ["/sdcard/DCIM/Camera", "/sdcard/DCIM/Expert RAW", "/sdcard/DCIM/Google Photos", "/sdcard/DCIM/Screenshots"] : ["/sdcard/DCIM"], supportedCardTypes: ["No removable memory-card slot"], recommendedCardSpeed: "Built-in storage", recommendedCardMakers: [], operatingSystem: "Android \(snapshot.androidVersion) · API \(snapshot.apiLevel)", connectionProvider: "\(snapshot.connection) · automatically selected", connectionDetail: snapshot.isAuthorized ? "Authorized and ready for read-only scanning" : "Authorization required on device", usableStorageGiB: nil, usedStorageGiB: nil, freeStorageGiB: nil, detectedImageCount: nil, detectedVideoCount: nil, availableConnectionMethods: ["ADB over USB", "MacDroid File Provider", "OpenMTP / direct MTP", "ADB over Wi-Fi"])
    }

    private func stableDeviceID(for stableID: String) -> UUID {
        let key = "deviceUUID.\(stableID)"
        if let value = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: value) { return id }
        let id = UUID(); UserDefaults.standard.set(id.uuidString, forKey: key); return id
    }

    func mockTestNASConnection() {
        nasConnectionStatus = "Checking…"
        let storageIndex = configuration.services.firstIndex { $0.kind == .storage && $0.isEnabled }
        let path = storageIndex.flatMap { configuration.services[$0].destination } ?? configuration.nasMountPath
        record("Testing the selected NAS destination")
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            let result = verifyWritableDestination(path)
            nasIsConnected = result == nil
            nasConnectionStatus = result == nil ? "Connected, writable, and verified" : (result ?? "Needs attention")
            if let storageIndex {
                configuration.services[storageIndex].setupState = nasIsConnected ? .operational : .needsAttention
            }
            record(nasConnectionStatus, severity: nasIsConnected ? .success : .warning)
        }
    }

    func markService(_ id: UUID, state: ServiceSetupState) {
        guard let index = configuration.services.firstIndex(where: { $0.id == id }) else { return }
        configuration.services[index].setupState = state
    }

    func updateServiceDestination(_ id: UUID, path: String) {
        guard let index = configuration.services.firstIndex(where: { $0.id == id }) else { return }
        configuration.services[index].destination = path
        configuration.services[index].setupState = .configuring
        if configuration.services[index].kind == .storage {
            configuration.nasMountPath = path
        }
        validateConfiguration()
    }

    func testService(_ id: UUID) {
        guard let index = configuration.services.firstIndex(where: { $0.id == id }) else { return }
        configuration.services[index].setupState = .configuring
        let service = configuration.services[index]
        switch service.kind {
        case .localStorage, .storage:
            validateConfiguration()
        case .photos:
            configuration.services[index].setupState = .operational
            serviceOperations[id] = "Operational · Photos permission requested when first used"
        case .neofinder:
            let found = FileManager.default.fileExists(atPath: "/Applications/NeoFinder.app")
            configuration.services[index].setupState = found ? .operational : .needsAttention
            serviceOperations[id] = found ? "Operational · NeoFinder detected" : "Needs attention · install NeoFinder in Applications"
        case .googlePhotos:
            configuration.services[index].setupState = googlePhotosAuthorized ? .operational : .configuring
            serviceOperations[id] = googlePhotosAuthorized ? "Operational · Google account authorized" : "Configuring · choose the Google OAuth JSON"
        case .youtube:
            configuration.services[index].setupState = youtubeAuthorized ? .operational : .configuring
            serviceOperations[id] = youtubeAuthorized ? "Operational · private YouTube uploads authorized" : "Configuring · authorize Google Photos first, then YouTube"
        case .flickr:
            configuration.services[index].setupState = flickrAuthorized ? .operational : .configuring
            serviceOperations[id] = flickrAuthorized ? "Operational · Flickr account authorized" : "Configuring · enter a Flickr API key and secret"
        case .derivative:
            configuration.services[index].setupState = FileManager.default.isExecutableFile(atPath: "/usr/bin/avconvert") ? .operational : .needsAttention
        case .s3, .amazonPhotos, .iCloud:
            configuration.services[index].setupState = .needsAttention
            serviceOperations[id] = "Needs attention · this adapter is not available in the controlled beta"
        }
    }

    /// Returns nil only after a write → SHA-256 read-back → delete probe.
    func verifyWritableDestination(_ text: String) -> String? {
        let path = NSString(string: text).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "Volume not mounted — connect it or choose another folder"
        }
        guard FileManager.default.isWritableFile(atPath: path) else {
            return "Folder not writable — choose another folder"
        }
        let probe = URL(fileURLWithPath: path).appending(path: ".camera-zapper-write-test-\(UUID().uuidString)")
        do {
            let payload = Data("Camera Zapper destination verification".utf8)
            try payload.write(to: probe, options: .atomic)
            let expected = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            let readBack = try FileHasher.sha256(url: probe)
            guard expected == readBack else { throw EngineError.hashMismatch(probe.lastPathComponent) }
            try FileManager.default.removeItem(at: probe)
            return nil
        } catch {
            try? FileManager.default.removeItem(at: probe)
            return "Verification test failed — \(error.localizedDescription)"
        }
    }

    func completeInitialSetup() {
        validateConfiguration()
        let unverifiedRequired = configuration.services.filter {
            $0.isEnabled && $0.isRequiredForDeletion && !serviceIsOperational($0)
        }
        guard configurationWarnings.isEmpty, unverifiedRequired.isEmpty else {
            for service in unverifiedRequired {
                if !configurationWarnings.contains(where: { $0.contains(service.name) }) {
                    configurationWarnings.append("\(service.name) must verify before setup can finish.")
                }
            }
            return
        }
        UserDefaults.standard.set(true, forKey: "completedInitialDestinationSetup")
        needsInitialSetup = false
        record("Initial destination setup completed", severity: .success)
    }

    func validateConfiguration() {
        var warnings: [String] = []
        let fileServices = configuration.services.filter { $0.isEnabled && ($0.kind == .localStorage || $0.kind == .storage) }
        if fileServices.isEmpty {
            warnings.append("Enable and configure at least one local or mounted storage destination.")
        }
        for service in fileServices {
            guard let index = configuration.services.firstIndex(where: { $0.id == service.id }) else { continue }
            guard let text = service.destination, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                warnings.append("\(service.name) needs a destination folder.")
                configuration.services[index].setupState = .needsAttention
                continue
            }
            let path = NSString(string: text).expandingTildeInPath
            if service.kind == .localStorage && !FileManager.default.fileExists(atPath: path) {
                do { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) }
                catch { warnings.append("\(service.name) could not create its destination folder.") }
            }
            if let problem = verifyWritableDestination(text) {
                configuration.services[index].setupState = .needsAttention
                warnings.append("\(service.name): \(problem)")
            } else {
                configuration.services[index].setupState = .operational
            }
        }
        configurationWarnings = warnings
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let value = configuration
        let url = configurationURL
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let data = try? JSONEncoder.pretty.encode(value) else { return }
            try? data.write(to: url, options: .atomic)
            self.persistSettingsBackup(value)
        }
    }

    private func persistSettingsBackup(_ value: AppConfiguration) {
        do {
            try FileManager.default.createDirectory(at: settingsBackupDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder.pretty.encode(SettingsExport(configuration: value))
            try data.write(to: settingsBackupDirectory.appending(path: "Camera-Zapper-Settings-Latest.json"), options: .atomic)
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
            try data.write(to: settingsBackupDirectory.appending(path: "Camera-Zapper-Settings-\(formatter.string(from: .now)).json"), options: .atomic)
        } catch {
            // The primary configuration save remains authoritative. Backup
            // failures are intentionally non-fatal and never expose secrets.
        }
    }

    private func persistPreImportSettingsBackup(_ value: AppConfiguration) throws {
        try FileManager.default.createDirectory(at: settingsBackupDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(SettingsExport(configuration: value))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "Camera-Zapper-Settings-Before-Import-\(formatter.string(from: .now)).json"
        try data.write(to: settingsBackupDirectory.appending(path: filename), options: .atomic)
    }

    private func scheduleDeviceSave() {
        deviceSaveTask?.cancel()
        let value = devices
        let url = deviceRegistryURL
        deviceSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let data = try? JSONEncoder.pretty.encode(value) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
