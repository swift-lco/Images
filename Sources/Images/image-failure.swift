import Foundation

public enum ImageFailureCategory:
    String,
    Sendable,
    Codable,
    Hashable,
    CaseIterable
{
    case configuration
    case sourceMissing = "source_missing"
    case sourceDecoding = "source_decoding"
    case resizing
    case outputEncoding = "output_encoding"
    case unsupportedFormat = "unsupported_format"
    case workerRuntime = "worker_runtime"
    case filesystem
    case pruning
    case incrementalState = "incremental_state"
    case unknown

    public var label: String {
        switch self {
        case .configuration:
            return "Configuration"

        case .sourceMissing:
            return "Source missing"

        case .sourceDecoding:
            return "Source decoding"

        case .resizing:
            return "Image resizing"

        case .outputEncoding:
            return "Output encoding"

        case .unsupportedFormat:
            return "Unsupported format"

        case .workerRuntime:
            return "Worker runtime"

        case .filesystem:
            return "Filesystem"

        case .pruning:
            return "Output pruning"

        case .incrementalState:
            return "Incremental state"

        case .unknown:
            return "Unknown"
        }
    }
}

protocol ImageFailureRepresentable: Error {
    var imageFailureCategory: ImageFailureCategory { get }
    var imageFailureSummary: String { get }
}

struct ImageFailureDetails {
    let category: ImageFailureCategory
    let summary: String
    let description: String

    init(
        _ error: Error,
        fallback: ImageFailureCategory = .unknown
    ) {
        if let represented = error as? any ImageFailureRepresentable {
            category = represented.imageFailureCategory
            summary = represented.imageFailureSummary
        } else {
            category = fallback
            summary = (
                error as? LocalizedError
            )?
            .errorDescription
            ?? String(
                describing: error
            )
        }

        description = (
            error as? LocalizedError
        )?
        .errorDescription
        ?? String(
            describing: error
        )
    }
}

extension ImageError: ImageFailureRepresentable {
    var imageFailureCategory: ImageFailureCategory {
        switch self {
        case .missingSourceDirectory,
             .missingSourceFile:
            return .sourceMissing

        case .invalidConfiguration,
             .invalidPath,
             .invalidQuality,
             .invalidWidth,
             .invalidHeight,
             .emptyResize:
            return .configuration

        case .unsupportedFormat,
             .unsupportedDestinationFormat:
            return .unsupportedFormat

        case .imageDecodingFailed:
            return .sourceDecoding

        case .encodingFailed:
            return .outputEncoding
        }
    }

    var imageFailureSummary: String {
        errorDescription
            ?? "Image processing failed."
    }
}
