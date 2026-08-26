import Foundation
import IO
import PNG

public struct ImagePNGEncoder: ImageEncoder {
    public let identifier = "swift-png"

    public init() {}

    public func supports(
        _ request: ImageEncodingRequest
    ) -> Bool {
        request.output.format == .png
            && request.source.pathExtension.lowercased() == "png"
    }

    public func encode(
        _ request: ImageEncodingRequest
    ) throws -> ImageEncodingResult {
        ImageWorkerDiagnostics.mark(
            "png.decode.begin",
            source: request.source,
            destination: request.destination
        )

        guard let decoded: PNG.Image = try .decompress(
            path: request.source.path
        ) else {
            throw ImageError.imageDecodingFailed(
                request.source.lastPathComponent
            )
        }

        let sourceWidth = decoded.size.x
        let sourceHeight = decoded.size.y

        guard
            sourceWidth > 0,
            sourceHeight > 0,
            sourceWidth <= Int.max / sourceHeight
        else {
            throw ImageError.imageDecodingFailed(
                request.source.lastPathComponent
            )
        }

        ImageWorkerDiagnostics.mark(
            "png.decode.complete",
            source: request.source,
            destination: request.destination,
            detail: "size=\(sourceWidth)x\(sourceHeight)"
        )

        let sourceSize = ImageSize(
            width: sourceWidth,
            height: sourceHeight
        )
        let targetSize = request.output.resize?.fitting(
            sourceSize
        ) ?? sourceSize
        let targetWidth = targetSize.width
        let targetHeight = targetSize.height

        let outputImage: PNG.Image

        if targetSize == sourceSize {
            outputImage = decoded
        } else {

            ImageWorkerDiagnostics.mark(
                "png.resize.begin",
                source: request.source,
                destination: request.destination,
                detail: "size=\(targetWidth)x\(targetHeight)"
            )

            let sourcePixels: [PNG.RGBA<UInt8>] = decoded.unpack(
                as: PNG.RGBA<UInt8>.self
            )

            guard sourcePixels.count == sourceWidth * sourceHeight else {
                throw ImageError.imageDecodingFailed(
                    request.source.lastPathComponent
                )
            }

            let targetPixels = resized(
                sourcePixels,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetWidth: targetWidth,
                targetHeight: targetHeight
            )

            outputImage = PNG.Image(
                packing: targetPixels,
                size: (
                    x: targetWidth,
                    y: targetHeight
                ),
                layout: .init(
                    format: .rgba8(
                        palette: [],
                        fill: nil
                    )
                )
            )

            ImageWorkerDiagnostics.mark(
                "png.resize.complete",
                source: request.source,
                destination: request.destination,
                detail: "size=\(targetWidth)x\(targetHeight)"
            )
        }

        ImageWorkerDiagnostics.mark(
            "png.encode.begin",
            source: request.source,
            destination: request.destination
        )

        try outputImage.compress(
            path: request.destination.path,
            level: 9
        )

        ImageWorkerDiagnostics.mark(
            "png.encode.complete",
            source: request.source,
            destination: request.destination
        )

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

    private func resized(
        _ source: [PNG.RGBA<UInt8>],
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) -> [PNG.RGBA<UInt8>] {
        let scaleX = Double(sourceWidth) / Double(targetWidth)
        let scaleY = Double(sourceHeight) / Double(targetHeight)

        var target: [PNG.RGBA<UInt8>] = []
        target.reserveCapacity(
            targetWidth * targetHeight
        )

        for targetY in 0..<targetHeight {
            let sourceY = clampedCoordinate(
                (Double(targetY) + 0.5) * scaleY - 0.5,
                upperBound: sourceHeight - 1
            )

            let y0 = Int(
                sourceY.rounded(
                    .down
                )
            )
            let y1 = min(
                y0 + 1,
                sourceHeight - 1
            )
            let yFraction = sourceY - Double(y0)

            for targetX in 0..<targetWidth {
                let sourceX = clampedCoordinate(
                    (Double(targetX) + 0.5) * scaleX - 0.5,
                    upperBound: sourceWidth - 1
                )

                let x0 = Int(
                    sourceX.rounded(
                        .down
                    )
                )
                let x1 = min(
                    x0 + 1,
                    sourceWidth - 1
                )
                let xFraction = sourceX - Double(x0)

                let top = PremultipliedPixel.interpolate(
                    PremultipliedPixel(
                        source[
                            y0 * sourceWidth + x0
                        ]
                    ),
                    PremultipliedPixel(
                        source[
                            y0 * sourceWidth + x1
                        ]
                    ),
                    fraction: xFraction
                )

                let bottom = PremultipliedPixel.interpolate(
                    PremultipliedPixel(
                        source[
                            y1 * sourceWidth + x0
                        ]
                    ),
                    PremultipliedPixel(
                        source[
                            y1 * sourceWidth + x1
                        ]
                    ),
                    fraction: xFraction
                )

                target.append(
                    PremultipliedPixel.interpolate(
                        top,
                        bottom,
                        fraction: yFraction
                    )
                    .rgba
                )
            }
        }

        return target
    }

    private func clampedCoordinate(
        _ value: Double,
        upperBound: Int
    ) -> Double {
        min(
            max(
                value,
                0
            ),
            Double(
                upperBound
            )
        )
    }
}

private struct PremultipliedPixel {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(
        _ pixel: PNG.RGBA<UInt8>
    ) {
        alpha = Double(pixel.a) / 255
        red = Double(pixel.r) / 255 * alpha
        green = Double(pixel.g) / 255 * alpha
        blue = Double(pixel.b) / 255 * alpha
    }

    private init(
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    static func interpolate(
        _ first: Self,
        _ second: Self,
        fraction: Double
    ) -> Self {
        let inverse = 1 - fraction

        return .init(
            red: first.red * inverse
                + second.red * fraction,
            green: first.green * inverse
                + second.green * fraction,
            blue: first.blue * inverse
                + second.blue * fraction,
            alpha: first.alpha * inverse
                + second.alpha * fraction
        )
    }

    var rgba: PNG.RGBA<UInt8> {
        guard alpha > 0 else {
            return .init(
                0,
                0,
                0,
                0
            )
        }

        return .init(
            channel(
                red / alpha
            ),
            channel(
                green / alpha
            ),
            channel(
                blue / alpha
            ),
            channel(
                alpha
            )
        )
    }

    private func channel(
        _ value: Double
    ) -> UInt8 {
        UInt8(
            min(
                max(
                    Int(
                        (
                            value * 255
                        )
                        .rounded()
                    ),
                    0
                ),
                255
            )
        )
    }
}
