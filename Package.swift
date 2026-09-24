// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "IPsoFacto",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "IPsoFactoCore", targets: ["IPsoFactoCore"]),
        .executable(name: "IPsoFacto", targets: ["IPsoFacto"])
    ],
    targets: [
        .target(
            name: "IPsoFactoCore",
            path: "Sources/IPsoFactoCore"
        ),
        .executableTarget(
            name: "IPsoFacto",
            dependencies: ["IPsoFactoCore"],
            path: "Sources/IPsoFacto"
        ),
        .testTarget(
            name: "IPsoFactoCoreTests",
            dependencies: ["IPsoFactoCore"],
            path: "Tests/IPsoFactoCoreTests"
        )
    ]
)
