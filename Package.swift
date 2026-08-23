// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CameraBackup",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CameraBackup", targets: ["CameraBackup"])],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite", pkgConfig: "sqlite3"),
        .executableTarget(
            name: "CameraBackup",
            dependencies: ["CSQLite"],
            path: "Sources/CameraBackup",
            exclude: ["Resources"]
        ),
        .testTarget(name: "CameraBackupTests", dependencies: ["CameraBackup"], path: "Tests/CameraBackupTests")
    ]
)
