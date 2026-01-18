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
        // FluidAudio для Parakeet TDT v3 - быстрая multilingual транскрипция
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9"),
    ],
    targets: [
        .executableTarget(
            name: "BetterDictation",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/BetterDictation",
            resources: [
                .copy("../../Resources")
            ]
        ),
    ]
)
