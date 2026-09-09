// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "universal_bluetooth",
    platforms: [.macOS("10.15")],
    products: [
        .library(
            name: "universal-bluetooth",
            targets: ["universal_bluetooth"]
        )
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "universal_bluetooth",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "BluetoothPairingController"
            ]
        ),
        .target(
            name: "BluetoothPairingController",
            publicHeadersPath: "include"
        )
    ]
)
