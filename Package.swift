// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeLimitsToolbar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeLimitsToolbar", targets: ["ClaudeLimitsToolbar"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeLimitsToolbar",
            path: "Sources/ClaudeLimitsToolbar"
        ),
        .testTarget(
            name: "ClaudeLimitsToolbarTests",
            dependencies: ["ClaudeLimitsToolbar"],
            path: "Tests/ClaudeLimitsToolbarTests"
        )
    ]
)
