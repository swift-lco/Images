private let imageConfigurationSchemaVersion = 2

extension ImageConfiguration {
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case images
    }

    public init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        let version = try container.decode(
            Int.self,
            forKey: .schemaVersion
        )

        guard version == imageConfigurationSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported image configuration schema version: \(version)"
            )
        }

        self.images = try container.decode(
            [Image].self,
            forKey: .images
        )
    }

    public func encode(
        to encoder: any Encoder
    ) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        try container.encode(
            imageConfigurationSchemaVersion,
            forKey: .schemaVersion
        )
        try container.encode(
            images,
            forKey: .images
        )
    }
}
