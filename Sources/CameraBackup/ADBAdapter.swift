import Foundation

struct AndroidDeviceSnapshot: Sendable {
    var serial: String
    var manufacturer: String
    var model: String
    var product: String
    var androidVersion: String
    var apiLevel: String
    var connection: String
    var isAuthorized: Bool
}

struct RemoteAndroidFile: Identifiable, Sendable {
    var id = UUID()
    var path: String
    var relativePath: String
    var filename: String
    var size: Int64
    var modifiedAt: Date
    var kind: MediaKind
}

actor ADBAdapter {
    let executableURL: URL

    init?(fileManager: FileManager = .default) {
        let home = fileManager.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "/Applications/MacDroid.app/Contents/Resources/adb"
        ]
        guard let path = candidates.first(where: fileManager.isExecutableFile(atPath:)) else { return nil }
        executableURL = URL(fileURLWithPath: path)
    }

    func discover() throws -> [AndroidDeviceSnapshot] {
        let output = try run(["devices", "-l"], timeout: 15)
        return output.split(separator: "\n").dropFirst().compactMap { line in
            let fields = line.split(whereSeparator: \Character.isWhitespace).map(String.init)
            guard fields.count >= 2 else { return nil }
            let serial = fields[0]
            let state = fields[1]
            let values = Dictionary(uniqueKeysWithValues: fields.dropFirst(2).compactMap { field -> (String, String)? in
                let parts = field.split(separator: ":", maxSplits: 1).map(String.init)
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            })
            // MacDroid can publish a legacy Nexus 4/occam compatibility endpoint even
            // when no such physical device exists. Keep it out of the ingest list.
            if values["product"] == "occam" && values["model"] == "Nexus_4" { return nil }
            if state != "device" {
                return AndroidDeviceSnapshot(serial: serial, manufacturer: "Android", model: values["model"] ?? "Unauthorized device", product: values["product"] ?? "", androidVersion: "", apiLevel: "", connection: state, isAuthorized: false)
            }
            let properties = (try? deviceProperties(serial: serial)) ?? [:]
            return AndroidDeviceSnapshot(serial: serial,
                                         manufacturer: properties["manufacturer"] ?? "Android",
                                         model: properties["model"] ?? values["model"]?.replacingOccurrences(of: "_", with: " ") ?? "Android device",
                                         product: values["product"] ?? "",
                                         androidVersion: properties["android"] ?? "",
                                         apiLevel: properties["sdk"] ?? "",
                                         connection: fields.contains(where: { $0.hasPrefix("usb:") }) ? "ADB over USB" : "ADB over network",
                                         isAuthorized: true)
        }
    }

    func scan(serial: String, folders: [String], progress: (@Sendable (String) -> Void)? = nil) throws -> [RemoteAndroidFile] {
        var results: [RemoteAndroidFile] = []
        for (index, folder) in folders.enumerated() {
            let displayName = URL(fileURLWithPath: folder).lastPathComponent
            progress?("Scanning folder \(index + 1) of \(folders.count): \(displayName)")
            let countBefore = results.count
            let quoted = shellQuote(folder)
            let command = "find \(quoted) -type f -exec stat -c '%s|%Y|%n' {} \\; 2>/dev/null"
            let output = try run(["-s", serial, "shell", command], timeout: 120)
            for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
                let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 3, let size = Int64(parts[0]), let timestamp = TimeInterval(parts[1]) else { continue }
                let path = parts[2]
                guard let kind = MediaClassifier.kind(for: URL(fileURLWithPath: path)) else { continue }
                let prefix = folder.hasSuffix("/") ? folder : folder + "/"
                let relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : URL(fileURLWithPath: path).lastPathComponent
                results.append(.init(path: path, relativePath: relative, filename: URL(fileURLWithPath: path).lastPathComponent, size: size, modifiedAt: Date(timeIntervalSince1970: timestamp), kind: kind))
            }
            progress?("Finished \(displayName): \(results.count - countBefore) supported files found")
        }
        return results.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func sourceSHA256(serial: String, path: String) throws -> String {
        let output = try run(["-s", serial, "shell", "sha256sum \(shellQuote(path))"], timeout: 300)
        guard let hash = output.split(whereSeparator: \Character.isWhitespace).first, hash.count == 64 else {
            throw ADBError.invalidResponse("The phone did not return a SHA-256 hash for \(path)")
        }
        return String(hash).lowercased()
    }

    func pull(serial: String, remotePath: String, localURL: URL) throws {
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try run(["-s", serial, "pull", "-a", remotePath, localURL.path], timeout: 3_600)
    }

    func deleteVerifiedSource(serial: String, remotePath: String) throws {
        let quoted = shellQuote(remotePath)
        var lastError: Error?
        for attempt in 1...5 {
            do {
                _ = try run(["-s", serial, "shell", "rm -f -- \(quoted) && test ! -e \(quoted)"], timeout: 60)
                return
            } catch {
                lastError = error
                if attempt < 5 { Thread.sleep(forTimeInterval: Double(attempt) * 0.35) }
            }
        }
        throw lastError ?? ADBError.command("Could not delete \(remotePath)")
    }

    private func deviceProperties(serial: String) throws -> [String: String] {
        let command = "printf 'manufacturer='; getprop ro.product.manufacturer; printf 'model='; getprop ro.product.model; printf 'android='; getprop ro.build.version.release; printf 'sdk='; getprop ro.build.version.sdk"
        let output = try run(["-s", serial, "shell", command], timeout: 15)
        return Dictionary(uniqueKeysWithValues: output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        })
    }

    private func run(_ arguments: [String], timeout: TimeInterval) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); throw ADBError.timeout(arguments.first ?? "command") }
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        let error = String(decoding: errorData, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw ADBError.command(error.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return output
    }

    private func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

enum ADBError: LocalizedError {
    case command(String), timeout(String), invalidResponse(String)
    var errorDescription: String? {
        switch self { case .command(let value): "ADB failed: \(value)"; case .timeout(let value): "ADB timed out while running \(value)"; case .invalidResponse(let value): value }
    }
}
