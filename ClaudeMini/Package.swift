// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeMini",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ClaudeMini", path: "Sources/ClaudeMini")
    ]
)
