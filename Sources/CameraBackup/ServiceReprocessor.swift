import AppKit
import Foundation

enum FlickrUploadPolicy {
    static func sizeLimit(for kind: MediaKind) -> Int64 { kind == .video ? 990_000_000 : 195_000_000 }
    static func shouldBlockForSkippedOversize(serviceIsRequired: Bool, mediaIsAccepted: Bool) -> Bool {
        serviceIsRequired && mediaIsAccepted
    }
}

actor ServiceReprocessor {
    private let database: CameraZapperDatabase
    private let machineID: UUID
    private let googlePhotos: GooglePhotosClient
    private let flickr: FlickrClient

    init(database: CameraZapperDatabase, googlePhotos: GooglePhotosClient, flickr: FlickrClient) {
        self.database = database
        self.googlePhotos = googlePhotos
        self.flickr = flickr
        machineID = UserDefaults.standard.string(forKey: "machineID").flatMap(UUID.init(uuidString:)) ?? UUID()
    }

    func run(service: ServiceConfiguration, localService: ServiceConfiguration, progress: @escaping @Sendable (Int, Int, String) async -> Void) async throws {
        let sources = try database.fetchReceipts(destinationID: localService.id.uuidString)
        switch service.kind {
        case .storage: try await copyToStorage(sources, service: service, localService: localService, progress: progress)
        case .photos: try await importIntoPhotos(sources, service: service, progress: progress)
        case .googlePhotos: try await uploadToGooglePhotos(sources, service: service, progress: progress)
        case .flickr: try await uploadToFlickr(sources, service: service, progress: progress)
        case .youtube: try await uploadToYouTube(sources, service: service, progress: progress)
        case .neofinder: try await catalogWithNeoFinder(sources, service: service, localService: localService, progress: progress)
        default: throw ServiceReprocessError.unsupported(service.name)
        }
    }

    func transcodeCompatibilityCopies(configuration: AppConfiguration, localService: ServiceConfiguration, progress: @escaping @Sendable (Int, Int, String) async -> Void) async throws {
        let sources = try database.fetchReceipts(destinationID: localService.id.uuidString).filter { VideoTranscoder.shouldTranscode(URL(fileURLWithPath: $0.destinationPath)) }
        let root = URL(fileURLWithPath: NSString(string: configuration.transcodeDestination ?? "~/Movies/Zebtron Camera Zapper Compatibility Videos").expandingTildeInPath, isDirectory: true)
        for (index, source) in sources.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            if try database.hasVerifiedReceipt(hash: source.contentSHA256, size: source.byteSize, destinationID: "video-processing-mp4", artifactType: "transcoded-mp4") { continue }
            await progress(index, sources.count, "Transcoding \(source.filename) to MP4")
            let date = source.verifiedAt
            let destination = root.appending(path: "Imported Devices").appending(path: String(Calendar.current.component(.year, from: date))).appending(path: String(format: "%02d", Calendar.current.component(.month, from: date))).appending(path: URL(fileURLWithPath: source.filename).deletingPathExtension().lastPathComponent + ".mp4")
            let hash = try await VideoTranscoder.transcodeToMP4(source: URL(fileURLWithPath: source.destinationPath), destination: destination, preset: configuration.transcodePreset ?? "PresetHEVCHighestQuality")
            var receipt = derivedReceipt(from: source, service: .init(id: UUID(), kind: .derivative, name: "Video Processing", isEnabled: true, priority: 0, isRequiredForDeletion: false, detail: "", destination: root.path, acceptedMedia: [.video], outputFormat: "MP4", transcodeEnabled: true, remoteLocation: nil, privacy: nil), path: destination.path, hash: hash, artifact: "transcoded-mp4")
            receipt.destinationID = "video-processing-mp4"
            try database.insertReceipt(receipt)
        }
        await progress(sources.count, sources.count, sources.isEmpty ? "No incompatible videos need transcoding" : "Video compatibility catch-up complete")
    }

    private func catalogWithNeoFinder(_ sources: [TransferReceipt], service: ServiceConfiguration, localService: ServiceConfiguration, progress: @escaping @Sendable (Int, Int, String) async -> Void) async throws {
        guard FileManager.default.fileExists(atPath: "/Applications/NeoFinder.app") else { throw ServiceReprocessError.missingNeoFinder }
        guard let rootText = localService.destination else { throw ServiceReprocessError.destinationMissing }
        let root = NSString(string: rootText).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: root) else { throw ServiceReprocessError.destinationUnavailable(root) }
        await progress(0, sources.count, "NeoFinder is cataloging the verified local archive")
        let escaped = root.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "NeoFinder"
            activate
            catalog POSIX file "\(escaped)" eject afterwards false canUpdate true canDuplicate false canQuit false
            repeat while cataloging > 0
                delay 1
            end repeat
        end tell
        """
        var error: NSDictionary?
        guard NSAppleScript(source: script)?.executeAndReturnError(&error) != nil else { throw ServiceReprocessError.automation(error?.description ?? "NeoFinder rejected the catalog request") }
        for (index, source) in sources.enumerated() {
            if !(try database.hasVerifiedReceipt(hash: source.contentSHA256, size: source.byteSize, destinationID: service.id.uuidString, artifactType: "neofinder-catalog")) {
                try database.insertReceipt(derivedReceipt(from: source, service: service, path: "neofinder://catalog/\(source.filename)", hash: source.contentSHA256, artifact: "neofinder-catalog"))
            }
            if index.isMultiple(of: 100) { await progress(index, sources.count, "Recording NeoFinder catalog receipts") }
        }
        await progress(sources.count, sources.count, "NeoFinder catalog catch-up complete")
    }

    private func uploadToGooglePhotos(_ sources: [TransferReceipt], service: ServiceConfiguration, progress: @escaping @Sendable (Int, Int, String) async -> Void) async throws {
        let supported = sources.filter { ["jpg", "jpeg", "heic", "png", "gif", "tif", "tiff", "dng", "mov", "mp4", "m4v"].contains(URL(fileURLWithPath: $0.destinationPath).pathExtension.lowercased()) }
        let sessions = Dictionary(uniqueKeysWithValues: (try database.fetchSessions()).map { ($0.id, $0) })
        var completed = 0
        for (sessionID, sessionSources) in Dictionary(grouping: supported, by: \.sessionID) {
            let pending = try sessionSources.filter { !(try database.hasVerifiedReceipt(hash: $0.contentSHA256, size: $0.byteSize, destinationID: service.id.uuidString, artifactType: "google-photos")) }
            completed += sessionSources.count - pending.count
            guard !pending.isEmpty else { continue }
            let session = sessions[sessionID]
            let title = "\(session?.deviceName ?? "Camera") · \((session?.startedAt ?? pending[0].verifiedAt).formatted(.dateTime.year().month().day().hour().minute()))"
            let albumID: String
            if let existing = try database.serviceContainer(serviceID: service.id.uuidString, sessionID: sessionID) { albumID = existing }
            else {
                await progress(completed, supported.count, "Creating Google Photos album: \(title)")
                albumID = try await googlePhotos.createAlbum(title: title)
                try database.saveServiceContainer(serviceID: service.id.uuidString, sessionID: sessionID, remoteID: albumID, displayName: title)
            }
            for source in pending {
                if Task.isCancelled { throw CancellationError() }
                await progress(completed, supported.count, "Uploading to \(title): \(source.filename)")
                let productURL = try await googlePhotos.upload(file: URL(fileURLWithPath: source.destinationPath), filename: source.filename, albumID: albumID)
                try database.insertReceipt(derivedReceipt(from: source, service: service, path: productURL, hash: source.contentSHA256, artifact: "google-photos"))
                completed += 1
            }
        }
        await progress(supported.count, supported.count, "Google Photos catch-up complete")
    }

    private func uploadToFlickr(_ sources: [TransferReceipt], service: ServiceConfiguration, progress: @escaping @Sendable (Int, Int, String) async -> Void) async throws {
        let supportedExtensions = ["jpg", "jpeg", "png", "gif", "tif", "tiff", "bmp", "mov", "mp4", "m4v", "avi", "wmv", "mpeg", "mpg", "3gp", "m2ts", "ogg", "ogv"]
        let supported = sources.filter { source in
            let url = URL(fileURLWithPath: source.destinationPath)
            guard supportedExtensions.contains(url.pathExtension.lowercased()), let kind = MediaClassifier.kind(for: url) else { return false }
            return service.acceptedMedia.contains(kind)
        }
        let previouslyCompleted = supported.count - (try supported.filter { !(try database.hasVerifiedReceipt(hash: $0.contentSHA256, size: $0.byteSize, destinationID: service.id.uuidString, artifactType: "flickr")) }).count
        var completed = previouslyCompleted
        var uploaded = 0
        var alreadyPresent = 0
        var unsupported: [String] = []
        for source in supported {
            if Task.isCancelled { throw CancellationError() }
            if try database.hasVerifiedReceipt(hash: source.contentSHA256, size: source.byteSize, destinationID: service.id.uuidString, artifactType: "flickr") { continue }
            let url = URL(fileURLWithPath: source.destinationPath)
            let kind = MediaClassifier.kind(for: url) ?? .other
            // Flickr documents 1 GB/video and 200 MB/photo. Leave room for the
            // multipart request envelope so nginx never receives an oversized body.
            let limit = FlickrUploadPolicy.sizeLimit(for: kind)
            if source.byteSize > limit {
                let reason = "Flickr skipped \(source.filename) — \(ByteCountFormatter.string(fromByteCount: source.byteSize, countStyle: .file)) exceeds Flickr's \(kind == .video ? "1 GB video" : "200 MB photo") limit"
                unsupported.append(source.filename)
                try database.insertEvent(.init(id: UUID(), timestamp: .now, severity: .warning, message: reason), sessionID: source.sessionID)
                completed += 1
                await progress(completed, supported.count, reason)
                continue
            }
            await progress(completed, supported.count, "Uploading to Flickr: \(source.filename)")
            let result: FlickrUploadResult
            do {
                result = try await flickr.uploadPrivate(file: url, filename: source.filename)
            } catch FlickrError.entityTooLarge {
                let reason = "Flickr skipped \(source.filename) — Flickr rejected the request as too large"
                unsupported.append(source.filename)
                try database.insertEvent(.init(id: UUID(), timestamp: .now, severity: .warning, message: reason), sessionID: source.sessionID)
                completed += 1
                await progress(completed, supported.count, reason)
                continue
            }
            let productURL: String
            switch result {
            case .uploaded(let url):
                uploaded += 1
                productURL = url
            case .alreadyPresent(let url):
                alreadyPresent += 1
                productURL = url ?? "flickr://duplicate/\(source.contentSHA256)"
                let message = "Already on Flickr — skipped duplicate: \(source.filename)"
                try database.insertEvent(.init(id: UUID(), timestamp: .now, severity: .info, message: message), sessionID: source.sessionID)
                await progress(completed + 1, supported.count, "\(message) · \(uploaded) uploaded · \(alreadyPresent) already there")
            }
            try database.insertReceipt(derivedReceipt(from: source, service: service, path: productURL, hash: source.contentSHA256, artifact: "flickr"))
            completed += 1
        }
        if !unsupported.isEmpty && FlickrUploadPolicy.shouldBlockForSkippedOversize(serviceIsRequired: service.isRequiredForDeletion, mediaIsAccepted: true) {
            throw ServiceReprocessError.providerLimit("Flickr processed eligible files but could not back up \(unsupported.count) oversized item\(unsupported.count == 1 ? "" : "s"): \(unsupported.joined(separator: ", ")). Disable Video for Flickr or make Flickr optional before deleting those originals; YouTube and storage receipts remain independent.")
        }
        let skipped = unsupported.isEmpty ? "" : " · \(unsupported.count) oversized skipped"
        await progress(supported.count, supported.count, "Flickr complete · \(uploaded) uploaded · \(alreadyPresent) already there · \(previouslyCompleted) previously processed\(skipped)")
    }

    private func uploadToYouTube(_ sources: [TransferReceipt], service: ServiceConfiguration, progress: @escaping @Sendable (Int, Int, String) async -> Void) async throws {
        let supported = sources.filter { ["mov", "mp4", "m4v", "mkv", "avi"].contains(URL(fileURLWithPath: $0.destinationPath).pathExtension.lowercased()) }
        var completed = supported.count - (try supported.filter { !(try database.hasVerifiedReceipt(hash: $0.contentSHA256, size: $0.byteSize, destinationID: service.id.uuidString, artifactType: "youtube-private")) }).count
        for source in supported {
            if Task.isCancelled { throw CancellationError() }
            if try database.hasVerifiedReceipt(hash: source.contentSHA256, size: source.byteSize, destinationID: service.id.uuidString, artifactType: "youtube-private") { continue }
            await progress(completed, supported.count, "Uploading privately to YouTube: \(source.filename)")
            let title = URL(fileURLWithPath: source.filename).deletingPathExtension().lastPathComponent
            let productURL = try await googlePhotos.uploadToYouTube(file: URL(fileURLWithPath: source.destinationPath), title: title)
            try database.insertReceipt(derivedReceipt(from: source, service: service, path: productURL, hash: source.contentSHA256, artifact: "youtube-private"))
            completed += 1
        }
        await progress(supported.count, supported.count, "YouTube private backup complete")
    }

    private func copyToStorage(_ sources: [TransferReceipt], service: ServiceConfiguration, localService: ServiceConfiguration, progress: @escaping @Sendable (Int, Int, String) async -> Void) async throws {
        guard let rootText = service.destination else { throw ServiceReprocessError.destinationMissing }
        let root = URL(fileURLWithPath: NSString(string: rootText).expandingTildeInPath, isDirectory: true)
        guard FileManager.default.isWritableFile(atPath: root.path) else { throw ServiceReprocessError.destinationUnavailable(root.path) }
        let localRoot = URL(fileURLWithPath: NSString(string: localService.destination ?? "").expandingTildeInPath, isDirectory: true)
        for (index, source) in sources.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            if try database.hasVerifiedReceipt(hash: source.contentSHA256, size: source.byteSize, destinationID: service.id.uuidString) { continue }
            await progress(index, sources.count, "Copying to \(service.name): \(source.filename)")
            let sourceURL = URL(fileURLWithPath: source.destinationPath)
            let relative = sourceURL.path.hasPrefix(localRoot.path + "/") ? String(sourceURL.path.dropFirst(localRoot.path.count + 1)) : source.filename
            let destination = root.appending(path: relative)
            let hash = try AtomicFileTransfer.copyAndVerify(source: sourceURL, destination: destination, expectedHash: source.contentSHA256)
            try database.insertReceipt(derivedReceipt(from: source, service: service, path: destination.path, hash: hash, artifact: "original"))
        }
        await progress(sources.count, sources.count, "\(service.name) catch-up complete")
    }

    private func importIntoPhotos(_ sources: [TransferReceipt], service: ServiceConfiguration, progress: @escaping @Sendable (Int, Int, String) async -> Void) async throws {
        let supported = sources.filter { ["jpg", "jpeg", "heic", "png", "gif", "tif", "tiff", "dng", "mov", "mp4", "m4v"].contains(URL(fileURLWithPath: $0.destinationPath).pathExtension.lowercased()) }
        for (index, source) in supported.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            if try database.hasVerifiedReceipt(hash: source.contentSHA256, size: source.byteSize, destinationID: service.id.uuidString, artifactType: "photos-import") { continue }
            await progress(index, supported.count, "Importing into Apple Photos: \(source.filename)")
            let escaped = source.destinationPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = "tell application \"Photos\" to import {POSIX file \"\(escaped)\"} skip check duplicates false"
            var error: NSDictionary?
            guard NSAppleScript(source: script)?.executeAndReturnError(&error) != nil else { throw ServiceReprocessError.automation(error?.description ?? "Photos rejected the import") }
            try database.insertReceipt(derivedReceipt(from: source, service: service, path: "photos://\(source.filename)", hash: source.contentSHA256, artifact: "photos-import"))
        }
        await progress(supported.count, supported.count, "Apple Photos catch-up complete")
    }

    private func derivedReceipt(from source: TransferReceipt, service: ServiceConfiguration, path: String, hash: String, artifact: String) -> TransferReceipt {
        .init(operationID: UUID(), machineID: machineID, sessionID: source.sessionID, sourceDeviceID: source.sourceDeviceID, sourceRelativePath: source.sourceRelativePath, filename: source.filename, contentSHA256: source.contentSHA256, byteSize: source.byteSize, destinationID: service.id.uuidString, destinationPath: path, destinationSHA256: hash, artifactType: artifact, verifiedAt: .now)
    }
}

enum ServiceReprocessError: LocalizedError {
    case missingNeoFinder, destinationMissing, destinationUnavailable(String), unsupported(String), automation(String), providerLimit(String)
    var errorDescription: String? {
        switch self {
        case .missingNeoFinder: "NeoFinder is not installed in /Applications. Install it before catalog catch-up can run."
        case .destinationMissing: "The service destination is not configured."
        case .destinationUnavailable(let path): "The destination is not mounted or writable: \(path)"
        case .unsupported(let name): "The \(name) adapter is not operational yet."
        case .automation(let message): "Apple Photos automation failed: \(message)"
        case .providerLimit(let message): message
        }
    }
}
