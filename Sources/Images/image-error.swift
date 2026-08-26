import Foundation

public enum ImageError: Error, LocalizedError, Sendable {
    case missingSourceDirectory(URL)
    case missingSourceFile(URL)
    case invalidConfiguration(URL)
    case invalidPath(String)
    case unsupportedFormat(String)
    case unsupportedDestinationFormat(String)
    case imageDecodingFailed(String)
    case encodingFailed(URL)
    case invalidQuality(Int)
    case invalidWidth(Int)
    case invalidHeight(Int)
    case emptyResize

    public var errorDescription: String? {
        switch self {
        case .missingSourceDirectory(let url):
            return "Source directory not found: \(url.path)"

        case .missingSourceFile(let url):
            return "Source image not found: \(url.path)"

        case .invalidConfiguration(let url):
            return "Invalid image configuration: \(url.path)"

        case .invalidPath(let value):
            return "Image path is outside its allowed project directory: \(value)"

        case .unsupportedFormat(let value):
            return "Unsupported image format: \(value)"

        case .unsupportedDestinationFormat(let value):
            return "No native image encoder is available for: \(value)"

        case .imageDecodingFailed(let value):
            return "Could not decode image: \(value)"

        case .encodingFailed(let url):
            return "Could not encode image: \(url.path)"

        case .invalidQuality(let value):
            return "Quality must be between 1 and 100: \(value)"

        case .invalidWidth(let value):
            return "Maximum width must be greater than zero: \(value)"

        case .invalidHeight(let value):
            return "Maximum height must be greater than zero: \(value)"

        case .emptyResize:
            return "Resize must define at least one spatial bound."
        }
    }
}

public extension ImageError {
    var isUnsupportedDestinationFormat: Bool {
        if case .unsupportedDestinationFormat = self {
            return true
        }

        return false
    }
}
