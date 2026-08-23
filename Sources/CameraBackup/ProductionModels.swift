import Foundation

enum FileTransferState: String, Codable, Sendable {
    case discovered
    case hashing
    case copying
    case copied
    case verified
    case cached
    case failed
    case safeToDelete
    case deleted
}

struct DiscoveredMediaFile: Identifiable, Hashable, Sendable {
    var id: UUID
    var sourceURL: URL
    var relativePath: String
    var filename: String
    var size: Int64
    var modifiedAt: Date
    var kind: MediaKind
}

struct PersistedFileRecord: Identifiable, Sendable {
    var id: UUID
    var sessionID: UUID
    var sourcePath: String
    var relativePath: String
    var filename: String
    var size: Int64
    var modifiedAt: Date
    var kind: MediaKind
    var sha256: String?
    var destinationPath: String?
    var destinationSHA256: String?
    var state: FileTransferState
    var errorMessage: String?
}

struct TransferReceipt: Codable, Sendable {
    var operationID: UUID
    var machineID: UUID
    var sessionID: UUID
    var sourceDeviceID: UUID
    var sourceRelativePath: String
    var filename: String
    var contentSHA256: String
    var byteSize: Int64
    var destinationID: String
    var destinationPath: String
    var destinationSHA256: String
    var artifactType: String
    var verifiedAt: Date
}

struct ScanResult: Sendable {
    var files: [DiscoveredMediaFile]
    var unknownFiles: [URL]
    var totalBytes: Int64
}

struct EngineProgress: Sendable {
    var status: BackupStatus
    var completedFiles: Int
    var totalFiles: Int
    var currentFile: String?
    var fraction: Double
    var message: String
    var phase: String = "Preparing"
    var completedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var skippedFiles: Int = 0
    var failedFiles: Int = 0
    var startedAt: Date = .now
}

enum EngineError: LocalizedError {
    case sourceUnavailable(String)
    case destinationUnavailable(String)
    case insufficientSpace(required: Int64, available: Int64)
    case hashMismatch(String)
    case cancelled
    case deletionBlocked(String)

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable(let path): "Source is unavailable: \(path)"
        case .destinationUnavailable(let path): "Destination is unavailable or not writable: \(path)"
        case .insufficientSpace(let required, let available): "Insufficient space: need \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)), have \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))"
        case .hashMismatch(let name): "SHA-256 verification failed for \(name)"
        case .cancelled: "Backup was cancelled"
        case .deletionBlocked(let reason): "Deletion blocked: \(reason). Nothing was deleted."
        }
    }
}
