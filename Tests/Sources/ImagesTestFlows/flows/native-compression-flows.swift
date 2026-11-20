import Foundation
import Images
import TestFlows

let nativeCompressionFlow = diagnosticFlow(
    "native-image-compression",
    title: "Native encoders resize PNG and create WebP",
    tags: [
        "compression",
        "imageio",
        "libwebp",
        "integration",
    ]
) {
    let workspace = try TestWorkspace(
        name: "native image compression"
    )

    defer {
        try? workspace.remove()
    }

    _ = try workspace.write(
        ImageFixtures.pngData(),
        relativePath: "raw/example.png"
    )

    let configuration = ImageConfiguration(
        images: [
            ImageConfiguration.Image(
                source: "raw/example.png",
                sourceSize: .init(
                    width: 4,
                    height: 3
                ),
                outputs: [
                    try .init(
                        destination: "compressed/example.png",
                        format: .png,
                        resize: try .init(
                            maxWidth: 2
                        ),
                        quality: 75
                    ),
                    try .init(
                        destination: "compressed/example.webp",
                        format: .webp,
                        resize: try .init(
                            maxWidth: 2
                        ),
                        quality: 75
                    ),
                ]
            ),
        ]
    )

    let report = ImageCompression.compress(
        in: ImageProject(
            root: workspace.root
        ),
        configuration: configuration
    )

    try Expect.equal(
        report.encodedCount,
        2,
        "encoded output count"
    )

    try Expect.equal(
        report.failedCount,
        0,
        "failed output count"
    )

    try Expect.equal(
        try ImageMetadata.dimensions(
            of: workspace.compressed.appendingPathComponent(
                "example.png"
            )
        ),
        ImageSize(
            width: 2,
            height: 2
        ),
        "PNG output dimensions"
    )

    try Expect.equal(
        try ImageMetadata.dimensions(
            of: workspace.compressed.appendingPathComponent(
                "example.webp"
            )
        ),
        ImageSize(
            width: 2,
            height: 2
        ),
        "WebP output dimensions"
    )

    return []
}

let compressionPrunesStaleOutputsFlow = diagnosticFlow(
    "compression-prunes-stale-outputs",
    title: "Compression removes stale configured outputs from compressed",
    tags: [
        "compression",
        "pruning",
        "filesystem",
        "integration",
    ]
) {
    let workspace = try TestWorkspace(
        name: "compression prunes stale outputs"
    )

    defer {
        try? workspace.remove()
    }

    _ = try workspace.write(
        ImageFixtures.pngData(),
        relativePath: "raw/example.png"
    )

    _ = try workspace.write(
        Data("stale".utf8),
        relativePath: "compressed/orphans/stale.png"
    )

    let configuration = ImageConfiguration(
        images: [
            ImageConfiguration.Image(
                source: "raw/example.png",
                sourceSize: .init(
                    width: 4,
                    height: 3
                ),
                outputs: [
                    try .init(
                        destination: "compressed/example.png",
                        format: .png,
                        resize: try .init(
                            maxWidth: 2
                        ),
                        quality: 75
                    ),
                ]
            ),
        ]
    )

    let report = ImageCompression.compress(
        in: ImageProject(
            root: workspace.root
        ),
        configuration: configuration
    )

    try Expect.equal(
        report.encodedCount,
        1,
        "encoded output count"
    )

    try Expect.equal(
        report.prunedCount,
        1,
        "pruned output count"
    )

    try Expect.equal(
        report.failedCount,
        0,
        "failed output count"
    )

    try Expect.equal(
        FileManager.default.fileExists(
            atPath: workspace.compressed
                .appendingPathComponent(
                    "orphans/stale.png"
                )
                .path
        ),
        false,
        "stale output removed"
    )

    try Expect.equal(
        FileManager.default.fileExists(
            atPath: workspace.compressed
                .appendingPathComponent(
                    "orphans"
                )
                .path
        ),
        false,
        "empty orphan directory removed"
    )

    try Expect.notNil(
        report.items.first {
            $0.status == .pruned
                && $0.destination == "compressed/orphans/stale.png"
        },
        "pruned output report item"
    )

    return []
}

let compressionPathSandboxFlow = diagnosticFlow(
    "compression-path-sandbox",
    title: "Compression rejects destinations outside compressed",
    tags: [
        "compression",
        "path",
        "security",
        "regression",
    ]
) {
    let workspace = try TestWorkspace(
        name: "compression path sandbox"
    )

    defer {
        try? workspace.remove()
    }

    _ = try workspace.write(
        ImageFixtures.pngData(),
        relativePath: "raw/example.png"
    )

    let configuration = ImageConfiguration(
        images: [
            ImageConfiguration.Image(
                source: "raw/example.png",
                sourceSize: .init(
                    width: 4,
                    height: 3
                ),
                outputs: [
                    try .init(
                        destination: "../escaped.png",
                        format: .png,
                        quality: 75
                    ),
                ]
            ),
        ]
    )

    let report = ImageCompression.compress(
        in: ImageProject(
            root: workspace.root
        ),
        configuration: configuration
    )

    try Expect.equal(
        report.encodedCount,
        0,
        "encoded output count"
    )

    try Expect.equal(
        report.failedCount,
        1,
        "rejected output count"
    )

    let escaped = workspace.root
        .deletingLastPathComponent()
        .appendingPathComponent(
            "escaped.png"
        )

    try Expect.equal(
        FileManager.default.fileExists(
            atPath: escaped.path
        ),
        false,
        "escaped output does not exist"
    )

    return []
}
