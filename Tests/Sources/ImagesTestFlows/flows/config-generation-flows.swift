import Foundation
import Images
import TestFlows

let generatedImageConfigurationFlow = diagnosticFlow(
    "generated-image-configuration",
    title: "Config generation reads deterministic image fixtures",
    tags: [
        "configuration",
        "filesystem",
        "image",
        "integration",
    ]
) {
    let workspace = try TestWorkspace(
        name: "generated image configuration"
    )

    defer {
        try? workspace.remove()
    }

    _ = try workspace.write(
        ImageFixtures.pngData(),
        relativePath: "raw/example.png"
    )

    _ = try workspace.write(
        ImageFixtures.pngData(),
        relativePath: "raw/nested/second.png"
    )

    _ = try workspace.write(
        ImageFixtures.svgData(),
        relativePath: "raw/vector.svg"
    )

    _ = try workspace.write(
        Data("ignored".utf8),
        relativePath: "raw/ignored.txt"
    )

    let project = ImageProject(
        root: workspace.root
    )

    let configuration = try await ImageConfiguration.generate(
        in: project,
        options: try .init(
            resize: try .init(
                maxWidth: 2
            ),
            quality: 75
        )
    )

    try Expect.equal(
        configuration.images.count,
        3,
        "supported image count"
    )

    try Expect.equal(
        configuration.images.map { $0.source.string },
        [
            "raw/example.png",
            "raw/nested/second.png",
            "raw/vector.svg",
        ],
        "discovered source paths"
    )

    let example = try Expect.notNil(
        configuration.images.first {
            $0.source == "raw/example.png"
        },
        "example image"
    )

    try Expect.equal(
        example.sourceSize,
        ImageSize(
            width: 4,
            height: 3
        ),
        "PNG dimensions"
    )

    try Expect.equal(
        example.outputs.map { $0.destination.string },
        [
            "compressed/example.png",
            "compressed/example.webp",
            "compressed/example.avif",
        ],
        "PNG output paths"
    )

    try Expect.equal(
        example.outputs.map { $0.resize?.maxWidth },
        [
            2,
            2,
            2,
        ],
        "PNG resize values"
    )

    let nested = try Expect.notNil(
        configuration.images.first {
            $0.source == "raw/nested/second.png"
        },
        "nested image"
    )

    try Expect.equal(
        nested.outputs.map { $0.destination.string },
        [
            "compressed/nested/second.png",
            "compressed/nested/second.webp",
            "compressed/nested/second.avif",
        ],
        "nested output paths"
    )

    let vector = try Expect.notNil(
        configuration.images.first {
            $0.source == "raw/vector.svg"
        },
        "SVG image"
    )

    try Expect.equal(
        vector.sourceSize,
        ImageSize(
            width: 8,
            height: 6
        ),
        "SVG dimensions"
    )

    return []
}

let preservedConfigurationReconciliationFlow = diagnosticFlow(
    "preserved-configuration-reconciliation",
    title: "Config generation preserves existing outputs and removes stale sources",
    tags: [
        "configuration",
        "preservation",
        "pruning",
        "integration",
    ]
) {
    let workspace = try TestWorkspace(
        name: "preserved configuration reconciliation"
    )

    defer {
        try? workspace.remove()
    }

    _ = try workspace.write(
        ImageFixtures.pngData(),
        relativePath: "raw/example.png"
    )

    _ = try workspace.write(
        ImageFixtures.pngData(),
        relativePath: "raw/new.png"
    )

    let preservedOutputs = [
        try ImageConfiguration.Output(
            destination: "compressed/custom/example.optimized.webp",
            format: .webp,
            resize: try .init(
                maxWidth: 3
            ),
            quality: 61
        ),
    ]

    let staleOutputs = [
        try ImageConfiguration.Output(
            destination: "compressed/stale.png",
            format: .png,
            quality: 80
        ),
    ]

    let existing = ImageConfiguration(
        images: [
            .init(
                source: "raw/example.png",
                sourceSize: .init(
                    width: 999,
                    height: 999
                ),
                outputs: preservedOutputs
            ),
            .init(
                source: "raw/stale.png",
                sourceSize: .init(
                    width: 1,
                    height: 1
                ),
                outputs: staleOutputs
            ),
        ]
    )

    let configuration = try await ImageConfiguration.generate(
        in: ImageProject(
            root: workspace.root
        ),
        options: try .init(
            resize: try .init(
                maxWidth: 2
            ),
            quality: 75
        ),
        preserving: existing
    )

    try Expect.equal(
        configuration.images.map { $0.source.string },
        [
            "raw/example.png",
            "raw/new.png",
        ],
        "reconciled source paths"
    )

    let preserved = try Expect.notNil(
        configuration.images.first {
            $0.source == "raw/example.png"
        },
        "preserved image"
    )

    try Expect.equal(
        preserved.sourceSize,
        ImageSize(
            width: 4,
            height: 3
        ),
        "preserved image size updated"
    )

    try Expect.equal(
        preserved.outputs,
        preservedOutputs,
        "preserved outputs"
    )

    let appended = try Expect.notNil(
        configuration.images.first {
            $0.source == "raw/new.png"
        },
        "appended image"
    )

    try Expect.equal(
        appended.outputs.map { $0.destination.string },
        [
            "compressed/new.png",
            "compressed/new.webp",
            "compressed/new.avif",
        ],
        "new image default outputs"
    )

    return []
}
