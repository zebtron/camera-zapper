import CryptoKit
import Foundation

enum MediaClassifier {
    static let photos: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff"]
    static let raw: Set<String> = ["arw", "raf", "cr2", "cr3", "nef", "nrw", "orf", "rw2", "dng", "gpr"]
    static let videos: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "mts", "m2ts", "3gp", "webm"]
    static let sidecars: Set<String> = ["xmp", "thm", "lrv", "aae"]

    static func kind(for url: URL) -> MediaKind? {
        let ext = url.pathExtension.lowercased()
        if photos.contains(ext) { return .photo }
        if raw.contains(ext) { return .raw }
        if videos.contains(ext) { return .video }
        if sidecars.contains(ext) { return .other }
        return nil
    }
}

enum FileHasher {
    static func sha256(url: URL, chunkSize: Int = 4 * 1_024 * 1_024) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let data = try handle.read(upToCount: chunkSize), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct LocalMediaScanner {
    func scan(root: URL, ingestFolders: [String]) throws -> ScanResult {
        var files: [DiscoveredMediaFile] = []
        var unknown: [URL] = []
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]
        for folder in ingestFolders {
            let folderURL = folder.hasPrefix("/") ? URL(fileURLWithPath: folder) : root.appending(path: folder)
            guard let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants, .skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: keys)
                guard values.isRegularFile == true else { continue }
                guard let kind = MediaClassifier.kind(for: url) else { unknown.append(url); continue }
                let size = Int64(values.fileSize ?? 0)
                let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
                files.append(.init(id: UUID(), sourceURL: url, relativePath: relative, filename: url.lastPathComponent, size: size, modifiedAt: values.contentModificationDate ?? .distantPast, kind: kind))
                total += size
            }
        }
        return .init(files: files, unknownFiles: unknown, totalBytes: total)
    }
}

enum AtomicFileTransfer {
    static func copyAndVerify(source: URL, destination: URL, expectedHash: String? = nil) throws -> String {
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = destination.deletingLastPathComponent().appending(path: ".\(destination.lastPathComponent).partial.\(UUID().uuidString)")
        defer { try? manager.removeItem(at: partial) }
        if manager.fileExists(atPath: destination.path) {
            let existingHash = try FileHasher.sha256(url: destination)
            if expectedHash == nil || existingHash == expectedHash { return existingHash }
            throw EngineError.hashMismatch(destination.lastPathComponent)
        }
        // Stream file data instead of using FileManager.copyItem. SMB servers
        // commonly reject macOS-only extended attributes (notably provenance),
        // causing copyItem to report a misleading destination permission error.
        guard manager.createFile(atPath: partial.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: partial.path])
        }
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: partial)
        do {
            while let data = try input.read(upToCount: 4 * 1_024 * 1_024), !data.isEmpty {
                try output.write(contentsOf: data)
            }
            try output.synchronize()
            try input.close()
            try output.close()
        } catch {
            try? input.close()
            try? output.close()
            throw error
        }
        let destinationHash = try FileHasher.sha256(url: partial)
        if let expectedHash, destinationHash != expectedHash { throw EngineError.hashMismatch(destination.lastPathComponent) }
        try manager.moveItem(at: partial, to: destination)
        if let modified = try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            try? manager.setAttributes([.modificationDate: modified], ofItemAtPath: destination.path)
        }
        return destinationHash
    }
}
