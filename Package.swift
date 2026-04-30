// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ECGBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ECGBar",
            path: "Sources/ECGBar"
        )
    ]
)
