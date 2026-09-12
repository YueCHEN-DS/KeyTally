// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "KeyTally",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "KeyTally", targets: ["KeyTally"])
    ],
    targets: [
        .executableTarget(
            name: "KeyTally",
            path: "Sources/KeyTally"
        ),
        .testTarget(
            name: "KeyTallyTests",
            dependencies: ["KeyTally"],
            path: "Tests/KeyTallyTests"
        )
    ]
)
