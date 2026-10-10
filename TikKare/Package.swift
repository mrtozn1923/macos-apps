// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TikKare",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TikKare",
            path: "Sources/TikKare"
        )
    ]
)
