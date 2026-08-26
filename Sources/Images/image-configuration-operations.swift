import Foundation
import IO
import Readers
import Writers

public extension ImageConfiguration {
    struct GenerationOptions: Sendable {
        public var resize: ImageResize?
        public var quality: ImageQuality

        public init(
            resize: ImageResize? = nil,
            quality: Int = 80
        ) throws {
            self.resize = resize
            self.quality = try .init(
                quality
            )
        }

        public init(
            resize: ImageResize? = nil,
            quality: ImageQuality
        ) {
            self.resize = resize
            self.quality = quality
        }
    }

    static func generate(
        in project: ImageProject,
        options: GenerationOptions,
        preserving existing: ImageConfiguration? = nil
    ) async throws -> ImageConfiguration {
        let sources = try ImageDiscovery.sources(
            in: project
        )

        var configuration = existing ?? .init()

        var discoveredImages: [Image] = []

        for source in sources {
            let size = try await dimensions(
                of: source.url
            )

            let image = image(
                source: source,
                size: size,
                options: options
            )

            discoveredImages.append(
                image
            )
        }

        let discoveredSources = Set(
            discoveredImages.map(\.source)
        )

        configuration.images.removeAll {
            !discoveredSources.contains(
                $0.source
            )
        }

        for image in discoveredImages {
            if let index = configuration.images.firstIndex(
                where: {
                    $0.source == image.source
                }
            ) {
                configuration.images[index].sourceSize = image.sourceSize
            } else {
                configuration.images.append(
                    image
                )
            }
        }

        configuration.images.sort {
            $0.source < $1.source
        }

        return configuration
    }

    func write(
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
        ]

        let data = try encoder.encode(
            self
        )

        _ = try FileWriter(
            url
        )
        .write(
            data,
            options: .overwriteWithoutBackup
        )
    }

    static func read(
        from url: URL,
        missing fallback: ImageConfiguration? = nil
    ) throws -> ImageConfiguration {
        guard FileSystem.default.exists(
            url
        ) else {
            if let fallback {
                return fallback
            }

            throw ImageError.invalidConfiguration(
                url
            )
        }

        do {
            let data = try DataFileReader(
                url
            )
            .read()
            .data

            return try JSONDecoder().decode(
                ImageConfiguration.self,
                from: data
            )
        } catch {
            throw ImageError.invalidConfiguration(
                url
            )
        }
    }

    static func image(
        source: ImageSource,
        size: ImageSize,
        options: GenerationOptions
    ) -> Image {
        let sourcePath = source.relative
        let stem = source.url
            .deletingPathExtension()
            .lastPathComponent

        let parent = source.relative.value.segments
            .dropLast()
            .map(\.value)

        let outputParent = [
            ImageProjectDefaults.destinationDirectoryName,
        ] + Array(
            parent.dropFirst()
        )

        let original = ImagePath(
            components: outputParent + [
                stem,
            ],
            filetype: source.format
        )

        let webp = ImagePath(
            components: outputParent + [
                stem,
            ],
            filetype: .webp
        )

        let avif = ImagePath(
            components: outputParent + [
                stem,
            ],
            filetype: .avif
        )

        let resize = options.resize.flatMap {
            $0.fitting(size) == size ? nil : $0
        }

        let candidates = [
            Output(
                destination: original,
                format: source.format,
                resize: resize,
                quality: options.quality
            ),
            Output(
                destination: webp,
                format: .webp,
                resize: resize,
                quality: options.quality
            ),
            Output(
                destination: avif,
                format: .avif,
                resize: resize,
                quality: options.quality
            ),
        ]

        var destinations = Set<ImagePath>()
        let outputs = candidates.filter { output in
            destinations.insert(
                output.destination
            ).inserted
        }

        return Image(
            source: sourcePath,
            sourceSize: size,
            outputs: outputs
        )
    }

    static func dimensions(
        of url: URL
    ) async throws -> ImageSize {
        try ImageMetadata.dimensions(
            of: url
        )
    }
}
