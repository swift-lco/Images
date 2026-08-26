// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Images",
    products: [
        .library(
            name: "Images",
            targets: ["Images"]
        ),
    ],
    targets: [
        .target(
            name: "Images"
        ),
    ],
    swiftLanguageModes: [.v6]
)
