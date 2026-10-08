// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Wakeloop",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WakeloopApp", targets: ["WakeloopApp"]),
        .executable(name: "wakeloop", targets: ["wakeloop"]),
    ],
    targets: [
        .target(name: "WakeloopCore"),
        .executableTarget(name: "WakeloopApp", dependencies: ["WakeloopCore"]),
        .executableTarget(name: "wakeloop", dependencies: ["WakeloopCore"]),
        .testTarget(name: "WakeloopCoreTests", dependencies: ["WakeloopCore"]),
    ]
)
