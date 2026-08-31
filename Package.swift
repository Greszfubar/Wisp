// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Wisp",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4")
    ],
    targets: [
        .executableTarget(
            name: "Wisp",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/Wisp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
