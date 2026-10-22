// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuraPlayer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AuraPlayer", targets: ["AuraPlayer"])
    ],
    targets: [
        .executableTarget(
            name: "AuraPlayer",
            path: "Sources/AuraPlayer"
        )
    ]
)
