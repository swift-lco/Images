import Foundation
import IO

public enum ImageCompressionStatus:
    String,
    Sendable,
    Codable,
    Hashable
{
    case encoded
    case unchanged
    case skipped
    case failed
    case pruned
}

public struct ImageCompressionItem:
    Sendable,
    Codable,
    Hashable
{
    public let source: String
    public let destination: String
    public let status: ImageCompressionStatus
    public let encoder: String?
    public let byteCount: Int64?
    public let errorDescription: String?
    public let failureCategory: ImageFailureCategory?
    public let failureSummary: String?

    public init(
        source: String,
        destination: String,
        status: ImageCompressionStatus,
        encoder: String?,
        byteCount: Int64?,
        errorDescription: String?,
        failureCategory: ImageFailureCategory? = nil,
        failureSummary: String? = nil
    ) {
        self.source = source
        self.destination = destination
        self.status = status
        self.encoder = encoder
        self.byteCount = byteCount
        self.errorDescription = errorDescription
        self.failureCategory = failureCategory
        self.failureSummary = failureSummary
    }
}

public struct ImageCompressionReport:
    Sendable,
    Codable,
    Hashable
{
    public let items: [ImageCompressionItem]

    public init(
        items: [ImageCompressionItem]
    ) {
        self.items = items
    }

    public var processedCount: Int {
        encodedCount
            + unchangedCount
            + skippedCount
            + failedCount
    }

    public var encodedCount: Int {
        items.filter {
            $0.status == .encoded
        }.count
    }

    public var unchangedCount: Int {
        items.filter {
            $0.status == .unchanged
        }.count
    }

    public var skippedCount: Int {
        items.filter {
            $0.status == .skipped
        }.count
    }

    public var failedCount: Int {
        items.filter {
            $0.status == .failed
        }.count
    }

    public var failedSourceCount: Int {
        Set(
            items
                .filter {
                    $0.status == .failed
                }
                .map(
                    \.source
                )
        )
        .count
    }

    public var prunedCount: Int {
        items.filter {
            $0.status == .pruned
        }.count
    }

    public var failureCounts: [ImageFailureCategory: Int] {
        items
            .filter {
                $0.status == .failed
            }
            .reduce(
                into: [:]
            ) { counts, item in
                counts[
                    item.failureCategory ?? .unknown,
                    default: 0
                ] += 1
            }
    }
}

public enum ImageCompression {
    public struct Options: Sendable {
        public var overwrite: Bool
        public var prune: Bool
        public var incremental: Bool

        public init(
            overwrite: Bool = true,
            prune: Bool = true,
            incremental: Bool = true
        ) {
            self.overwrite = overwrite
            self.prune = prune
            self.incremental = incremental
        }
    }

    public static func compress(
        in project: ImageProject,
        configuration: ImageConfiguration,
        options: Options = .init(),
        encoders: [any ImageEncoder] = [
            ImageCopyEncoder(),
            ImageWebPEncoder(),
            ImagePNGEncoder(),
            ImageIOEncoder(),
        ],
        fileSystem: FileSystem = .default,
        progress: ((ImageCompressionProgress) -> Void)? = nil
    ) -> ImageCompressionReport {
        let totalOutputCount = configuration.images.reduce(
            into: 0
        ) { count, image in
            count += image.outputs.count
        }

        var completedOutputCount = 0
        var items: [ImageCompressionItem] = []
        var incremental = ImageIncrementalSession(
            project: project
        )

        for image in configuration.images {
            for output in image.outputs {
                let itemCountBeforeOutput = items.count

                defer {
                    if items.count > itemCountBeforeOutput {
                        completedOutputCount += 1

                        progress?(
                            .init(
                                completedCount: completedOutputCount,
                                totalCount: totalOutputCount,
                                item: items[itemCountBeforeOutput]
                            )
                        )
                    }
                }

                do {
                    let source = try project.sourceURL(
                        image.source
                    )

                    let destination = try project.destinationURL(
                        output.destination
                    )

                    guard fileSystem.exists(
                        source
                    ) else {
                        throw ImageError.missingSourceFile(
                            source
                        )
                    }

                    if
                        fileSystem.exists(
                            destination
                        ),
                        !options.overwrite
                    {
                        items.append(
                            .init(
                                source: image.source.string,
                                destination: output.destination.string,
                                status: .skipped,
                                encoder: nil,
                                byteCount: nil,
                                errorDescription: nil
                            )
                        )

                        continue
                    }

                    let plan = try incremental.plan(
                        sourcePath: image.source.string,
                        source: source,
                        destination: destination,
                        output: output,
                        encoders: encoders
                    )

                    if options.incremental, plan.isCurrent {
                        items.append(
                            .init(
                                source: image.source.string,
                                destination: output.destination.string,
                                status: .unchanged,
                                encoder: plan.encoder.identifier,
                                byteCount: plan.byteCount,
                                errorDescription: nil
                            )
                        )

                        continue
                    }

                    try fileSystem.directory.create(
                        destination.deletingLastPathComponent()
                    )

                    let temporary = destination
                        .deletingLastPathComponent()
                        .appendingPathComponent(
                            ".images-\(UUID().uuidString)"
                        )
                        .appendingPathExtension(
                            output.format.rawValue
                        )

                    defer {
                        try? fileSystem.remove(
                            temporary
                        )
                    }

                    let request = ImageEncodingRequest(
                        source: source,
                        destination: temporary,
                        output: output
                    )

                    let result = try plan.encoder.encode(
                        request
                    )

                    if fileSystem.exists(
                        destination
                    ) {
                        try fileSystem.replace(
                            destination,
                            with: temporary
                        )
                    } else {
                        try fileSystem.move(
                            temporary,
                            to: destination
                        )
                    }

                    try incremental.record(
                        plan,
                        destination: destination,
                        destinationPath: output.destination.string
                    )

                    items.append(
                        .init(
                            source: image.source.string,
                            destination: output.destination.string,
                            status: .encoded,
                            encoder: result.encoder,
                            byteCount: result.byteCount,
                            errorDescription: nil
                        )
                    )
                } catch {
                    let unsupportedDestination =
                        (
                            error as? ImageError
                        )?
                        .isUnsupportedDestinationFormat == true

                    let optionalAVIF =
                        output.format == .avif
                        && unsupportedDestination

                    let status: ImageCompressionStatus =
                        optionalAVIF
                            ? .skipped
                            : .failed

                    let failure = ImageFailureDetails(
                        error
                    )

                    items.append(
                        .init(
                            source: image.source.string,
                            destination: output.destination.string,
                            status: status,
                            encoder: nil,
                            byteCount: nil,
                            errorDescription: failure.description,
                            failureCategory: status == .failed
                                ? failure.category
                                : nil,
                            failureSummary: status == .failed
                                ? failure.summary
                                : nil
                        )
                    )
                }
            }
        }

        if options.prune, !items.contains(where: { $0.status == .failed }) {
            do {
                items.append(
                    contentsOf: try pruneStaleOutputs(
                        in: project,
                        configuration: configuration,
                        fileSystem: fileSystem
                    )
                )
            } catch {
                let failure = ImageFailureDetails(
                    error,
                    fallback: .pruning
                )

                items.append(
                    .init(
                        source: "(prune)",
                        destination: ImageProjectDefaults.destinationDirectoryName,
                        status: .failed,
                        encoder: nil,
                        byteCount: nil,
                        errorDescription: failure.description,
                        failureCategory: failure.category,
                        failureSummary: failure.summary
                    )
                )
            }
        }

        incremental.retain(
            configuration: configuration
        )

        do {
            try incremental.write(
                to: project.incrementalState
            )
        } catch {
            let failure = ImageFailureDetails(
                error,
                fallback: .incrementalState
            )

            items.append(
                .init(
                    source: "(incremental-state)",
                    destination: ImageProjectDefaults.incrementalStateFilename,
                    status: .failed,
                    encoder: nil,
                    byteCount: nil,
                    errorDescription: failure.description,
                    failureCategory: failure.category,
                    failureSummary: failure.summary
                )
            )
        }

        return .init(
            items: items
        )
    }

    private static func pruneStaleOutputs(
        in project: ImageProject,
        configuration: ImageConfiguration,
        fileSystem: FileSystem
    ) throws -> [ImageCompressionItem] {
        guard fileSystem.exists(
            project.destination
        ) else {
            return []
        }

        let allowedDestinations = try configuredDestinationPaths(
            in: project,
            configuration: configuration
        )

        let destinationRoot = fileSystem.resolve(
            project.destination
        )

        let entries = try fileSystem.directory.entries(
            destinationRoot,
            recursive: true,
            options: [
                .skipsHiddenFiles,
            ]
        )

        var items: [ImageCompressionItem] = []

        for entry in entries where entry.kind == .file {
            let resolved = fileSystem.resolve(
                entry.url
            )

            guard !allowedDestinations.contains(
                resolved.path
            ) else {
                continue
            }

            let destination = try destinationString(
                for: resolved,
                destinationRoot: destinationRoot
            )

            try fileSystem.remove(
                resolved
            )

            items.append(
                .init(
                    source: "(pruned)",
                    destination: destination,
                    status: .pruned,
                    encoder: nil,
                    byteCount: nil,
                    errorDescription: nil
                )
            )
        }

        try removeEmptyDirectories(
            in: destinationRoot,
            fileSystem: fileSystem
        )

        return items.sorted {
            $0.destination < $1.destination
        }
    }

    private static func configuredDestinationPaths(
        in project: ImageProject,
        configuration: ImageConfiguration
    ) throws -> Set<String> {
        var destinations = Set<String>()

        for image in configuration.images {
            for output in image.outputs {
                let url = try project.destinationURL(
                    output.destination
                )
                .resolvingSymlinksInPath()
                .standardizedFileURL

                destinations.insert(
                    url.path
                )
            }
        }

        return destinations
    }

    private static func destinationString(
        for url: URL,
        destinationRoot: URL
    ) throws -> String {
        let rootComponents = destinationRoot
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .pathComponents

        let fileComponents = url
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .pathComponents

        guard fileComponents.starts(
            with: rootComponents
        ) else {
            throw ImageError.invalidPath(
                url.path
            )
        }

        let relativeComponents = Array(
            fileComponents.dropFirst(
                rootComponents.count
            )
        )

        return (
            [
                ImageProjectDefaults.destinationDirectoryName,
            ] + relativeComponents
        )
        .joined(
            separator: "/"
        )
    }

    private static func removeEmptyDirectories(
        in root: URL,
        fileSystem: FileSystem
    ) throws {
        let directories = try fileSystem.directory.entries(
            root,
            recursive: true,
            options: [
                .skipsHiddenFiles,
            ]
        )
        .filter {
            $0.kind == .directory
        }
        .map(
            \.url
        )

        for directory in directories.sorted(
            by: {
                $0.path.count > $1.path.count
            }
        ) {
            let contents = try fileSystem.directory.contents(
                directory
            )

            if contents.isEmpty {
                try fileSystem.remove(
                    directory
                )
            }
        }
    }

}
