// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BetterDictation",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BetterDictation", targets: ["BetterDictation"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "BetterDictation",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/BetterDictation",
            resources: [
                .copy("../../Resources")
            ]
        ),
    ]
)
