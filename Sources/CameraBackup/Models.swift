import Foundation

enum MediaKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case photo = "Photos"
    case raw = "RAW"
    case video = "Video"
    case other = "Other"
    var id: String { rawValue }
    var icon: String {
        switch self { case .photo: "photo"; case .raw: "camera.aperture"; case .video: "film"; case .other: "doc" }
    }
    var sampleName: String {
        switch self { case .photo: "IMG_8432.JPG"; case .raw: "IMG_8432.ARW"; case .video: "C0007.MOV"; case .other: "IMG_8432.XMP" }
    }
}

enum ServiceKind: String, Codable, CaseIterable {
    case localStorage = "Local Device Storage"
    case storage = "Storage"
    case s3 = "Amazon S3"
    case youtube = "YouTube"
    case googlePhotos = "Google Photos"
    case flickr = "Flickr"
    case amazonPhotos = "Amazon Photos"
    case iCloud = "iCloud Drive"
    case photos = "Apple Photos"
    case neofinder = "NeoFinder"
    case derivative = "Compatibility Video Copies"
}

enum ServiceSetupState: String, Codable, CaseIterable {
    case notSetUp
    case configuring
    case operational
    case needsAttention
}

struct ServiceConfiguration: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: ServiceKind
    var name: String
    var isEnabled: Bool
    var priority: Int
    var isRequiredForDeletion: Bool
    var detail: String
    var destination: String?
    var acceptedMedia: Set<MediaKind>
    var outputFormat: String?
    var transcodeEnabled: Bool
    var remoteLocation: String?
    var privacy: String?
    var setupState: ServiceSetupState? = nil

    static let defaults: [Self] = [
        .init(id: UUID(), kind: .localStorage, name: "Local Device Archive", isEnabled: true, priority: 0, isRequiredForDeletion: true, detail: "Verified safety copy on this Mac; retained while offline and until required destinations succeed", destination: "~/Pictures/Camera Zapper/Archive", acceptedMedia: Set(MediaKind.allCases), outputFormat: "Original", transcodeEnabled: false, remoteLocation: nil, privacy: nil, setupState: .operational),
        .init(id: UUID(), kind: .storage, name: "Primary NAS Archive", isEnabled: false, priority: 1, isRequiredForDeletion: false, detail: "Copy and SHA-256 verify archival files after you choose a mounted destination", destination: "/Volumes/NAS", acceptedMedia: Set(MediaKind.allCases), outputFormat: "Original", transcodeEnabled: false, remoteLocation: "smb://your-nas.local/Media", privacy: nil),
        .init(id: UUID(), kind: .youtube, name: "YouTube Video Backup", isEnabled: false, priority: 2, isRequiredForDeletion: false, detail: "Upload new videos privately to YouTube", destination: nil, acceptedMedia: [.video], outputFormat: "MP4", transcodeEnabled: true, remoteLocation: "Camera Zapper", privacy: "Private"),
        .init(id: UUID(), kind: .googlePhotos, name: "Google Photos", isEnabled: false, priority: 3, isRequiredForDeletion: false, detail: "Upload verified photos and videos to Google Photos", destination: nil, acceptedMedia: [.photo, .raw, .video], outputFormat: "Original", transcodeEnabled: false, remoteLocation: "Camera Zapper", privacy: "Private"),
        .init(id: UUID(), kind: .flickr, name: "Flickr", isEnabled: false, priority: 4, isRequiredForDeletion: false, detail: "Upload verified photos and videos directly to Flickr without Flickr Uploadr", destination: nil, acceptedMedia: [.photo, .video], outputFormat: "Original", transcodeEnabled: false, remoteLocation: "Camera Zapper", privacy: "Private"),
        .init(id: UUID(), kind: .photos, name: "Apple Photos", isEnabled: false, priority: 4, isRequiredForDeletion: false, detail: "Import compatible photos into Photos", destination: nil, acceptedMedia: [.photo], outputFormat: "Original", transcodeEnabled: false, remoteLocation: nil, privacy: nil),
        .init(id: UUID(), kind: .derivative, name: "Compatibility Video Copies", isEnabled: false, priority: 4, isRequiredForDeletion: false, detail: "Create easy-to-play MP4 copies for incompatible video while preserving the original", destination: "~/Movies/Camera Zapper/Compatibility Videos", acceptedMedia: [.video], outputFormat: "MP4", transcodeEnabled: true, remoteLocation: nil, privacy: nil),
        .init(id: UUID(), kind: .neofinder, name: "NeoFinder", isEnabled: false, priority: 5, isRequiredForDeletion: false, detail: "Catalog verified destination files", destination: nil, acceptedMedia: Set(MediaKind.allCases), outputFormat: nil, transcodeEnabled: false, remoteLocation: nil, privacy: nil)
    ]
}

struct DestinationRule: Identifiable, Codable, Equatable {
    var id: MediaKind { kind }
    var kind: MediaKind
    var enabled: Bool
    var root: String
    var pathTemplate: String

    func example(device: String = "Sony A7 IV", date: Date = Date()) -> String {
        let calendar = Calendar.current
        let year = String(calendar.component(.year, from: date))
        let month = String(format: "%02d", calendar.component(.month, from: date))
        let day = String(format: "%02d", calendar.component(.day, from: date))
        let relative = pathTemplate
            .replacingOccurrences(of: "{year}", with: year)
            .replacingOccurrences(of: "{month}", with: month)
            .replacingOccurrences(of: "{day}", with: day)
            .replacingOccurrences(of: "{device}", with: device.replacingOccurrences(of: " ", with: "_"))
            .replacingOccurrences(of: "{filename}", with: kind.sampleName)
        return URL(fileURLWithPath: root).appending(path: relative).path
    }

    static let defaults: [Self] = [
        .init(kind: .photo, enabled: true, root: "~/Pictures/Camera Zapper/Photos", pathTemplate: "{year}/{month}/{filename}"),
        .init(kind: .raw, enabled: true, root: "~/Pictures/Camera Zapper/RAW", pathTemplate: "{year}/{month}/{filename}"),
        .init(kind: .video, enabled: true, root: "~/Pictures/Camera Zapper/Video", pathTemplate: "{year}/{month}/Originals/{filename}"),
        .init(kind: .other, enabled: true, root: "~/Pictures/Camera Zapper/Extras", pathTemplate: "{year}/{month}/{device}/{filename}")
    ]
}

enum DeletionPolicy: String, Codable, CaseIterable, Identifiable {
    case ask = "Always ask"
    case automatic = "Delete verified originals automatically"
    case never = "Never delete originals"
    var id: String { rawValue }
}

enum NodePlatform: String, Codable, Hashable { case macOS = "macOS", android = "Android", windows = "Windows", linux = "Linux", iOS = "iOS" }
enum CoordinationRole: String, Codable, Hashable { case coordinator = "Coordinator", ingest = "Ingest Station", travel = "Travel Worker", mobile = "Mobile Source" }
enum CoordinationMode: String, Codable, CaseIterable, Identifiable { case standalone = "This Mac Only", coordinated = "Multiple Devices"; var id: String { rawValue } }

struct CoordinationNode: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var platform: NodePlatform
    var role: CoordinationRole
    var detail: String
    var isOnline: Bool
    var isPrimary: Bool
    var capabilities: [String]
    var lastSeen: Date
}

enum ConnectionPath: String, Codable, Hashable { case lan = "LAN", vpn = "VPN", offline = "Offline" }

struct ClientConnectionRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var clientName: String
    var platform: NodePlatform
    var address: String
    var path: ConnectionPath
    var isOnline: Bool
    var firstConnected: Date
    var lastConnected: Date
    var syncedSources: [String]
}

struct CoordinationConfiguration: Codable, Equatable {
    var enabled = false
    var mode: CoordinationMode = .standalone
    var coordinatorName = Host.current().localizedName ?? "This Mac"
    var coordinatorAddress = "https://this-mac.local:7443"
    var requireCoordinatorForDeletion = true
    var allowOfflineCaching = true
    var leaseMinutes = 30
    var writeNASReceipts = true
}

struct AppConfiguration: Codable, Equatable {
    var launchAtLogin = false
    var startAutomatically = true
    var notifications = true
    var deletionPolicy: DeletionPolicy = .ask
    var preserveUnknownFiles = true
    var safetyMarginPercent = 10.0
    var offlineCacheEnabled = true
    var offlineCacheDirectory = "~/Pictures/Camera Zapper/Offline Cache"
    var offlineCacheMaximumGB = 250.0
    var offlineCacheMinimumFreeGB = 25.0
    var retrySyncAutomatically = true
    var releaseCacheAfterVerification = true
    var cacheAllowsSourceDeletion = false
    var nasHost = "your-nas.local"
    var nasShare = "Media"
    var nasMountPath = "/Volumes/NAS"
    var nasUsesKeychain = true
    var mountAutomatically = true
    var coordination = CoordinationConfiguration()
    var services = ServiceConfiguration.defaults
    var destinations = DestinationRule.defaults
    // Optional for backward-compatible decoding of configurations written
    // before Video Processing became its own settings section.
    var transcodeIncompatibleVideos: Bool? = false
    var transcodeDestination: String? = "~/Movies/Camera Zapper/Compatibility Videos"
    var transcodePreset: String? = "PresetHEVCHighestQuality"
}

struct SettingsExport: Codable {
    let schemaVersion: Int
    let appVersion: String
    let exportedAt: Date
    let configuration: AppConfiguration

    init(configuration: AppConfiguration) {
        schemaVersion = 1
        appVersion = "1.348"
        exportedAt = .now
        self.configuration = configuration
    }
}

enum CacheSyncStatus: String {
    case available = "NAS available"
    case caching = "Caching locally"
    case queued = "Waiting for NAS"
    case syncing = "Syncing to NAS"
    case idle = "No queued files"
}

enum DeviceCategory: String, Codable, Hashable {
    case camera = "Camera"
    case actionCamera = "Action Camera"
    case androidPhone = "Android Phone"
}

enum AndroidConnectionMethod: String, Codable, CaseIterable, Identifiable {
    case automatic = "Automatic (recommended)"
    case mtp = "MTP (recommended)"
    case adbUSB = "ADB over USB"
    case adbWiFi = "ADB over Wi-Fi"
    var id: String { rawValue }
}

enum BackupStatus: String, Codable {
    case idle = "Ready"
    case scanning = "Scanning"
    case backingUp = "Backing Up"
    case verifying = "Verifying"
    case review = "Review Required"
    case failed = "Problem"
}

struct CameraDevice: Identifiable, Codable, Hashable {
    var id: UUID
    var displayName: String
    var model: String
    var volumeName: String
    var volumeUUID: String
    var isConnected: Bool
    var lastSeen: Date
    var filesWaiting: Int
    var manufacturer: String
    var releaseYear: Int?
    var sensorDescription: String
    var observedCardCapacitiesGB: [Int]
    var videoCapability: String
    var shootsRAW: Bool
    var rawFormats: [String]
    var videoFormats: [String]
    var customImagePath: String?
    var category: DeviceCategory
    var androidConnectionMethod: AndroidConnectionMethod?
    var sourceFolders: [String]
    var supportedCardTypes: [String]
    var recommendedCardSpeed: String
    var recommendedCardMakers: [String]
    var operatingSystem: String? = nil
    var connectionProvider: String? = nil
    var connectionDetail: String? = nil
    var usableStorageGiB: Int? = nil
    var usedStorageGiB: Int? = nil
    var freeStorageGiB: Int? = nil
    var detectedImageCount: Int? = nil
    var detectedVideoCount: Int? = nil
    var availableConnectionMethods: [String] = []
}

struct BackupSession: Identifiable, Codable, Hashable {
    var id: UUID
    var deviceID: UUID
    var deviceName: String
    var startedAt: Date
    var finishedAt: Date?
    var status: BackupStatus
    var filesFound: Int
    var filesVerified: Int
    var filesFailed: Int
    var bytesTransferred: Int64
    var imageCount: Int
    var videoCount: Int
    var audioCount: Int
    var outputFormats: [String]
    var transcodedCount: Int
}

struct ActivityEvent: Identifiable, Codable, Hashable {
    enum Severity: String, Codable, CaseIterable { case info = "Info", success = "Success", warning = "Warning", error = "Error" }
    var id: UUID
    var timestamp: Date
    var severity: Severity
    var message: String
}
