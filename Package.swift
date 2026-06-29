// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "macsay",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "macsay", targets: ["macsay"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.4"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "macsay",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
            ],
            path: "Sources",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist"
                ])
            ]
        ),
        // .testTarget(name: "macsayTests", dependencies: ["macsay"]),
    ]
)