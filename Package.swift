// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Images",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "Images",
            targets: [
                "Images",
            ]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/leviouwendijk/IO.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Path.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/FileTypes.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Readers.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Writers.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Processes.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/ainame/Swift-WebP.git",
            from: "0.6.1"
        ),
        .package(
            url: "https://github.com/tayloraswift/swift-png.git",
            from: "4.5.0"
        ),
    ],
    targets: [
        .target(
            name: "Images",
            dependencies: [
                .product(
                    name: "IO",
                    package: "IO"
                ),
                .product(
                    name: "Path",
                    package: "Path"
                ),
                .product(
                    name: "FileTypes",
                    package: "FileTypes"
                ),
                .product(
                    name: "Readers",
                    package: "Readers"
                ),
                .product(
                    name: "Writers",
                    package: "Writers"
                ),
                .product(
                    name: "Processes",
                    package: "Processes"
                ),
                .product(
                    name: "WebP",
                    package: "swift-webp"
                ),
                .product(
                    name: "PNG",
                    package: "swift-png"
                ),
            ]
        ),
    ],
    swiftLanguageModes: [
        .v6,
    ]
)
