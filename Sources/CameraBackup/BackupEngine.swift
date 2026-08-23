import Foundation

struct BackupRunResult: Sendable {
    var session: BackupSession
    var events: [ActivityEvent]
}

actor BackupEngine {
    private let database: CameraZapperDatabase
    private let adb: ADBAdapter?
    private let machineID: UUID
    private let stagingRoot: URL

    init(database: CameraZapperDatabase, adb: ADBAdapter?, applicationSupport: URL) {
        self.database = database
        self.adb = adb
        self.stagingRoot = applicationSupport.appending(path: "Staging", directoryHint: .isDirectory)
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "machineID"), let id = UUID(uuidString: value) { machineID = id }
        else { let id = UUID(); machineID = id; defaults.set(id.uuidString, forKey: "machineID") }
    }

    func discoverAndroid() async throws -> [AndroidDeviceSnapshot] {
        guard let adb else { return [] }
        return try await adb.discover()
    }

    func scanAndroid(serial: String, folders: [String], progress: (@Sendable (String) -> Void)? = nil) async throws -> [RemoteAndroidFile] {
        guard let adb else { throw EngineError.sourceUnavailable("ADB is not installed") }
        return try await adb.scan(serial: serial, folders: folders, progress: progress)
    }

    func verifyAndDeleteAndroid(device: CameraDevice, configuration: AppConfiguration, progress: @escaping @Sendable (EngineProgress) async -> Void) async throws -> Int {
        guard let adb else { throw EngineError.sourceUnavailable("ADB is not installed") }
        // Compatibility copies are optional processing artifacts, not backup
        // destinations. Legacy configurations may still contain a hidden
        // derivative service marked required; it must never gate deletion.
        let required = configuration.services.filter { $0.isEnabled && $0.isRequiredForDeletion && $0.kind != .derivative }
        guard !required.isEmpty else { throw EngineError.deletionBlocked("No services are marked as required") }
        let recordedFiles = try database.verifiedSourceFiles(deviceID: device.id)
        guard !recordedFiles.isEmpty else { throw EngineError.deletionBlocked("No verified source files remain for this device") }
        let startedAt = Date()

        // Reconcile an interrupted prior deletion. Files successfully removed
        // before a transport failure must not block or repeat the resumed run.
        await progress(.init(status: .verifying, completedFiles: 0, totalFiles: recordedFiles.count, currentFile: nil, fraction: 0, message: "Reconciling files still present on the source", phase: "Deletion preflight", startedAt: startedAt))
        let presentPaths = Set(try await adb.scan(serial: device.volumeUUID, folders: device.sourceFolders).map(\.path))
        for missing in recordedFiles where !presentPaths.contains(missing.sourcePath) {
            try database.markSourceDeleted(deviceID: device.id, sourcePath: missing.sourcePath)
        }
        let files = recordedFiles.filter { presentPaths.contains($0.sourcePath) }
        guard !files.isEmpty else {
            await progress(.init(status: .idle, completedFiles: 0, totalFiles: 0, currentFile: nil, fraction: 1, message: "No verified originals remain on this device", phase: "Deletion complete", startedAt: startedAt))
            return 0
        }

        // Two phases by design: every check passes before the first destructive call.
        for (index, file) in files.enumerated() {
            guard let expectedHash = file.sha256 else { throw EngineError.deletionBlocked("Missing source hash for \(file.filename)") }
            await progress(.init(status: .verifying, completedFiles: index, totalFiles: files.count, currentFile: file.filename, fraction: Double(index) / Double(files.count), message: "Rechecking source and required destinations", phase: "Deletion preflight", startedAt: startedAt))
            let currentHash = try await adb.sourceSHA256(serial: device.volumeUUID, path: file.sourcePath)
            guard currentHash == expectedHash else { throw EngineError.deletionBlocked("Source changed since backup: \(file.filename)") }
            for service in required where service.acceptedMedia.contains(file.kind) {
                guard let receipt = try database.verifiedReceipt(hash: expectedHash, size: file.size, destinationID: service.id.uuidString, artifactType: receiptArtifact(for: service.kind)) else {
                    throw EngineError.deletionBlocked("\(service.name) has no verified receipt for \(file.filename)")
                }
                if service.kind == .localStorage || service.kind == .storage {
                    let destination = URL(fileURLWithPath: receipt.destinationPath)
                    guard try Self.archivedCopyIsVerified(destination: destination, expectedSize: file.size, expectedHash: expectedHash) else {
                        throw EngineError.deletionBlocked("\(service.name) failed on-disk verification for \(file.filename)")
                    }
                }
            }
        }

        for (index, file) in files.enumerated() {
            await progress(.init(status: .verifying, completedFiles: index, totalFiles: files.count, currentFile: file.filename, fraction: Double(index) / Double(files.count), message: "All required checks passed; deleting source file", phase: "Deleting verified originals", startedAt: startedAt))
            try await adb.deleteVerifiedSource(serial: device.volumeUUID, remotePath: file.sourcePath)
            try database.markSourceDeleted(deviceID: device.id, sourcePath: file.sourcePath)
        }
        await progress(.init(status: .idle, completedFiles: files.count, totalFiles: files.count, currentFile: nil, fraction: 1, message: "Deleted \(files.count) originals after all required checks passed", phase: "Deletion complete", startedAt: startedAt))
        return files.count
    }

    private func receiptArtifact(for kind: ServiceKind) -> String {
        switch kind { case .googlePhotos: "google-photos"; case .youtube: "youtube-private"; case .flickr: "flickr"; case .photos: "photos-import"; case .neofinder: "neofinder-catalog"; default: "original" }
    }

    /// Shared by deletion preflight and tests: a source may be deleted only
    /// when the durable archived file is regular, byte-identical in size, and
    /// has the expected SHA-256 content hash.
    nonisolated static func archivedCopyIsVerified(destination: URL, expectedSize: Int64, expectedHash: String) throws -> Bool {
        let values = try destination.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, Int64(values.fileSize ?? -1) == expectedSize else { return false }
        return try FileHasher.sha256(url: destination) == expectedHash
    }

    func backupAndroid(device: CameraDevice,
                       serial: String,
                       folders: [String],
                       configuration: AppConfiguration,
                       progress: @escaping @Sendable (EngineProgress) async -> Void) async throws -> BackupRunResult {
        guard let adb else { throw EngineError.sourceUnavailable("ADB is not installed") }
        let localService = configuration.services.first(where: { $0.kind == .localStorage && $0.isEnabled })
        guard let localService, let destinationText = localService.destination else { throw EngineError.destinationUnavailable("Local Device Archive is not configured") }
        let destinationRoot = URL(fileURLWithPath: NSString(string: destinationText).expandingTildeInPath, isDirectory: true)
        try validateDestination(destinationRoot)
        try database.upsertDevice(device, sourcePath: "adb://\(serial)")

        let startedAt = Date()
        await progress(.init(status: .scanning, completedFiles: 0, totalFiles: 0, currentFile: nil, fraction: 0, message: "Scanning Android media folders", phase: "Scanning", startedAt: startedAt))
        let remoteFiles = try await adb.scan(serial: serial, folders: folders) { message in
            Task { await progress(.init(status: .scanning, completedFiles: 0, totalFiles: 0, currentFile: nil, fraction: 0, message: message, phase: "Scanning", startedAt: startedAt)) }
        }
        let totalBytes = remoteFiles.reduce(Int64(0)) { $0 + $1.size }
        var completedBytes: Int64 = 0
        var skippedFiles = 0
        var session = BackupSession(id: UUID(), deviceID: device.id, deviceName: device.displayName, startedAt: .now, finishedAt: nil, status: .backingUp, filesFound: remoteFiles.count, filesVerified: 0, filesFailed: 0, bytesTransferred: 0, imageCount: remoteFiles.filter { $0.kind == .photo || $0.kind == .raw }.count, videoCount: remoteFiles.filter { $0.kind == .video }.count, audioCount: 0, outputFormats: Array(Set(remoteFiles.map { URL(fileURLWithPath: $0.filename).pathExtension.uppercased() })).sorted(), transcodedCount: 0)
        try database.createSession(session)
        var events: [ActivityEvent] = []
        try record("Found \(remoteFiles.count) supported media files on \(device.displayName)", severity: .info, sessionID: session.id, into: &events)

        for (index, remote) in remoteFiles.enumerated() {
            if Task.isCancelled { throw EngineError.cancelled }
            let fraction = remoteFiles.isEmpty ? 1 : Double(index) / Double(remoteFiles.count)
            await progress(.init(status: .backingUp, completedFiles: session.filesVerified, totalFiles: remoteFiles.count, currentFile: remote.filename, fraction: fraction, message: "Calculating the source SHA-256 on the phone", phase: "Hashing source", completedBytes: completedBytes, totalBytes: totalBytes, skippedFiles: skippedFiles, failedFiles: session.filesFailed, startedAt: startedAt))
            var fileRecord = PersistedFileRecord(id: remote.id, sessionID: session.id, sourcePath: remote.path, relativePath: remote.relativePath, filename: remote.filename, size: remote.size, modifiedAt: remote.modifiedAt, kind: remote.kind, sha256: nil, destinationPath: nil, destinationSHA256: nil, state: .discovered, errorMessage: nil)
            try database.insertFile(fileRecord)
            do {
                try database.updateFile(id: remote.id, state: .hashing)
                let sourceHash = try await adb.sourceSHA256(serial: serial, path: remote.path)
                let destinationID = localService.id.uuidString
                if try database.hasVerifiedReceipt(hash: sourceHash, size: remote.size, destinationID: destinationID) {
                    try database.updateFile(id: remote.id, state: .verified, sha256: sourceHash)
                    session.filesVerified += 1
                    skippedFiles += 1
                    completedBytes += remote.size
                    try record("Skipped \(remote.filename): verified receipt already exists", severity: .success, sessionID: session.id, into: &events)
                    try database.updateSession(session)
                    await progress(.init(status: .backingUp, completedFiles: session.filesVerified, totalFiles: remoteFiles.count, currentFile: remote.filename, fraction: totalBytes == 0 ? 1 : Double(completedBytes) / Double(totalBytes), message: "Already verified — skipped safely", phase: "Deduplicating", completedBytes: completedBytes, totalBytes: totalBytes, skippedFiles: skippedFiles, failedFiles: session.filesFailed, startedAt: startedAt))
                    continue
                }

                let staged = stagingRoot.appending(path: session.id.uuidString).appending(path: remote.id.uuidString + ".partial")
                try? FileManager.default.removeItem(at: staged)
                try database.updateFile(id: remote.id, state: .copying, sha256: sourceHash)
                await progress(.init(status: .backingUp, completedFiles: session.filesVerified, totalFiles: remoteFiles.count, currentFile: remote.filename, fraction: totalBytes == 0 ? fraction : Double(completedBytes) / Double(totalBytes), message: "Copying from phone into interruption-safe staging", phase: "Copying", completedBytes: completedBytes, totalBytes: totalBytes, skippedFiles: skippedFiles, failedFiles: session.filesFailed, startedAt: startedAt))
                try await adb.pull(serial: serial, remotePath: remote.path, localURL: staged)
                await progress(.init(status: .backingUp, completedFiles: session.filesVerified, totalFiles: remoteFiles.count, currentFile: remote.filename, fraction: totalBytes == 0 ? fraction : Double(completedBytes) / Double(totalBytes), message: "Comparing phone, staging, and archive hashes", phase: "Verifying SHA-256", completedBytes: completedBytes, totalBytes: totalBytes, skippedFiles: skippedFiles, failedFiles: session.filesFailed, startedAt: startedAt))
                let stagedHash = try FileHasher.sha256(url: staged)
                guard stagedHash == sourceHash else { throw EngineError.hashMismatch(remote.filename) }

                let finalURL = destinationURL(root: destinationRoot, device: device, file: remote)
                let verifiedHash = try AtomicFileTransfer.copyAndVerify(source: staged, destination: finalURL, expectedHash: sourceHash)
                try? FileManager.default.removeItem(at: staged)
                guard verifiedHash == sourceHash else { throw EngineError.hashMismatch(remote.filename) }
                let receipt = TransferReceipt(operationID: UUID(), machineID: machineID, sessionID: session.id, sourceDeviceID: device.id, sourceRelativePath: remote.relativePath, filename: remote.filename, contentSHA256: sourceHash, byteSize: remote.size, destinationID: destinationID, destinationPath: finalURL.path, destinationSHA256: verifiedHash, artifactType: "original", verifiedAt: .now)
                try database.insertReceipt(receipt)
                try database.updateFile(id: remote.id, state: .verified, sha256: sourceHash, destination: finalURL.path, destinationSHA256: verifiedHash)
                try writeReceipt(receipt, destinationRoot: destinationRoot)
                session.filesVerified += 1
                session.bytesTransferred += remote.size
                completedBytes += remote.size
                try record("Verified \(remote.filename)", severity: .success, sessionID: session.id, into: &events)
                if configuration.transcodeIncompatibleVideos ?? false,
                   remote.kind == .video,
                   VideoTranscoder.shouldTranscode(finalURL) {
                    do {
                        await progress(.init(status: .backingUp, completedFiles: session.filesVerified, totalFiles: remoteFiles.count, currentFile: remote.filename, fraction: totalBytes == 0 ? fraction : Double(completedBytes) / Double(totalBytes), message: "Creating optional MP4 compatibility copy; original is preserved", phase: "Transcoding video", completedBytes: completedBytes, totalBytes: totalBytes, skippedFiles: skippedFiles, failedFiles: session.filesFailed, startedAt: startedAt))
                        let rootText = configuration.transcodeDestination ?? "~/Movies/Zebtron Camera Zapper Compatibility Videos"
                        let root = URL(fileURLWithPath: NSString(string: rootText).expandingTildeInPath, isDirectory: true)
                        let derivativeURL = root.appending(path: sanitize(device.displayName)).appending(path: String(Calendar.current.component(.year, from: remote.modifiedAt))).appending(path: String(format: "%02d", Calendar.current.component(.month, from: remote.modifiedAt))).appending(path: finalURL.deletingPathExtension().lastPathComponent + ".mp4")
                        let derivativeID = "video-processing-mp4"
                        if !(try database.hasVerifiedReceipt(hash: sourceHash, size: remote.size, destinationID: derivativeID, artifactType: "transcoded-mp4")) {
                            let derivativeHash = try await VideoTranscoder.transcodeToMP4(source: finalURL, destination: derivativeURL, preset: configuration.transcodePreset ?? "PresetHEVCHighestQuality")
                            let derivativeReceipt = TransferReceipt(operationID: UUID(), machineID: machineID, sessionID: session.id, sourceDeviceID: device.id, sourceRelativePath: remote.relativePath, filename: derivativeURL.lastPathComponent, contentSHA256: sourceHash, byteSize: remote.size, destinationID: derivativeID, destinationPath: derivativeURL.path, destinationSHA256: derivativeHash, artifactType: "transcoded-mp4", verifiedAt: .now)
                            try database.insertReceipt(derivativeReceipt)
                            session.transcodedCount += 1
                            try record("Created MP4 compatibility copy for \(remote.filename)", severity: .success, sessionID: session.id, into: &events)
                        }
                    } catch {
                        try? record("Optional video conversion failed for \(remote.filename): \(error.localizedDescription). Original remains verified.", severity: .warning, sessionID: session.id, into: &events)
                    }
                }
            } catch {
                fileRecord.state = .failed
                try? database.updateFile(id: remote.id, state: .failed, error: error.localizedDescription)
                session.filesFailed += 1
                try? record("Failed \(remote.filename): \(error.localizedDescription)", severity: .error, sessionID: session.id, into: &events)
            }
            try database.updateSession(session)
        }
        session.finishedAt = .now
        session.status = session.filesFailed == 0 ? .review : .failed
        try database.updateSession(session)
        await progress(.init(status: session.status, completedFiles: session.filesVerified, totalFiles: session.filesFound, currentFile: nil, fraction: 1, message: session.filesFailed == 0 ? "All files copied and SHA-256 verified" : "Backup finished with \(session.filesFailed) failures", phase: session.filesFailed == 0 ? "Complete" : "Needs attention", completedBytes: completedBytes, totalBytes: totalBytes, skippedFiles: skippedFiles, failedFiles: session.filesFailed, startedAt: startedAt))
        return .init(session: session, events: events)
    }

    private func destinationURL(root: URL, device: CameraDevice, file: RemoteAndroidFile) -> URL {
        let date = file.modifiedAt == .distantPast ? Date() : file.modifiedAt
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        let year = String(components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let deviceName = sanitize(device.displayName)
        let kindFolder: String = switch file.kind { case .photo: "Photos"; case .raw: "RAW"; case .video: "Video/Originals"; case .other: "Other" }
        return root.appending(path: deviceName).appending(path: kindFolder).appending(path: year).appending(path: month).appending(path: file.filename)
    }

    private func validateDestination(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let probe = url.appending(path: ".camera-zapper-write-test-\(UUID().uuidString)")
        do { try Data().write(to: probe); try FileManager.default.removeItem(at: probe) }
        catch { throw EngineError.destinationUnavailable(url.path) }
    }

    private func writeReceipt(_ receipt: TransferReceipt, destinationRoot: URL) throws {
        let prefix = String(receipt.contentSHA256.prefix(2))
        let folder = destinationRoot.appending(path: ".ZebtronCameraZapper/receipts/\(prefix)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder.receipt.encode(receipt)
        try data.write(to: folder.appending(path: receipt.operationID.uuidString + ".json"), options: .atomic)
    }

    private func record(_ message: String, severity: ActivityEvent.Severity, sessionID: UUID, into events: inout [ActivityEvent]) throws {
        let event = ActivityEvent(id: UUID(), timestamp: .now, severity: severity, message: message)
        try database.insertEvent(event, sessionID: sessionID)
        events.insert(event, at: 0)
    }

    private func sanitize(_ value: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        return value.components(separatedBy: disallowed).filter { !$0.isEmpty }.joined(separator: "_")
    }
}

extension JSONEncoder {
    static var receipt: JSONEncoder { let value = JSONEncoder(); value.outputFormatting = [.prettyPrinted, .sortedKeys]; value.dateEncodingStrategy = .iso8601; return value }
}
