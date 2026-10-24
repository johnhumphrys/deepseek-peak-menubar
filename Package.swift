// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeepSeekPeak",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "DeepSeekPeakBar", targets: ["DeepSeekPeakBar"]),
    ],
    targets: [
        .target(
            name: "PeakCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DeepSeekPeakBar",
            dependencies: ["PeakCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PeakCoreTests",
            dependencies: ["PeakCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
