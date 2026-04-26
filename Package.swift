// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoicePTT",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VoicePTT", targets: ["VoicePTT"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", "0.7.0"..<"0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "VoicePTT",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/VoicePTT"
        )
    ]
)
