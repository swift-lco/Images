import Images
import TestFlows

let projectLayoutFlow = diagnosticFlow(
    "project-layout-defaults",
    title: "Project layout defaults remain stable",
    tags: [
        "foundation",
        "layout",
        "regression",
    ]
) {
    try Expect.equal(
        ImageProjectDefaults.sourceDirectoryName,
        "raw",
        "source directory"
    )

    try Expect.equal(
        ImageProjectDefaults.destinationDirectoryName,
        "compressed",
        "destination directory"
    )

    try Expect.equal(
        ImageProjectDefaults.configurationFilename,
        "simg-config.json",
        "configuration filename"
    )

    return []
}

let pathRenderingFlow = diagnosticFlow(
    "path-rendering",
    title: "Image paths render through Path",
    tags: [
        "foundation",
        "path",
    ]
) {
    let path = ImagePath(
        components: [
            "raw",
            "nested",
            "example",
        ],
        filetype: .png
    )

    try Expect.equal(
        path.string,
        "raw/nested/example.png",
        "rendered image path"
    )

    return []
}
