import Foundation
import Images
import TestFlows

private enum ImageConfigurationContractFlowError: Error {
    case missingFixture
    case malformedEncodedConfiguration
}

let imageConfigurationSwiftContractFlow = diagnosticFlow(
    "image-configuration-swift-contract",
    title: "Image configuration exposes semantic paths, resize constraints, and quality",
    tags: [
        "configuration",
        "contract",
        "ergonomics",
        "regression",
    ]
) {
    let output = try ImageConfiguration.Output(
        destination: "compressed/example.webp",
        format: .webp,
        resize: try .init(
            maxWidth: 1920,
            maxHeight: 1080
        ),
        quality: 72
    )

    let image = ImageConfiguration.Image(
        source: "raw/example.jpg",
        sourceSize: .init(
            width: 4000,
            height: 3000
        ),
        outputs: [
            output,
        ]
    )

    try Expect.equal(
        image.source.string,
        "raw/example.jpg",
        "semantic source path"
    )

    try Expect.equal(
        output.destination.string,
        "compressed/example.webp",
        "semantic destination path"
    )

    try Expect.equal(
        output.resize?.maxWidth,
        1920,
        "resize maximum width"
    )

    try Expect.equal(
        output.resize?.maxHeight,
        1080,
        "resize maximum height"
    )

    try Expect.equal(
        output.quality.value,
        72,
        "validated image quality"
    )

    let encodedPath = try JSONEncoder().encode(
        image.source
    )

    try Expect.equal(
        try JSONDecoder().decode(
            String.self,
            from: encodedPath
        ),
        "raw/example.jpg",
        "ImagePath single-value wire representation"
    )

    let decodedPath = try JSONDecoder().decode(
        ImagePath.self,
        from: encodedPath
    )

    try Expect.equal(
        decodedPath,
        image.source,
        "ImagePath retains semantic identity through Codable"
    )

    return []
}

let imageResizeFittingFlow = diagnosticFlow(
    "image-resize-fitting",
    title: "Resize constraints preserve aspect ratio and never upscale",
    tags: [
        "resize",
        "geometry",
        "regression",
    ]
) {
    let source = ImageSize(
        width: 4000,
        height: 3000
    )

    try Expect.equal(
        try ImageResize(
            maxWidth: 2000
        ).fitting(
            source
        ),
        .init(
            width: 2000,
            height: 1500
        ),
        "width-bounded fit"
    )

    try Expect.equal(
        try ImageResize(
            maxHeight: 1000
        ).fitting(
            source
        ),
        .init(
            width: 1333,
            height: 1000
        ),
        "height-bounded fit"
    )

    try Expect.equal(
        try ImageResize(
            maxWidth: 2000,
            maxHeight: 1000
        ).fitting(
            source
        ),
        .init(
            width: 1333,
            height: 1000
        ),
        "two-dimensional bounded fit"
    )

    try Expect.equal(
        try ImageResize(
            maxWidth: 8000
        ).fitting(
            source
        ),
        source,
        "resize does not upscale"
    )

    return []
}

let imageConfigurationV2RoundTripFlow = diagnosticFlow(
    "image-configuration-v2-round-trip",
    title: "Schema-v2 image configuration preserves the approved Swift contract",
    tags: [
        "configuration",
        "codable",
        "schema",
        "regression",
    ]
) {
    guard let fixture = Bundle.module.url(
        forResource: "image-configuration-v2",
        withExtension: "json"
    ) else {
        throw ImageConfigurationContractFlowError.missingFixture
    }

    let fixtureData = try Data(
        contentsOf: fixture
    )
    let configuration = try JSONDecoder().decode(
        ImageConfiguration.self,
        from: fixtureData
    )

    try Expect.equal(
        configuration.images.count,
        2,
        "v2 fixture image count"
    )

    let resized = configuration.images[0]

    try Expect.equal(
        resized.source.string,
        "raw/8178.jpg",
        "v2 source path"
    )

    try Expect.equal(
        resized.sourceSize,
        .init(
            width: 8190,
            height: 5464
        ),
        "v2 source_size"
    )

    try Expect.equal(
        resized.outputs[0].resize?.maxWidth,
        1080,
        "v2 nested resize width"
    )

    try Expect.equal(
        resized.outputs[0].resize?.maxHeight,
        nil,
        "v2 optional resize height"
    )

    try Expect.equal(
        resized.outputs[0].quality.value,
        80,
        "v2 image quality"
    )

    try Expect.equal(
        configuration.images[1].outputs[0].resize,
        nil,
        "v2 omitted resize remains no-resize"
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [
        .sortedKeys,
    ]

    let encoded = try encoder.encode(
        configuration
    )

    guard
        let object = try JSONSerialization.jsonObject(
            with: encoded
        ) as? [String: Any],
        let images = object["images"] as? [[String: Any]],
        let first = images.first,
        let outputs = first["outputs"] as? [[String: Any]],
        let firstOutput = outputs.first,
        let resize = firstOutput["resize"] as? [String: Any]
    else {
        throw ImageConfigurationContractFlowError.malformedEncodedConfiguration
    }

    try Expect.equal(
        object["schema_version"] as? Int,
        2,
        "encoded schema version"
    )

    try Expect.equal(
        first["source_size"] != nil,
        true,
        "encoded source_size field"
    )

    try Expect.equal(
        resize["max_width"] as? Int,
        1080,
        "encoded nested resize width"
    )

    let roundTripped = try JSONDecoder().decode(
        ImageConfiguration.self,
        from: encoded
    )

    try Expect.equal(
        roundTripped,
        configuration,
        "v2 configuration round trip"
    )

    return []
}
