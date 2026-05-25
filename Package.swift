// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "osd-notify",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "osd-notify", targets: ["OsdNotify"])
    ],
    targets: [
        .executableTarget(
            name: "OsdNotify"
        ),
        .testTarget(
            name: "OsdNotifyTests",
            dependencies: ["OsdNotify"]
        )
    ]
)
