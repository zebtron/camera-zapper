import CSQLite
import Foundation

final class CameraZapperDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    let url: URL

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw DatabaseError.open(message)
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
        try execute("PRAGMA busy_timeout=5000;")
        try migrate()
    }

    deinit { sqlite3_close(handle) }

    func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS devices (
          id TEXT PRIMARY KEY, stable_id TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL,
          model TEXT NOT NULL, source_path TEXT NOT NULL, category TEXT NOT NULL,
          first_seen REAL NOT NULL, last_seen REAL NOT NULL, is_connected INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS sessions (
          id TEXT PRIMARY KEY, device_id TEXT NOT NULL, device_name TEXT NOT NULL,
          started_at REAL NOT NULL, finished_at REAL, status TEXT NOT NULL,
          files_found INTEGER NOT NULL DEFAULT 0, files_verified INTEGER NOT NULL DEFAULT 0,
          files_failed INTEGER NOT NULL DEFAULT 0, bytes_transferred INTEGER NOT NULL DEFAULT 0,
          image_count INTEGER NOT NULL DEFAULT 0, video_count INTEGER NOT NULL DEFAULT 0,
          audio_count INTEGER NOT NULL DEFAULT 0, transcoded_count INTEGER NOT NULL DEFAULT 0,
          output_formats TEXT NOT NULL DEFAULT '', FOREIGN KEY(device_id) REFERENCES devices(id)
        );
        CREATE TABLE IF NOT EXISTS files (
          id TEXT PRIMARY KEY, session_id TEXT NOT NULL, source_path TEXT NOT NULL,
          relative_path TEXT NOT NULL, filename TEXT NOT NULL, byte_size INTEGER NOT NULL,
          modified_at REAL NOT NULL, media_kind TEXT NOT NULL, sha256 TEXT,
          destination_path TEXT, destination_sha256 TEXT, state TEXT NOT NULL,
          error_message TEXT, FOREIGN KEY(session_id) REFERENCES sessions(id)
        );
        CREATE INDEX IF NOT EXISTS idx_files_hash ON files(sha256, byte_size);
        CREATE INDEX IF NOT EXISTS idx_files_session ON files(session_id);
        CREATE TABLE IF NOT EXISTS receipts (
          operation_id TEXT PRIMARY KEY, machine_id TEXT NOT NULL, session_id TEXT NOT NULL,
          device_id TEXT NOT NULL, source_relative_path TEXT NOT NULL, filename TEXT NOT NULL,
          content_sha256 TEXT NOT NULL, byte_size INTEGER NOT NULL, destination_id TEXT NOT NULL,
          destination_path TEXT NOT NULL, destination_sha256 TEXT NOT NULL,
          artifact_type TEXT NOT NULL, verified_at REAL NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_receipt_dedupe
          ON receipts(content_sha256, byte_size, destination_id, artifact_type);
        CREATE TABLE IF NOT EXISTS events (
          id TEXT PRIMARY KEY, session_id TEXT, timestamp REAL NOT NULL,
          severity TEXT NOT NULL, message TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS service_containers (
          service_id TEXT NOT NULL, session_id TEXT NOT NULL, remote_id TEXT NOT NULL,
          display_name TEXT NOT NULL, created_at REAL NOT NULL,
          PRIMARY KEY(service_id, session_id)
        );
        """)
    }

    func upsertDevice(_ device: CameraDevice, sourcePath: String) throws {
        try run("""
        INSERT INTO devices(id,stable_id,display_name,model,source_path,category,first_seen,last_seen,is_connected)
        VALUES(?,?,?,?,?,?,?,?,?)
        ON CONFLICT(stable_id) DO UPDATE SET display_name=excluded.display_name, model=excluded.model,
        source_path=excluded.source_path, category=excluded.category, last_seen=excluded.last_seen,
        is_connected=excluded.is_connected;
        """, [.text(device.id.uuidString), .text(device.volumeUUID), .text(device.displayName), .text(device.model), .text(sourcePath), .text(device.category.rawValue), .double(device.lastSeen.timeIntervalSince1970), .double(device.lastSeen.timeIntervalSince1970), .integer(device.isConnected ? 1 : 0)])
    }

    func fetchDevices() throws -> [CameraDevice] {
        try query("SELECT id,stable_id,display_name,model,category,last_seen FROM devices ORDER BY last_seen DESC;", []) { statement in
            guard let id = UUID(uuidString: columnText(statement, 0)) else { return nil }
            let stableID = columnText(statement, 1)
            let model = columnText(statement, 3)
            return CameraDevice(id: id, displayName: columnText(statement, 2), model: model, volumeName: model, volumeUUID: stableID, isConnected: false, lastSeen: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)), filesWaiting: 0, manufacturer: "Android", releaseYear: nil, sensorDescription: "Connect this device to refresh automatically detected details", observedCardCapacitiesGB: [], videoCapability: "Connect this device to refresh video capabilities", shootsRAW: false, rawFormats: [], videoFormats: ["MP4", "HEVC"], customImagePath: nil, category: DeviceCategory(rawValue: columnText(statement, 4)) ?? .androidPhone, androidConnectionMethod: .automatic, sourceFolders: ["/sdcard/DCIM"], supportedCardTypes: ["Connect to detect storage details"], recommendedCardSpeed: "Connect to refresh", recommendedCardMakers: [], operatingSystem: "Offline", connectionProvider: "Previously connected device", connectionDetail: "Offline · reconnect this device to scan or sync", availableConnectionMethods: ["ADB over USB", "MacDroid File Provider", "OpenMTP / direct MTP", "ADB over Wi-Fi"])
        }
    }

    func createSession(_ session: BackupSession) throws {
        try run("""
        INSERT INTO sessions(id,device_id,device_name,started_at,finished_at,status,files_found,files_verified,files_failed,bytes_transferred,image_count,video_count,audio_count,transcoded_count,output_formats)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
        """, [.text(session.id.uuidString), .text(session.deviceID.uuidString), .text(session.deviceName), .double(session.startedAt.timeIntervalSince1970), session.finishedAt.map { .double($0.timeIntervalSince1970) } ?? .null, .text(session.status.rawValue), .integer(Int64(session.filesFound)), .integer(Int64(session.filesVerified)), .integer(Int64(session.filesFailed)), .integer(session.bytesTransferred), .integer(Int64(session.imageCount)), .integer(Int64(session.videoCount)), .integer(Int64(session.audioCount)), .integer(Int64(session.transcodedCount)), .text(session.outputFormats.joined(separator: ","))])
    }

    func updateSession(_ session: BackupSession) throws {
        try run("UPDATE sessions SET finished_at=?,status=?,files_found=?,files_verified=?,files_failed=?,bytes_transferred=?,image_count=?,video_count=?,audio_count=?,transcoded_count=?,output_formats=? WHERE id=?;",
                [session.finishedAt.map { .double($0.timeIntervalSince1970) } ?? .null, .text(session.status.rawValue), .integer(Int64(session.filesFound)), .integer(Int64(session.filesVerified)), .integer(Int64(session.filesFailed)), .integer(session.bytesTransferred), .integer(Int64(session.imageCount)), .integer(Int64(session.videoCount)), .integer(Int64(session.audioCount)), .integer(Int64(session.transcodedCount)), .text(session.outputFormats.joined(separator: ",")), .text(session.id.uuidString)])
    }

    func insertFile(_ file: PersistedFileRecord) throws {
        try run("INSERT OR REPLACE INTO files(id,session_id,source_path,relative_path,filename,byte_size,modified_at,media_kind,sha256,destination_path,destination_sha256,state,error_message) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?);",
                [.text(file.id.uuidString), .text(file.sessionID.uuidString), .text(file.sourcePath), .text(file.relativePath), .text(file.filename), .integer(file.size), .double(file.modifiedAt.timeIntervalSince1970), .text(file.kind.rawValue), file.sha256.map(SQLiteValue.text) ?? .null, file.destinationPath.map(SQLiteValue.text) ?? .null, file.destinationSHA256.map(SQLiteValue.text) ?? .null, .text(file.state.rawValue), file.errorMessage.map(SQLiteValue.text) ?? .null])
    }

    func updateFile(id: UUID, state: FileTransferState, sha256: String? = nil, destination: String? = nil, destinationSHA256: String? = nil, error: String? = nil) throws {
        try run("UPDATE files SET state=?,sha256=COALESCE(?,sha256),destination_path=COALESCE(?,destination_path),destination_sha256=COALESCE(?,destination_sha256),error_message=? WHERE id=?;",
                [.text(state.rawValue), sha256.map(SQLiteValue.text) ?? .null, destination.map(SQLiteValue.text) ?? .null, destinationSHA256.map(SQLiteValue.text) ?? .null, error.map(SQLiteValue.text) ?? .null, .text(id.uuidString)])
    }

    func hasVerifiedReceipt(hash: String, size: Int64, destinationID: String, artifactType: String = "original") throws -> Bool {
        try scalarInt("SELECT COUNT(*) FROM receipts WHERE content_sha256=? AND byte_size=? AND destination_id=? AND artifact_type=?;", [.text(hash), .integer(size), .text(destinationID), .text(artifactType)]) > 0
    }

    func verifiedReceipt(hash: String, size: Int64, destinationID: String, artifactType: String) throws -> TransferReceipt? {
        let matches: [TransferReceipt] = try query("SELECT operation_id,machine_id,session_id,device_id,source_relative_path,filename,content_sha256,byte_size,destination_id,destination_path,destination_sha256,artifact_type,verified_at FROM receipts WHERE content_sha256=? AND byte_size=? AND destination_id=? AND artifact_type=? LIMIT 1;", [.text(hash), .integer(size), .text(destinationID), .text(artifactType)]) { statement in
            guard let operationID = UUID(uuidString: columnText(statement, 0)), let machineID = UUID(uuidString: columnText(statement, 1)), let sessionID = UUID(uuidString: columnText(statement, 2)), let deviceID = UUID(uuidString: columnText(statement, 3)) else { return nil }
            return TransferReceipt(operationID: operationID, machineID: machineID, sessionID: sessionID, sourceDeviceID: deviceID, sourceRelativePath: columnText(statement, 4), filename: columnText(statement, 5), contentSHA256: columnText(statement, 6), byteSize: sqlite3_column_int64(statement, 7), destinationID: columnText(statement, 8), destinationPath: columnText(statement, 9), destinationSHA256: columnText(statement, 10), artifactType: columnText(statement, 11), verifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 12)))
        }
        return matches.first
    }

    func verifiedSourceFiles(deviceID: UUID) throws -> [PersistedFileRecord] {
        let records: [PersistedFileRecord] = try query("SELECT f.id,f.session_id,f.source_path,f.relative_path,f.filename,f.byte_size,f.modified_at,f.media_kind,f.sha256,f.state FROM files f JOIN sessions s ON s.id=f.session_id WHERE s.device_id=? AND f.sha256 IS NOT NULL AND f.state IN ('verified','safeToDelete') ORDER BY f.modified_at DESC;", [.text(deviceID.uuidString)]) { statement in
            guard let id = UUID(uuidString: columnText(statement, 0)), let sessionID = UUID(uuidString: columnText(statement, 1)) else { return nil }
            return PersistedFileRecord(id: id, sessionID: sessionID, sourcePath: columnText(statement, 2), relativePath: columnText(statement, 3), filename: columnText(statement, 4), size: sqlite3_column_int64(statement, 5), modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)), kind: MediaKind(rawValue: columnText(statement, 7)) ?? .other, sha256: columnText(statement, 8), destinationPath: nil, destinationSHA256: nil, state: FileTransferState(rawValue: columnText(statement, 9)) ?? .verified, errorMessage: nil)
        }
        var seen = Set<String>()
        return records.filter { seen.insert($0.sourcePath).inserted }
    }

    func markSourceDeleted(deviceID: UUID, sourcePath: String) throws {
        try run("UPDATE files SET state='deleted' WHERE source_path=? AND session_id IN (SELECT id FROM sessions WHERE device_id=?);", [.text(sourcePath), .text(deviceID.uuidString)])
    }

    func insertReceipt(_ receipt: TransferReceipt) throws {
        try run("INSERT OR IGNORE INTO receipts(operation_id,machine_id,session_id,device_id,source_relative_path,filename,content_sha256,byte_size,destination_id,destination_path,destination_sha256,artifact_type,verified_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?);",
                [.text(receipt.operationID.uuidString), .text(receipt.machineID.uuidString), .text(receipt.sessionID.uuidString), .text(receipt.sourceDeviceID.uuidString), .text(receipt.sourceRelativePath), .text(receipt.filename), .text(receipt.contentSHA256), .integer(receipt.byteSize), .text(receipt.destinationID), .text(receipt.destinationPath), .text(receipt.destinationSHA256), .text(receipt.artifactType), .double(receipt.verifiedAt.timeIntervalSince1970)])
    }

    func insertEvent(_ event: ActivityEvent, sessionID: UUID? = nil) throws {
        try run("INSERT INTO events(id,session_id,timestamp,severity,message) VALUES(?,?,?,?,?);", [.text(event.id.uuidString), sessionID.map { .text($0.uuidString) } ?? .null, .double(event.timestamp.timeIntervalSince1970), .text(event.severity.rawValue), .text(event.message)])
    }

    func fetchSessions(limit: Int = 200) throws -> [BackupSession] {
        try query("SELECT id,device_id,device_name,started_at,finished_at,status,files_found,files_verified,files_failed,bytes_transferred,image_count,video_count,audio_count,transcoded_count,output_formats FROM sessions ORDER BY started_at DESC LIMIT ?;", [.integer(Int64(limit))]) { statement in
            guard let id = UUID(uuidString: columnText(statement, 0)), let deviceID = UUID(uuidString: columnText(statement, 1)) else { return nil }
            return BackupSession(id: id, deviceID: deviceID, deviceName: columnText(statement, 2), startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)), finishedAt: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)), status: BackupStatus(rawValue: columnText(statement, 5)) ?? .failed, filesFound: Int(sqlite3_column_int64(statement, 6)), filesVerified: Int(sqlite3_column_int64(statement, 7)), filesFailed: Int(sqlite3_column_int64(statement, 8)), bytesTransferred: sqlite3_column_int64(statement, 9), imageCount: Int(sqlite3_column_int64(statement, 10)), videoCount: Int(sqlite3_column_int64(statement, 11)), audioCount: Int(sqlite3_column_int64(statement, 12)), outputFormats: columnText(statement, 14).split(separator: ",").map(String.init), transcodedCount: Int(sqlite3_column_int64(statement, 13)))
        }
    }

    func fetchEvents(limit: Int = 500) throws -> [ActivityEvent] {
        try query("SELECT id,timestamp,severity,message FROM events ORDER BY timestamp DESC LIMIT ?;", [.integer(Int64(limit))]) { statement in
            guard let id = UUID(uuidString: columnText(statement, 0)) else { return nil }
            return ActivityEvent(id: id, timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)), severity: ActivityEvent.Severity(rawValue: columnText(statement, 2)) ?? .info, message: columnText(statement, 3))
        }
    }

    func fetchReceipts(destinationID: String, artifactType: String = "original") throws -> [TransferReceipt] {
        try query("SELECT operation_id,machine_id,session_id,device_id,source_relative_path,filename,content_sha256,byte_size,destination_id,destination_path,destination_sha256,artifact_type,verified_at FROM receipts WHERE destination_id=? AND artifact_type=? ORDER BY verified_at;", [.text(destinationID), .text(artifactType)]) { statement in
            guard let operationID = UUID(uuidString: columnText(statement, 0)),
                  let machineID = UUID(uuidString: columnText(statement, 1)),
                  let sessionID = UUID(uuidString: columnText(statement, 2)),
                  let deviceID = UUID(uuidString: columnText(statement, 3)) else { return nil }
            return TransferReceipt(operationID: operationID, machineID: machineID, sessionID: sessionID, sourceDeviceID: deviceID, sourceRelativePath: columnText(statement, 4), filename: columnText(statement, 5), contentSHA256: columnText(statement, 6), byteSize: sqlite3_column_int64(statement, 7), destinationID: columnText(statement, 8), destinationPath: columnText(statement, 9), destinationSHA256: columnText(statement, 10), artifactType: columnText(statement, 11), verifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 12)))
        }
    }

    func serviceContainer(serviceID: String, sessionID: UUID) throws -> String? {
        try query("SELECT remote_id FROM service_containers WHERE service_id=? AND session_id=? LIMIT 1;", [.text(serviceID), .text(sessionID.uuidString)]) { columnText($0, 0) }.first
    }

    func saveServiceContainer(serviceID: String, sessionID: UUID, remoteID: String, displayName: String) throws {
        try run("INSERT OR REPLACE INTO service_containers(service_id,session_id,remote_id,display_name,created_at) VALUES(?,?,?,?,?);", [.text(serviceID), .text(sessionID.uuidString), .text(remoteID), .text(displayName), .double(Date().timeIntervalSince1970)])
    }

    private func execute(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let text = error.map { String(cString: $0) } ?? message
            sqlite3_free(error)
            throw DatabaseError.execute(text)
        }
    }

    private func run(_ sql: String, _ values: [SQLiteValue]) throws {
        lock.lock(); defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw DatabaseError.prepare(message) }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() { value.bind(to: statement, index: Int32(offset + 1)) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.execute(message) }
    }

    private func scalarInt(_ sql: String, _ values: [SQLiteValue]) throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw DatabaseError.prepare(message) }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() { value.bind(to: statement, index: Int32(offset + 1)) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int64(statement, 0)
    }

    private func query<T>(_ sql: String, _ values: [SQLiteValue], map: (OpaquePointer?) -> T?) throws -> [T] {
        lock.lock(); defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw DatabaseError.prepare(message) }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() { value.bind(to: statement, index: Int32(offset + 1)) }
        var results: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW { if let value = map(statement) { results.append(value) } }
        return results
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
    }

    private var message: String { handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error" }
}

private enum SQLiteValue {
    case text(String), integer(Int64), double(Double), null
    func bind(to statement: OpaquePointer?, index: Int32) {
        switch self {
        case .text(let value): sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        case .integer(let value): sqlite3_bind_int64(statement, index, value)
        case .double(let value): sqlite3_bind_double(statement, index, value)
        case .null: sqlite3_bind_null(statement, index)
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DatabaseError: LocalizedError {
    case open(String), prepare(String), execute(String)
    var errorDescription: String? {
        switch self { case .open(let value): "Database open failed: \(value)"; case .prepare(let value): "Database query failed: \(value)"; case .execute(let value): "Database write failed: \(value)" }
    }
}
