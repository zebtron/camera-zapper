import Foundation
import Testing
@testable import CameraBackup

@Test func hashingAndAtomicVerification() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "CameraZapperTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appending(path: "source.bin")
    let destination = root.appending(path: "archive/subfolder/source.bin")
    try Data("zebtron-camera-zapper".utf8).write(to: source)
    let sourceHash = try FileHasher.sha256(url: source)
    let destinationHash = try AtomicFileTransfer.copyAndVerify(source: source, destination: destination, expectedHash: sourceHash)
    #expect(sourceHash == destinationHash)
    #expect(FileManager.default.fileExists(atPath: destination.path))
}

@Test func mediaClassification() {
    #expect(MediaClassifier.kind(for: URL(fileURLWithPath: "IMG_0001.ARW")) == .raw)
    #expect(MediaClassifier.kind(for: URL(fileURLWithPath: "VID_0001.MP4")) == .video)
    #expect(MediaClassifier.kind(for: URL(fileURLWithPath: "IMG_0001.XMP")) == .other)
    #expect(MediaClassifier.kind(for: URL(fileURLWithPath: "README.TXT")) == nil)
}

@Test func freshInstallServicesAreNeutralUntilChosen() {
    let services = ServiceConfiguration.defaults
    let local = services.first { $0.kind == .localStorage }
    #expect(local?.isEnabled == true)
    #expect(local?.isRequiredForDeletion == true)
    #expect(local?.setupState == .operational)

    for service in services where service.kind != .localStorage {
        #expect(service.isEnabled == false)
        #expect(service.isRequiredForDeletion == false)
        #expect(service.setupState == nil || service.setupState == .notSetUp)
    }
}

@Test func backupEngineDeletionPreflightRequiresVerifiedCopy() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "CameraZapperDeleteTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let archive = root.appending(path: "verified.jpg")
    let data = Data("verified media bytes".utf8)
    try data.write(to: archive)
    let hash = try FileHasher.sha256(url: archive)

    #expect(try BackupEngine.archivedCopyIsVerified(destination: archive, expectedSize: Int64(data.count), expectedHash: hash))
    #expect(try !BackupEngine.archivedCopyIsVerified(destination: archive, expectedSize: Int64(data.count + 1), expectedHash: hash))
    #expect(try !BackupEngine.archivedCopyIsVerified(destination: archive, expectedSize: Int64(data.count), expectedHash: String(repeating: "0", count: 64)))
}

@Test func failedAtomicVerificationCleansPartialFile() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "CameraZapperPartialTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appending(path: "source.bin")
    let destination = root.appending(path: "archive.bin")
    try Data("content that must not verify".utf8).write(to: source)

    #expect(throws: EngineError.self) {
        _ = try AtomicFileTransfer.copyAndVerify(source: source, destination: destination, expectedHash: String(repeating: "f", count: 64))
    }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.contains(".partial.") }
    #expect(leftovers.isEmpty)
}

@Test func flickrOversizePolicyOnlyBlocksRequiredApplicableMedia() {
    #expect(FlickrUploadPolicy.sizeLimit(for: .photo) == 195_000_000)
    #expect(FlickrUploadPolicy.sizeLimit(for: .video) == 990_000_000)
    #expect(!FlickrUploadPolicy.shouldBlockForSkippedOversize(serviceIsRequired: false, mediaIsAccepted: true))
    #expect(!FlickrUploadPolicy.shouldBlockForSkippedOversize(serviceIsRequired: true, mediaIsAccepted: false))
    #expect(FlickrUploadPolicy.shouldBlockForSkippedOversize(serviceIsRequired: true, mediaIsAccepted: true))
}
