// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RemoteComment",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Capture",
            path: "Sources/Capture",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .executableTarget(
            name: "Display",
            path: "Sources/Display",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
    ]
)
