// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThirdPlaceCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ThirdPlaceCore", targets: ["ThirdPlaceCore"])
    ],
    targets: [
        .target(name: "ThirdPlaceCore"),
        .testTarget(name: "ThirdPlaceCoreTests", dependencies: ["ThirdPlaceCore"])
    ]
)
