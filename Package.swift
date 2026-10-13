// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacMouseMapper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacMouseMapper", targets: ["MacMouseMapper"]),
        .library(name: "MacMouseMapperCore", targets: ["MacMouseMapperCore"]),
        .executable(name: "MacMouseMapperCoreTests", targets: ["MacMouseMapperCoreTests"])
    ],
    targets: [
        .target(
            name: "MacMouseMapperCore"
        ),
        .executableTarget(
            name: "MacMouseMapper",
            dependencies: ["MacMouseMapperCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "MacMouseMapperCoreTests",
            dependencies: ["MacMouseMapperCore"],
            path: "Tests/MacMouseMapperCoreTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
