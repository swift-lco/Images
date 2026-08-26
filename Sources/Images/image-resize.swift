public struct ImageResize:
    Sendable,
    Codable,
    Hashable,
    CustomStringConvertible
{
    public let maxWidth: Int?
    public let maxHeight: Int?

    public init(
        maxWidth: Int? = nil,
        maxHeight: Int? = nil
    ) throws {
        guard maxWidth != nil || maxHeight != nil else {
            throw ImageError.emptyResize
        }

        if let maxWidth, maxWidth < 1 {
            throw ImageError.invalidWidth(
                maxWidth
            )
        }

        if let maxHeight, maxHeight < 1 {
            throw ImageError.invalidHeight(
                maxHeight
            )
        }

        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
    }

    public func fitting(
        _ source: ImageSize
    ) -> ImageSize {
        guard source.width > 0, source.height > 0 else {
            return source
        }

        let widthScale = maxWidth.map {
            Double($0) / Double(source.width)
        } ?? 1

        let heightScale = maxHeight.map {
            Double($0) / Double(source.height)
        } ?? 1

        let scale = min(
            1,
            min(
                widthScale,
                heightScale
            )
        )

        return .init(
            width: max(
                1,
                Int(
                    (Double(source.width) * scale)
                        .rounded()
                )
            ),
            height: max(
                1,
                Int(
                    (Double(source.height) * scale)
                        .rounded()
                )
            )
        )
    }

    public var description: String {
        var constraints: [String] = []

        if let maxWidth {
            constraints.append(
                "maxWidth=\(maxWidth)"
            )
        }

        if let maxHeight {
            constraints.append(
                "maxHeight=\(maxHeight)"
            )
        }

        return constraints.joined(
            separator: ","
        )
    }

    public init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        try self.init(
            maxWidth: container.decodeIfPresent(
                Int.self,
                forKey: .maxWidth
            ),
            maxHeight: container.decodeIfPresent(
                Int.self,
                forKey: .maxHeight
            )
        )
    }

    public func encode(
        to encoder: any Encoder
    ) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        try container.encodeIfPresent(
            maxWidth,
            forKey: .maxWidth
        )
        try container.encodeIfPresent(
            maxHeight,
            forKey: .maxHeight
        )
    }

    enum CodingKeys: String, CodingKey {
        case maxWidth = "max_width"
        case maxHeight = "max_height"
    }
}
