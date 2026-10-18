// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NabizTut",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NabizTut",
            path: "Sources/NabizTut",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
