import Foundation

enum VideoTranscoder {
    static let alreadyCompatible: Set<String> = ["mp4", "mkv"]

    static func shouldTranscode(_ url: URL) -> Bool {
        !alreadyCompatible.contains(url.pathExtension.lowercased()) && MediaClassifier.videos.contains(url.pathExtension.lowercased())
    }

    static func transcodeToMP4(source: URL, destination: URL, preset: String = "PresetHEVCHighestQuality") async throws -> String {
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: destination.path) { return try FileHasher.sha256(url: destination) }
        let partial = destination.deletingLastPathComponent().appending(path: ".\(destination.deletingPathExtension().lastPathComponent).\(UUID().uuidString).partial.mp4")
        defer { try? manager.removeItem(at: partial) }
        let process = Process(); let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/avconvert")
        process.arguments = ["--source", source.path, "--preset", preset, "--output", partial.path, "--disableMetadataFilter"]
        process.standardError = errorPipe; process.standardOutput = Pipe()
        try process.run()
        while process.isRunning {
            if Task.isCancelled { process.terminate(); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(250))
        }
        guard process.terminationStatus == 0 else {
            let text = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw VideoTranscodeError.failed(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let hash = try FileHasher.sha256(url: partial)
        try manager.moveItem(at: partial, to: destination)
        return hash
    }
}

enum VideoTranscodeError: LocalizedError {
    case failed(String)
    var errorDescription: String? { switch self { case .failed(let detail): "Video conversion failed: \(detail.isEmpty ? "avconvert returned an error" : detail)" } }
}
