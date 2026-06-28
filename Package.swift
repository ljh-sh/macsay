// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "macsay",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "macsay", targets: ["macsay"])
    ],
    targets: [
        .executableTarget(
            name: "macsay",
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