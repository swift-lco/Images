import Darwin
import Dispatch
import Foundation
import IO
import Processes

enum ImageWorkerDiagnostics {
    static let environmentKey = "IMAGES_WORKER_DIAGNOSTICS"

    static var enabled: Bool {
        ProcessInfo.processInfo.environment[
            environmentKey
        ] == "1"
    }

    static func mark(
        _ stage: String,
        source: URL? = nil,
        destination: URL? = nil,
        detail: String? = nil
    ) {
        guard enabled else {
            return
        }

        var fields = [
            "[images-worker]",
            "stage=\(stage)",
        ]

        if let source {
            fields.append(
                "source=\(source.path)"
            )
        }

        if let destination {
            fields.append(
                "destination=\(destination.path)"
            )
        }

        if let detail {
            fields.append(
                detail
            )
        }

        FileHandle.standardError.write(
            Data(
                (
                    fields.joined(
                        separator: " "
                    ) + "\n"
                )
                .utf8
            )
        )
    }
}

public enum ImageIsolatedEncoderKind:
    String,
    Codable,
    Sendable
{
    case imageIO = "imageio"
    case png = "swift-png"
    case webP = "libwebp"

    public var identifier: String {
        rawValue
    }

    fileprivate func supports(
        _ request: ImageEncodingRequest
    ) -> Bool {
        switch self {
        case .imageIO:
            return request.output.format != .webp
                && request.output.format != .svg

        case .png:
            return request.output.format == .png
                && request.source.pathExtension.lowercased() == "png"

        case .webP:
            return request.output.format == .webp
        }
    }

    fileprivate func encoder() -> any ImageEncoder {
        switch self {
        case .imageIO:
            return ImageIOEncoder()

        case .png:
            return ImagePNGEncoder()

        case .webP:
            return ImageWebPEncoder()
        }
    }
}

public struct ImageIsolatedEncodingPayload:
    Codable,
    Sendable
{
    public let encoder: ImageIsolatedEncoderKind
    public let source: URL
    public let destination: URL
    public let output: ImageConfiguration.Output

    public init(
        encoder: ImageIsolatedEncoderKind,
        source: URL,
        destination: URL,
        output: ImageConfiguration.Output
    ) {
        self.encoder = encoder
        self.source = source
        self.destination = destination
        self.output = output
    }
}

public struct ImageIsolatedEncoder: ImageEncoder {
    public let kind: ImageIsolatedEncoderKind
    public let executableURL: URL

    public var identifier: String {
        kind.identifier
    }

    public init(
        kind: ImageIsolatedEncoderKind,
        executableURL: URL
    ) {
        self.kind = kind
        self.executableURL = executableURL.standardizedFileURL
    }

    public func supports(
        _ request: ImageEncodingRequest
    ) -> Bool {
        kind.supports(
            request
        )
    }

    public func encode(
        _ request: ImageEncodingRequest
    ) throws -> ImageEncodingResult {
        let payload = ImageIsolatedEncodingPayload(
            encoder: kind,
            source: request.source,
            destination: request.destination,
            output: request.output
        )

        let encodedRequest = try JSONEncoder()
            .encode(
                payload
            )
            .base64EncodedString()

        let specification = ProcessSpecification(
            executable: .path(
                executableURL.path
            ),
            arguments: [
                "_encode-worker",
                "--request",
                encodedRequest,
            ],
            environment: .inheritedUpdating(
                [
                    ImageWorkerDiagnostics.environmentKey:
                        "1",
                ]
            )
        )

        let startedAt = Date()

        let process = try ImageProcessBridge.run(
            specification
        )

        let elapsed = Date().timeIntervalSince(
            startedAt
        )

        var diagnosticData = process.stdout

        diagnosticData.append(
            process.stderr
        )

        let diagnostics = String(
            decoding: diagnosticData,
            as: UTF8.self
        )

        guard process.isSuccess else {
            throw ImageIsolatedEncodingError(
                encoder: identifier,
                source: request.source,
                destination: request.destination,
                output: request.output,
                exit: process.exit,
                elapsed: elapsed,
                diagnostics: diagnostics
            )
        }

        let metadata = try FileInspector(
            request.destination
        )
        .inspect()

        guard
            metadata.existed,
            let byteCount = metadata.byteCount
        else {
            throw ImageError.encodingFailed(
                request.destination
            )
        }

        return .init(
            encoder: identifier,
            destination: request.destination,
            byteCount: Int64(
                byteCount
            )
        )
    }

    public static func standard(
        executableURL: URL
    ) -> [any ImageEncoder] {
        [
            ImageCopyEncoder(),
            ImageIsolatedEncoder(
                kind: .webP,
                executableURL: executableURL
            ),
            ImageIsolatedEncoder(
                kind: .png,
                executableURL: executableURL
            ),
            ImageIsolatedEncoder(
                kind: .imageIO,
                executableURL: executableURL
            ),
        ]
    }
}

public enum ImageEncodingWorker {
    @discardableResult
    public static func encode(
        _ payload: ImageIsolatedEncodingPayload
    ) throws -> ImageEncodingResult {
        let encoder = payload.encoder.encoder()

        let request = ImageEncodingRequest(
            source: payload.source,
            destination: payload.destination,
            output: payload.output
        )

        guard encoder.supports(request) else {
            throw ImageError.unsupportedDestinationFormat(
                payload.output.format.rawValue
            )
        }

        return try encoder.encode(
            request
        )
    }
}

private struct ImageIsolatedEncodingError:
    Error,
    LocalizedError,
    ImageFailureRepresentable
{
    let encoder: String
    let source: URL
    let destination: URL
    let output: ImageConfiguration.Output
    let exit: ProcessExit
    let elapsed: TimeInterval
    let diagnostics: String

    var imageFailureCategory: ImageFailureCategory {
        guard let lastStage else {
            return .workerRuntime
        }

        if lastStage.hasPrefix(
            "source."
        )
            || lastStage.hasPrefix(
                "png.decode"
            )
            || lastStage.contains(
                ".source-load"
            )
        {
            return .sourceDecoding
        }

        if lastStage.hasPrefix(
            "resize."
        )
            || lastStage.contains(
                ".resize"
            )
        {
            return .resizing
        }

        if lastStage.hasPrefix(
            "imageio."
        )
            || lastStage.hasPrefix(
                "png.encode"
            )
            || lastStage.hasPrefix(
                "webp."
            )
        {
            return .outputEncoding
        }

        return .workerRuntime
    }

    var imageFailureSummary: String {
        switch exit {
        case .signaled(let signal):
            return """
            \(operationLabel) crashed with \
            \(signalName(signal)) \
            (\(signal)).
            """

        case .exited(let status):
            return """
            \(operationLabel) failed with worker exit status \
            \(status).
            """
        }
    }

    var errorDescription: String? {
        var lines = [
            failureHeading,
            "  category: \(imageFailureCategory.label)",
            "  cause: \(imageFailureSummary)",
            "  source: \(source.path)",
            "  destination: \(destination.path)",
            "  format: \(source.pathExtension.lowercased()) -> \(output.format.rawValue)",
            "  resize: \(output.resize?.description ?? "original")",
            "  quality: \(output.quality.value)",
            "  elapsed: \(String(format: "%.3f", elapsed)) seconds",
        ]

        if let lastStage {
            lines.append(
                "  last stage: \(lastStage)"
            )
        }

        let diagnosticLines = diagnostics
            .split(
                whereSeparator: {
                    $0.isNewline
                }
            )
            .map(
                String.init
            )
            .filter {
                !$0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
            }

        if !diagnosticLines.isEmpty {
            lines.append(
                "  worker diagnostics:"
            )

            lines.append(
                contentsOf: diagnosticLines.map {
                    "    \($0)"
                }
            )
        }

        return lines.joined(
            separator: "\n"
        )
    }

    private var failureHeading: String {
        switch exit {
        case .signaled(let signal):
            return """
            Isolated \(encoder) worker terminated by \
            \(signalName(signal)) \
            (\(signal): \(signalDescription(signal))).
            """

        case .exited(let status):
            return """
            Isolated \(encoder) worker exited with status \
            \(status).
            """
        }
    }

    private var operationLabel: String {
        guard let lastStage else {
            return "\(encoder) worker"
        }

        if lastStage.hasPrefix(
            "source.decode"
        )
            || lastStage.hasPrefix(
                "png.decode"
            )
            || lastStage.contains(
                ".source-load"
            )
        {
            return "Source decoding"
        }

        if lastStage.hasPrefix(
            "resize."
        )
            || lastStage.contains(
                ".resize"
            )
        {
            return "Image resizing"
        }

        if lastStage.hasPrefix(
            "imageio.finalize"
        ) {
            return "ImageIO output finalization"
        }

        if lastStage.hasPrefix(
            "imageio.add-image"
        ) {
            return "ImageIO output assembly"
        }

        if lastStage.hasPrefix(
            "imageio.destination"
        ) {
            return "ImageIO destination setup"
        }

        if lastStage.hasPrefix(
            "png.encode"
        ) {
            return "PNG encoding"
        }

        if lastStage.hasPrefix(
            "webp.encode"
        ) {
            return "WebP encoding"
        }

        if lastStage.hasPrefix(
            "webp.write"
        ) {
            return "WebP output writing"
        }

        return "\(encoder) worker"
    }

    private var lastStage: String? {
        let lines = diagnostics.split(
            whereSeparator: {
                $0.isNewline
            }
        )

        for line in lines.reversed() {
            let fields = line.split(
                separator: " "
            )

            guard let stage = fields.first(
                where: {
                    $0.hasPrefix(
                        "stage="
                    )
                }
            ) else {
                continue
            }

            return String(
                stage.dropFirst(
                    "stage=".count
                )
            )
        }

        return nil
    }

    private func signalName(
        _ signal: Int32
    ) -> String {
        switch signal {
        case SIGABRT:
            return "SIGABRT"

        case SIGBUS:
            return "SIGBUS"

        case SIGFPE:
            return "SIGFPE"

        case SIGILL:
            return "SIGILL"

        case SIGKILL:
            return "SIGKILL"

        case SIGSEGV:
            return "SIGSEGV"

        case SIGTERM:
            return "SIGTERM"

        case SIGTRAP:
            return "SIGTRAP"

        default:
            return "SIGNAL"
        }
    }

    private func signalDescription(
        _ signal: Int32
    ) -> String {
        guard let value = strsignal(
            signal
        ) else {
            return "unknown signal"
        }

        return String(
            cString: value
        )
    }
}

private enum ImageProcessBridge {
    static func run(
        _ specification: ProcessSpecification
    ) throws -> ProcessResult {
        let state = State()

        Task.detached {
            do {
                state.complete(
                    .success(
                        try await ProcessRunner().run(
                            specification
                        )
                    )
                )
            } catch {
                state.complete(
                    .failure(
                        error
                    )
                )
            }
        }

        return try state.wait()
    }

    private final class State:
        @unchecked Sendable
    {
        private let lock = NSLock()

        private let semaphore = DispatchSemaphore(
            value: 0
        )

        private var result:
            Result<
                ProcessResult,
                any Error
            >?

        func complete(
            _ result: Result<
                ProcessResult,
                any Error
            >
        ) {
            lock.lock()

            self.result = result

            lock.unlock()

            semaphore.signal()
        }

        func wait() throws -> ProcessResult {
            semaphore.wait()

            lock.lock()

            let result = self.result

            lock.unlock()

            guard let result else {
                preconditionFailure(
                    "Image worker execution completed without a process result."
                )
            }

            return try result.get()
        }
    }
}

