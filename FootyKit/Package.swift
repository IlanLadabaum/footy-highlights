// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FootyKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "FootyKit", targets: ["FootyKit"]),
        .executable(name: "footy-cli", targets: ["footy-cli"]),
    ],
    targets: [
        .target(
            name: "FootyKit",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "footy-cli",
            dependencies: ["FootyKit"]
        ),
        .testTarget(
            name: "FootyKitTests",
            dependencies: ["FootyKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
