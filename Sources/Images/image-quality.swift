public struct ImageQuality:
    Sendable,
    Codable,
    Hashable
{
    public let value: Int

    public init(
        _ value: Int
    ) throws {
        guard (1...100).contains(value) else {
            throw ImageError.invalidQuality(
                value
            )
        }

        self.value = value
    }

    public var fraction: Double {
        Double(value) / 100
    }

    public init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.singleValueContainer()

        try self.init(
            container.decode(
                Int.self
            )
        )
    }

    public func encode(
        to encoder: any Encoder
    ) throws {
        var container = encoder.singleValueContainer()

        try container.encode(
            value
        )
    }
}
