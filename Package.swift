// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HowTo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "HowToApp",
            targets: ["HowToApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "HowToApp",
            dependencies: []
        )
    ]
)

