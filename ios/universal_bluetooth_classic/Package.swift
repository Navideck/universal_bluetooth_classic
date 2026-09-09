// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "universal_bluetooth_classic",
    platforms: [.iOS("12.0")],
    products: [
        .library(
            name: "universal-bluetooth-classic",
            targets: ["universal_bluetooth_classic"]
        )
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "universal_bluetooth_classic",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [.process("PrivacyInfo.xcprivacy")]
        )
    ]
)
