// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "ImagesTests",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "imagetest",
            targets: [
                "ImagesTestFlows",
            ]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/leviouwendijk/TestFlows.git",
            branch: "master"
        ),
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "ImagesTestFlows",
            dependencies: [
                .product(name: "Images", package: "Images"),
                .product(
                    name: "TestFlows",
                    package: "TestFlows"
                ),
            ],
            resources: [
                .copy(
                    "Resources/image-configuration-v2.json"
                ),
            ]
        ),
    ],
    swiftLanguageModes: [
        .v6,
    ]
)
