// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuietGlass",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "QuietGlass", targets: ["QuietGlass"])],
    targets: [
        .target(name: "ShieldCore"),
        .executableTarget(name: "QuietGlass", dependencies: ["ShieldCore"]),
        .testTarget(name: "ShieldCoreTests", dependencies: ["ShieldCore"])
    ]
)
