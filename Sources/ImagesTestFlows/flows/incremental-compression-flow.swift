import Foundation
import Images
import TestFlows

let incrementalCompressionFlow = diagnosticFlow(
    "incremental-image-compression",
    title: "Compression rebuilds only changed outputs",
    tags: [
        "compression",
        "incremental",
        "integration",
    ]
) {
    let workspace = try TestWorkspace(
        name: "incremental image compression"
    )

    defer {
        try? workspace.remove()
    }

    let source = try workspace.write(
        ImageFixtures.svgData(),
        relativePath: "raw/example.svg"
    )

    let project = ImageProject(
        root: workspace.root
    )

    var configuration = ImageConfiguration(
        images: [
            .init(
                source: "raw/example.svg",
                sourceSize: .init(
                    width: 8,
                    height: 6
                ),
                outputs: [
                    try .init(
                        destination: "compressed/example.svg",
                        format: .svg,
                        quality: 80
                    ),
                ]
            ),
        ]
    )

    let initial = ImageCompression.compress(
        in: project,
        configuration: configuration
    )

    try Expect.equal(
        initial.encodedCount,
        1,
        "initial encoded count"
    )

    try Expect.equal(
        FileManager.default.fileExists(
            atPath: project.incrementalState.path
        ),
        true,
        "incremental state exists"
    )

    let unchanged = ImageCompression.compress(
        in: project,
        configuration: configuration
    )

    try Expect.equal(
        unchanged.unchangedCount,
        1,
        "unchanged output count"
    )

    configuration.images[0].outputs[0].quality = try .init(61)

    let settingsChanged = ImageCompression.compress(
        in: project,
        configuration: configuration
    )

    try Expect.equal(
        settingsChanged.encodedCount,
        1,
        "settings change encoded count"
    )

    let changedSource = String(
        decoding: ImageFixtures.svgData(),
        as: UTF8.self
    )
    .replacingOccurrences(
        of: "#ff0000",
        with: "#00ff00"
    )

    try Data(
        changedSource.utf8
    )
    .write(
        to: source,
        options: .atomic
    )

    let sourceChanged = ImageCompression.compress(
        in: project,
        configuration: configuration
    )

    try Expect.equal(
        sourceChanged.encodedCount,
        1,
        "source change encoded count"
    )

    let forced = ImageCompression.compress(
        in: project,
        configuration: configuration,
        options: .init(
            incremental: false
        )
    )

    try Expect.equal(
        forced.encodedCount,
        1,
        "forced encoded count"
    )

    try Expect.equal(
        forced.failedCount,
        0,
        "forced failed count"
    )

    return []
}
