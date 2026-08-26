import CryptoKit
import Foundation
import IO
import Readers
import Writers

struct ImageIncrementalPlan {
    let encoder: any ImageEncoder
    let fingerprint: String
    let byteCount: Int64?
    let isCurrent: Bool
}

struct ImageIncrementalSession {
    private var state: State
    private var sourceDigests: [String: String] = [:]

    init(
        project: ImageProject
    ) {
        state = State.read(
            from: project.incrementalState
        )
    }

    mutating func plan(
        sourcePath: String,
        source: URL,
        destination: URL,
        output: ImageConfiguration.Output,
        encoders: [any ImageEncoder]
    ) throws -> ImageIncrementalPlan {
        let request = ImageEncodingRequest(
            source: source,
            destination: destination,
            output: output
        )

        guard let encoder = encoders.first(where: {
            $0.supports(
                request
            )
        }) else {
            throw ImageError.unsupportedDestinationFormat(
                output.format.rawValue
            )
        }

        let sourceKey = source.standardizedFileURL.path

        let sourceDigest = try sourceDigests[sourceKey] ?? {
            let value = digest(
                try ImageFileData.read(
                    source
                )
            )

            sourceDigests[sourceKey] = value

            return value
        }()

        let fingerprint = digest(
            Data(
                [
                    String(
                        ImageProjectDefaults.incrementalFingerprintVersion
                    ),
                    sourcePath,
                    sourceDigest,
                    output.destination.string,
                    output.format.rawValue,
                    output.resize?.maxWidth.map(
                        String.init
                    ) ?? "-",
                    output.resize?.maxHeight.map(
                        String.init
                    ) ?? "-",
                    String(
                        output.quality.value
                    ),
                    encoder.identifier,
                ]
                .joined(
                    separator: "\0"
                )
                .utf8
            )
        )

        let recorded = state.outputs[
            output.destination.string
        ]

        let current = try? OutputState(
            destination: destination,
            fingerprint: fingerprint
        )

        let isCurrent: Bool

        if let recorded, let current {
            isCurrent = recorded == current
        } else {
            isCurrent = false
        }

        return .init(
            encoder: encoder,
            fingerprint: fingerprint,
            byteCount: recorded?.byteCount,
            isCurrent: isCurrent
        )
    }

    mutating func record(
        _ plan: ImageIncrementalPlan,
        destination: URL,
        destinationPath: String
    ) throws {
        state.outputs[
            destinationPath
        ] = try .init(
            destination: destination,
            fingerprint: plan.fingerprint
        )
    }

    mutating func retain(
        configuration: ImageConfiguration
    ) {
        let destinations = Set(
            configuration.images.flatMap {
                $0.outputs.map {
                    $0.destination.string
                }
            }
        )

        state.outputs = state.outputs.filter {
            destinations.contains(
                $0.key
            )
        }
    }

    func write(
        to url: URL
    ) throws {
        try state.write(
            to: url
        )
    }

    private func digest(
        _ data: Data
    ) -> String {
        SHA256.hash(
            data: data
        )
        .map {
            String(
                format: "%02x",
                $0
            )
        }
        .joined()
    }
}

private struct State: Codable {
    static let version = 1

    var schema: Int = version
    var outputs: [String: OutputState] = [:]

    static func read(
        from url: URL
    ) -> Self {
        guard
            FileSystem.default.exists(
                url
            ),
            let data = try? DataFileReader(
                url
            )
            .read()
            .data,
            let value = try? JSONDecoder().decode(
                Self.self,
                from: data
            ),
            value.schema == version
        else {
            return .init()
        }

        return value
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
}

private struct OutputState:
    Codable,
    Equatable
{
    let fingerprint: String
    let byteCount: Int64
    let modificationMicroseconds: Int64

    init(
        destination: URL,
        fingerprint: String
    ) throws {
        let metadata = try FileInspector(
            destination
        )
        .inspect()

        guard
            metadata.existed,
            let size = metadata.byteCount,
            let date = metadata.modifiedAt
        else {
            throw ImageError.encodingFailed(
                destination
            )
        }

        self.fingerprint = fingerprint

        byteCount = Int64(
            size
        )

        modificationMicroseconds = Int64(
            (
                date.timeIntervalSince1970
                    * 1_000_000
            )
            .rounded()
        )
    }
}
