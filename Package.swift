// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IconKitchen",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "IconKitchen",
            path: "Sources/IconKitchen"
        )
    ]
)
