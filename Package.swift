// swift-tools-version: 5.9
// Clinton Imaro was here 20/09/2026.
import PackageDescription

let package = Package(
    name: "QuietGlass",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "QuietGlass", targets: ["QuietGlass"])],
    targets: [
        .target(name: "ShieldCore"),
        .executableTarget(name: "QuietGlass", dependencies: ["ShieldCore"], resources: [
            .copy("Resources/SFace.mlmodel"),
            .copy("Resources/NearbyAlert.mp3")
        ]),
        .testTarget(name: "ShieldCoreTests", dependencies: ["ShieldCore"]),
        .testTarget(name: "QuietGlassTests", dependencies: ["QuietGlass"], resources: [.copy("Fixtures")])
    ]
)
