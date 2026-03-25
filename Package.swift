// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ENTExaminer",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    targets: [
        .executableTarget(
            name: "ENTExaminer",
            path: "ENTExaminer",
            exclude: [
                "Resources/Assets.xcassets",
                "Resources/AppIcon.icns",
                "ENTExaminer.entitlements",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "ENTExaminerTests",
            dependencies: ["ENTExaminer"],
            path: "ENTExaminerTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
