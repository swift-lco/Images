import FileTypes

public struct ImageConfiguration:
    Sendable,
    Codable,
    Hashable
{
    public var images: [Image]

    public init(
        images: [Image] = []
    ) {
        self.images = images
    }

    public struct Image:
        Sendable,
        Codable,
        Hashable
    {
        public var source: ImagePath
        public var sourceSize: ImageSize
        public var outputs: [Output]

        public init(
            source: ImagePath,
            sourceSize: ImageSize,
            outputs: [Output]
        ) {
            self.source = source
            self.sourceSize = sourceSize
            self.outputs = outputs
        }

        enum CodingKeys: String, CodingKey {
            case source
            case sourceSize = "source_size"
            case outputs
        }
    }

    public struct Output:
        Sendable,
        Codable,
        Hashable
    {
        public var destination: ImagePath
        public var format: PhotoFile
        public var resize: ImageResize?
        public var quality: ImageQuality

        public init(
            destination: ImagePath,
            format: PhotoFile,
            resize: ImageResize? = nil,
            quality: Int = 80
        ) throws {
            self.init(
                destination: destination,
                format: format,
                resize: resize,
                quality: try .init(
                    quality
                )
            )
        }

        public init(
            destination: ImagePath,
            format: PhotoFile,
            resize: ImageResize? = nil,
            quality: ImageQuality
        ) {
            self.destination = destination
            self.format = format
            self.resize = resize
            self.quality = quality
        }
    }
}

public struct ImageSize:
    Sendable,
    Codable,
    Hashable
{
    public var width: Int
    public var height: Int

    public init(
        width: Int,
        height: Int
    ) {
        self.width = width
        self.height = height
    }
}
