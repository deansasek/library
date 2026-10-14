// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Library",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Library",
            path: "Sources/Library",
            resources: [.process("Resources")]
        )
    ]
)
