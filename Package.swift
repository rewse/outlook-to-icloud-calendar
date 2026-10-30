// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Outlook2iCloudCal",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "Outlook2iCloudCalCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Outlook2iCloudCal",
            dependencies: ["Outlook2iCloudCalCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "Outlook2iCloudCalCoreTests",
            dependencies: ["Outlook2iCloudCalCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
