// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThirdPlaceBackend",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ThirdPlaceBackend", targets: ["ThirdPlaceBackend"])
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.20.0"),
        .package(path: "../ThirdPlaceCore")
    ],
    targets: [
        .target(
            name: "ThirdPlaceBackend",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "ThirdPlaceCore", package: "ThirdPlaceCore")
            ]
        ),
        .testTarget(name: "ThirdPlaceBackendTests", dependencies: ["ThirdPlaceBackend"])
    ]
)
