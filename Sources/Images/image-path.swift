import FileTypes
import Path

public struct ImagePath:
    Sendable,
    Codable,
    Hashable,
    Comparable,
    ExpressibleByStringLiteral
{
    public let value: StandardPath

    public init(
        _ value: StandardPath
    ) {
        self.value = value
    }

    public init(
        rawPath: String,
        filetype: PhotoFile? = nil
    ) {
        let resolvedFiletype = filetype
            ?? (try? PhotoFile(
                filename: rawPath
            ))
        let component = resolvedFiletype?.component
        let path: String

        if let component,
           rawPath.lowercased().hasSuffix(
               component.lowercased()
           )
        {
            path = String(
                rawPath.dropLast(
                    component.count
                )
            )
        } else {
            path = rawPath
        }

        self.init(
            StandardPath(
                rawPath: path,
                filetype: resolvedFiletype.map(
                    AnyFileType.photo
                )
            )
        )
    }

    public init(
        _ rawPath: String,
        filetype: PhotoFile? = nil
    ) {
        self.init(
            rawPath: rawPath,
            filetype: filetype
        )
    }

    public init(
        _ components: String...
    ) {
        value = StandardPath(
            components
        )
    }

    public init(
        components: [String],
        filetype: PhotoFile? = nil
    ) {
        value = StandardPath(
            components,
            filetype: filetype.map(
                AnyFileType.photo
            )
        )
    }

    public init(
        stringLiteral value: String
    ) {
        self.init(
            rawPath: value
        )
    }

    public var string: String {
        value.concatenated()
    }

    public static func < (
        lhs: Self,
        rhs: Self
    ) -> Bool {
        lhs.string < rhs.string
    }

    public init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.singleValueContainer()

        self.init(
            rawPath: try container.decode(
                String.self
            )
        )
    }

    public func encode(
        to encoder: any Encoder
    ) throws {
        var container = encoder.singleValueContainer()

        try container.encode(
            string
        )
    }
}
