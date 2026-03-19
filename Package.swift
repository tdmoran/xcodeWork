// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ENTExaminer",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "ENTExaminer",
            path: "ENTExaminer",
            exclude: [
                "Resources/Assets.xcassets",
                "ENTExaminer.entitlements",
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "ENTExaminerTests",
            path: "Tests"
        ),
    ]
)
