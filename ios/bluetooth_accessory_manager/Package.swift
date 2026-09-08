// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "bluetooth_accessory_manager",
    platforms: [.iOS("12.0")],
    products: [
        .library(
            name: "bluetooth-accessory-manager",
            targets: ["bluetooth_accessory_manager"]
        )
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "bluetooth_accessory_manager",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [.process("PrivacyInfo.xcprivacy")]
        )
    ]
)
