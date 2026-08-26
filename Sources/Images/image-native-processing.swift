import AppKit
import CoreGraphics
import FileTypes
import Foundation
import IO
import ImageIO
import PNG
import Readers
import Writers
import UniformTypeIdentifiers
import WebP

enum ImageFileData {
    static func read(
        _ url: URL
    ) throws -> Data {
        try DataFileReader(
            url
        )
        .read(
            options: .init(
                missingFilePolicy: .throwError
            )
        )
        .data
    }
}

public struct ImageEncodingRequest: Sendable {
    public let source: URL
    public let destination: URL
    public let output: ImageConfiguration.Output

    public init(
        source: URL,
        destination: URL,
        output: ImageConfiguration.Output
    ) {
        self.source = source
        self.destination = destination
        self.output = output
    }
}

public struct ImageEncodingResult: Sendable, Hashable {
    public let encoder: String
    public let destination: URL
    public let byteCount: Int64

    public init(
        encoder: String,
        destination: URL,
        byteCount: Int64
    ) {
        self.encoder = encoder
        self.destination = destination
        self.byteCount = byteCount
    }
}

public protocol ImageEncoder: Sendable {
    var identifier: String { get }

    func supports(
        _ request: ImageEncodingRequest
    ) -> Bool

    func encode(
        _ request: ImageEncodingRequest
    ) throws -> ImageEncodingResult
}

public enum ImageMetadata {
    public static func dimensions(
        of url: URL
    ) throws -> ImageSize {
        switch url.pathExtension.lowercased() {
        case "png":
            return try pngDimensions(
                of: url
            )

        case "svg":
            return try svgDimensions(
                of: url
            )

        case "webp":
            let feature = try WebPImageInspector.inspect(
                ImageFileData.read(
                    url
                )
            )

            return .init(
                width: feature.width,
                height: feature.height
            )

        default:
            let data = try ImageFileData.read(
                url
            )

            guard
                let source = CGImageSourceCreateWithData(
                    data as CFData,
                    nil
                ),
                let values = CGImageSourceCopyPropertiesAtIndex(
                    source,
                    0,
                    nil
                ) as? [CFString: Any],
                let width = values[kCGImagePropertyPixelWidth] as? NSNumber,
                let height = values[kCGImagePropertyPixelHeight] as? NSNumber
            else {
                throw ImageError.unsupportedFormat(
                    url.lastPathComponent
                )
            }

            return .init(
                width: width.intValue,
                height: height.intValue
            )
        }
    }

    private static func pngDimensions(
        of url: URL
    ) throws -> ImageSize {
        let data = try ImageFileData.read(
            url
        )

        let signature: [UInt8] = [
            0x89,
            0x50,
            0x4E,
            0x47,
            0x0D,
            0x0A,
            0x1A,
            0x0A,
        ]

        guard
            data.count >= 24,
            Array(data.prefix(8)) == signature,
            Array(
                data.dropFirst(12).prefix(4)
            ) == Array("IHDR".utf8)
        else {
            throw ImageError.imageDecodingFailed(
                url.lastPathComponent
            )
        }

        func uint32(
            at offset: Int
        ) -> UInt32 {
            let start = data.startIndex + offset

            return
                UInt32(data[start]) << 24
                | UInt32(data[start + 1]) << 16
                | UInt32(data[start + 2]) << 8
                | UInt32(data[start + 3])
        }

        let headerLength = uint32(
            at: 8
        )

        let width = uint32(
            at: 16
        )

        let height = uint32(
            at: 20
        )

        guard
            headerLength == 13,
            width > 0,
            height > 0
        else {
            throw ImageError.imageDecodingFailed(
                url.lastPathComponent
            )
        }

        return .init(
            width: Int(width),
            height: Int(height)
        )
    }

    private static func svgDimensions(
        of url: URL
    ) throws -> ImageSize {
        let text = try TextFileReader(
            url
        )
        .read()
        .text

        if
            let width = attribute(
                "width",
                in: text
            ),
            let height = attribute(
                "height",
                in: text
            )
        {
            return .init(
                width: Int(
                    width.rounded()
                ),
                height: Int(
                    height.rounded()
                )
            )
        }

        let pattern = #"\bviewBox\s*=\s*[\"']\s*[-+0-9.eE]+\s+[-+0-9.eE]+\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)"#

        guard
            let values = captures(
                pattern,
                in: text
            ),
            let width = Double(
                values[0]
            ),
            let height = Double(
                values[1]
            )
        else {
            throw ImageError.unsupportedFormat(
                url.lastPathComponent
            )
        }

        return .init(
            width: Int(
                width.rounded()
            ),
            height: Int(
                height.rounded()
            )
        )
    }

    private static func attribute(
        _ name: String,
        in text: String
    ) -> Double? {
        let pattern = #"\b"#
            + NSRegularExpression.escapedPattern(
                for: name
            )
            + #"\s*=\s*[\"']\s*([-+0-9.eE]+)"#

        return captures(
            pattern,
            in: text
        ).flatMap {
            Double(
                $0[0]
            )
        }
    }

    private static func captures(
        _ pattern: String,
        in text: String
    ) -> [String]? {
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [
                    .caseInsensitive,
                ]
            ),
            let match = expression.firstMatch(
                in: text,
                range: NSRange(
                    text.startIndex...,
                    in: text
                )
            )
        else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            Range(
                match.range(
                    at: index
                ),
                in: text
            ).map {
                String(
                    text[$0]
                )
            }
        }
    }
}

private enum NativeImage {
    static func load(
        _ url: URL
    ) throws -> CGImage {
        switch url.pathExtension.lowercased() {
        case "webp":
            return try loadWebP(
                url
            )

        case "png":
            return try loadPNG(
                url
            )

        default:
            return try loadImageIO(
                url
            )
        }
    }

    private static func loadWebP(
        _ url: URL
    ) throws -> CGImage {
        ImageWorkerDiagnostics.mark(
            "source.read.begin",
            source: url
        )

        let data = try ImageFileData.read(
            url
        )

        ImageWorkerDiagnostics.mark(
            "source.read.complete",
            source: url,
            detail: "bytes=\(data.count)"
        )

        ImageWorkerDiagnostics.mark(
            "source.decode.webp.begin",
            source: url
        )

        let image = try WebPDecoder().decodeCGImage(
            from: data,
            options: .init()
        )

        ImageWorkerDiagnostics.mark(
            "source.decode.webp.complete",
            source: url,
            detail: "size=\(image.width)x\(image.height)"
        )

        return image
    }

    private static func loadPNG(
        _ url: URL
    ) throws -> CGImage {
        ImageWorkerDiagnostics.mark(
            "source.decode.png.swift.begin",
            source: url
        )

        guard let decoded: PNG.Image = try .decompress(
            path: url.path
        ) else {
            ImageWorkerDiagnostics.mark(
                "source.decode.png.swift.open-failed",
                source: url
            )

            throw ImageError.imageDecodingFailed(
                url.lastPathComponent
            )
        }

        let width = decoded.size.x
        let height = decoded.size.y

        ImageWorkerDiagnostics.mark(
            "source.decode.png.swift.decompress-complete",
            source: url,
            detail: "size=\(width)x\(height)"
        )

        ImageWorkerDiagnostics.mark(
            "source.decode.png.swift.unpack.begin",
            source: url
        )

        let pixels: [PNG.RGBA<UInt8>] = decoded.unpack(
            as: PNG.RGBA<UInt8>.self
        )

        ImageWorkerDiagnostics.mark(
            "source.decode.png.swift.unpack.complete",
            source: url,
            detail: "pixels=\(pixels.count)"
        )

        guard
            width > 0,
            height > 0,
            width <= Int.max / height,
            pixels.count == width * height,
            pixels.count <= Int.max / 4
        else {
            throw ImageError.imageDecodingFailed(
                url.lastPathComponent
            )
        }

        var pixelData = Data(
            count: pixels.count * 4
        )

        pixelData.withUnsafeMutableBytes {
            rawBuffer in

            let bytes = rawBuffer.bindMemory(
                to: UInt8.self
            )

            for (
                index,
                pixel
            ) in pixels.enumerated() {
                let offset = index * 4

                bytes[offset] = pixel.r
                bytes[offset + 1] = pixel.g
                bytes[offset + 2] = pixel.b
                bytes[offset + 3] = pixel.a
            }
        }

        ImageWorkerDiagnostics.mark(
            "source.decode.png.cgimage.begin",
            source: url
        )

        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo
                .last
                .rawValue
        )
        .union(
            .byteOrder32Big
        )

        guard
            let provider = CGDataProvider(
                data: pixelData as CFData
            ),
            let colorSpace = CGColorSpace(
                name: CGColorSpace.sRGB
            ),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else {
            throw ImageError.imageDecodingFailed(
                url.lastPathComponent
            )
        }

        ImageWorkerDiagnostics.mark(
            "source.decode.png.cgimage.complete",
            source: url,
            detail: "size=\(image.width)x\(image.height)"
        )

        return image
    }

    private static func loadImageIO(
        _ url: URL
    ) throws -> CGImage {
        ImageWorkerDiagnostics.mark(
            "source.decode.imageio.create-source-url.begin",
            source: url
        )

        guard let imageSource = CGImageSourceCreateWithURL(
            url as CFURL,
            nil
        ) else {
            ImageWorkerDiagnostics.mark(
                "source.decode.imageio.create-source-url.failed",
                source: url
            )

            throw ImageError.imageDecodingFailed(
                url.lastPathComponent
            )
        }

        ImageWorkerDiagnostics.mark(
            "source.decode.imageio.create-source-url.complete",
            source: url
        )

        ImageWorkerDiagnostics.mark(
            "source.decode.imageio.create-image.begin",
            source: url
        )

        if let image = CGImageSourceCreateImageAtIndex(
            imageSource,
            0,
            nil
        ) {
            ImageWorkerDiagnostics.mark(
                "source.decode.imageio.create-image.complete",
                source: url,
                detail: "size=\(image.width)x\(image.height)"
            )

            return image
        }

        ImageWorkerDiagnostics.mark(
            "source.decode.appkit-url.begin",
            source: url
        )

        if
            let image = NSImage(
                contentsOf: url
            ),
            let cgImage = image.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            )
        {
            ImageWorkerDiagnostics.mark(
                "source.decode.appkit-url.complete",
                source: url,
                detail: "size=\(cgImage.width)x\(cgImage.height)"
            )

            return cgImage
        }

        ImageWorkerDiagnostics.mark(
            "source.decode.failed",
            source: url
        )

        throw ImageError.imageDecodingFailed(
            url.lastPathComponent
        )
    }

    static func resized(
        _ image: CGImage,
        resize: ImageResize?
    ) throws -> CGImage {
        ImageWorkerDiagnostics.mark(
            "resize.inspect",
            detail: "input=\(image.width)x\(image.height)"
        )

        let sourceSize = ImageSize(
            width: image.width,
            height: image.height
        )
        let targetSize = resize?.fitting(
            sourceSize
        ) ?? sourceSize
        let width = targetSize.width
        let height = targetSize.height

        let isResizing =
            width != image.width
            || height != image.height

        ImageWorkerDiagnostics.mark(
            isResizing
                ? "resize.context-create.begin"
                : "normalize.context-create.begin",
            detail: "output=\(width)x\(height)"
        )

        guard let colorSpace = CGColorSpace(
            name: CGColorSpace.sRGB
        ) else {
            throw ImageError.imageDecodingFailed(
                "sRGB color space"
            )
        }

        let bitmapInfo = CGBitmapInfo(
            rawValue:
                CGImageAlphaInfo
                    .premultipliedLast
                    .rawValue
        )
        .union(
            .byteOrder32Big
        )

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw ImageError.imageDecodingFailed(
                isResizing
                    ? "resize context"
                    : "normalization context"
            )
        }

        ImageWorkerDiagnostics.mark(
            isResizing
                ? "resize.context-create.complete"
                : "normalize.context-create.complete",
            detail:
                "output=\(width)x\(height) bytesPerRow=\(width * 4)"
        )

        context.interpolationQuality =
            isResizing
                ? .high
                : .none

        context.setBlendMode(
            .copy
        )

        context.clear(
            CGRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
        )

        ImageWorkerDiagnostics.mark(
            isResizing
                ? "resize.draw.begin"
                : "normalize.draw.begin",
            detail: "output=\(width)x\(height)"
        )

        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
        )

        ImageWorkerDiagnostics.mark(
            isResizing
                ? "resize.draw.complete"
                : "normalize.draw.complete",
            detail: "output=\(width)x\(height)"
        )

        guard let rendered = context.makeImage() else {
            throw ImageError.imageDecodingFailed(
                isResizing
                    ? "resized image"
                    : "normalized image"
            )
        }

        ImageWorkerDiagnostics.mark(
            isResizing
                ? "resize.complete"
                : "normalize.complete",
            detail:
                "output=\(rendered.width)x\(rendered.height)"
        )

        return rendered
    }
}

public struct ImageCopyEncoder: ImageEncoder {
    public let identifier = "copy"

    public init() {}

    public func supports(
        _ request: ImageEncodingRequest
    ) -> Bool {
        request.output.format == .svg
            && request.source.pathExtension.lowercased() == "svg"
    }

    public func encode(
        _ request: ImageEncodingRequest
    ) throws -> ImageEncodingResult {
        try FileSystem.default.copy(
            request.source,
            to: request.destination
        )

        return try imageEncodingResult(
            encoder: identifier,
            destination: request.destination
        )
    }
}

public struct ImageIOEncoder: ImageEncoder {
    public let identifier = "imageio"

    public init() {}

    public func supports(
        _ request: ImageEncodingRequest
    ) -> Bool {
        request.output.format != .webp
            && request.output.format != .svg
    }

    public func encode(
        _ request: ImageEncodingRequest
    ) throws -> ImageEncodingResult {
        ImageWorkerDiagnostics.mark(
            "imageio.destination-type.begin",
            source: request.source,
            destination: request.destination
        )

        let type = try destinationType(
            request.output.format
        )

        ImageWorkerDiagnostics.mark(
            "imageio.destination-type.complete",
            source: request.source,
            destination: request.destination,
            detail: "uti=\(type)"
        )

        let supported = (
            CGImageDestinationCopyTypeIdentifiers() as NSArray
        )
        .compactMap {
            $0 as? String
        }

        ImageWorkerDiagnostics.mark(
            "imageio.destination-create.begin",
            source: request.source,
            destination: request.destination
        )

        guard
            supported.contains(
                type
            ),
            let destination = CGImageDestinationCreateWithURL(
                request.destination as CFURL,
                type as CFString,
                1,
                nil
            )
        else {
            throw ImageError.unsupportedDestinationFormat(
                request.output.format.rawValue
            )
        }

        ImageWorkerDiagnostics.mark(
            "imageio.destination-create.complete",
            source: request.source,
            destination: request.destination
        )

        ImageWorkerDiagnostics.mark(
            "imageio.source-load.begin",
            source: request.source,
            destination: request.destination
        )

        let loaded = try NativeImage.load(
            request.source
        )

        ImageWorkerDiagnostics.mark(
            "imageio.source-load.complete",
            source: request.source,
            destination: request.destination
        )

        ImageWorkerDiagnostics.mark(
            "imageio.resize.begin",
            source: request.source,
            destination: request.destination
        )

        let image = try NativeImage.resized(
            loaded,
            resize: request.output.resize
        )

        ImageWorkerDiagnostics.mark(
            "imageio.resize.complete",
            source: request.source,
            destination: request.destination,
            detail: "size=\(image.width)x\(image.height)"
        )

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality:
                request.output.quality.fraction,
            kCGImageMetadataShouldExcludeGPS:
                true,
            kCGImageMetadataShouldExcludeXMP:
                true,
        ]

        ImageWorkerDiagnostics.mark(
            "imageio.add-image.begin",
            source: request.source,
            destination: request.destination
        )

        CGImageDestinationAddImage(
            destination,
            image,
            properties as CFDictionary
        )

        ImageWorkerDiagnostics.mark(
            "imageio.add-image.complete",
            source: request.source,
            destination: request.destination
        )

        ImageWorkerDiagnostics.mark(
            "imageio.finalize.begin",
            source: request.source,
            destination: request.destination
        )

        guard CGImageDestinationFinalize(destination) else {
            throw ImageError.encodingFailed(
                request.destination
            )
        }

        ImageWorkerDiagnostics.mark(
            "imageio.finalize.complete",
            source: request.source,
            destination: request.destination
        )

        return try imageEncodingResult(
            encoder: identifier,
            destination: request.destination
        )
    }

    private func destinationType(
        _ format: PhotoFile
    ) throws -> String {
        switch format {
        case .jpg, .jpeg:
            return UTType.jpeg.identifier

        case .tif, .tiff:
            return UTType.tiff.identifier

        default:
            guard let type = UTType(
                filenameExtension: format.rawValue
            ) else {
                throw ImageError.unsupportedDestinationFormat(
                    format.rawValue
                )
            }

            return type.identifier
        }
    }
}

public struct ImageWebPEncoder: ImageEncoder {
    public let identifier = "libwebp"

    public init() {}

    public func supports(
        _ request: ImageEncodingRequest
    ) -> Bool {
        request.output.format == .webp
    }

    public func encode(
        _ request: ImageEncodingRequest
    ) throws -> ImageEncodingResult {
        ImageWorkerDiagnostics.mark(
            "webp.source-load.begin",
            source: request.source,
            destination: request.destination
        )

        let image = try NativeImage.load(
            request.source
        )

        ImageWorkerDiagnostics.mark(
            "webp.source-load.complete",
            source: request.source,
            destination: request.destination
        )

        ImageWorkerDiagnostics.mark(
            "webp.resize.begin",
            source: request.source,
            destination: request.destination
        )

        let resized = try NativeImage.resized(
            image,
            resize: request.output.resize
        )

        ImageWorkerDiagnostics.mark(
            "webp.resize.complete",
            source: request.source,
            destination: request.destination,
            detail: "size=\(resized.width)x\(resized.height)"
        )

        ImageWorkerDiagnostics.mark(
            "webp.configuration",
            source: request.source,
            destination: request.destination
        )

        var configuration = WebPEncoderConfig.preset(
            .photo,
            quality: Float(
                request.output.quality.value
            )
        )

        configuration.method = 6
        configuration.threadLevel = 1
        configuration.autofilter = 1

        ImageWorkerDiagnostics.mark(
            "webp.encode.begin",
            source: request.source,
            destination: request.destination
        )

        let data = try WebPEncoder().encode(
            resized,
            config: configuration
        )

        ImageWorkerDiagnostics.mark(
            "webp.encode.complete",
            source: request.source,
            destination: request.destination,
            detail: "bytes=\(data.count)"
        )

        ImageWorkerDiagnostics.mark(
            "webp.write.begin",
            source: request.source,
            destination: request.destination
        )

        _ = try FileWriter(
            request.destination
        )
        .write(
            data,
            options: .overwriteWithoutBackup
        )

        ImageWorkerDiagnostics.mark(
            "webp.write.complete",
            source: request.source,
            destination: request.destination
        )

        return try imageEncodingResult(
            encoder: identifier,
            destination: request.destination
        )
    }
}

private func imageEncodingResult(
    encoder: String,
    destination: URL
) throws -> ImageEncodingResult {
    let metadata = try FileInspector(
        destination
    )
    .inspect()

    guard
        metadata.existed,
        let byteCount = metadata.byteCount
    else {
        throw ImageError.encodingFailed(
            destination
        )
    }

    return .init(
        encoder: encoder,
        destination: destination,
        byteCount: Int64(
            byteCount
        )
    )
}
