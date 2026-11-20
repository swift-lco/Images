import Foundation

enum ImageFixtures {
    static let png4x3 = """
    iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAEElEQVR4nGP8z4AATAy4OAAmdgEF5PO41QAAAABJRU5ErkJggg==
    """

    static let svg8x6 = """
    <svg xmlns="http://www.w3.org/2000/svg" width="8" height="6" viewBox="0 0 8 6">
        <rect width="8" height="6" fill="#ff0000"/>
    </svg>
    """

    static func pngData() throws -> Data {
        guard let data = Data(
            base64Encoded: png4x3,
            options: .ignoreUnknownCharacters
        ) else {
            throw ImageFixtureError.invalidBase64(
                "png4x3"
            )
        }

        return data
    }

    static func svgData() -> Data {
        Data(
            svg8x6.utf8
        )
    }
}

enum ImageFixtureError: Error {
    case invalidBase64(String)
}
