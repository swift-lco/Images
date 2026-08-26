import Foundation
import Path

public struct ImageProject: Sendable {
    public let root: URL

    public init(
        root: URL
    ) {
        self.root = root.standardizedFileURL
    }

    public init(
        path: String
    ) {
        self.init(
            root: URL(
                fileURLWithPath: path,
                isDirectory: true
            )
        )
    }

    public var source: URL {
        url(
            ImagePath(
                ImageProjectDefaults.sourceDirectoryName
            )
        )
    }

    public var destination: URL {
        url(
            ImagePath(
                ImageProjectDefaults.destinationDirectoryName
            )
        )
    }

    public var configuration: URL {
        url(
            ImagePath(
                ImageProjectDefaults.configurationFilename
            )
        )
    }

    public var incrementalState: URL {
        url(
            ImagePath(
                ImageProjectDefaults.incrementalStateFilename
            )
        )
    }

    public func url(
        _ path: ImagePath
    ) -> URL {
        var url = path.value.segments.reduce(root) { url, segment in
            url.appendingPathComponent(
                segment.value
            )
        }

        if let filetype = path.value.filetype {
            url.appendPathExtension(
                filetype.base.rawValue
            )
        }

        return url.standardizedFileURL
    }

    public func sourceURL(
        _ path: ImagePath
    ) throws -> URL {
        try sourceURL(
            path.string
        )
    }

    public func sourceURL(
        _ rawPath: String
    ) throws -> URL {
        try scopedURL(
            rawPath,
            requiredDirectory: ImageProjectDefaults.sourceDirectoryName
        )
    }

    public func destinationURL(
        _ path: ImagePath
    ) throws -> URL {
        try destinationURL(
            path.string
        )
    }

    public func destinationURL(
        _ rawPath: String
    ) throws -> URL {
        try scopedURL(
            rawPath,
            requiredDirectory: ImageProjectDefaults.destinationDirectoryName
        )
    }

    private func scopedURL(
        _ rawPath: String,
        requiredDirectory: String
    ) throws -> URL {
        let scope = try PathAccessScope(
            root: root,
            policy: .allowAll
        )

        let scoped = try scope.resolve(
            rawPath: rawPath,
            type: .file
        )

        guard scoped.relative.segments.first?.value == requiredDirectory else {
            throw ImageError.invalidPath(
                rawPath
            )
        }

        return try scope.absoluteURL(
            for: scoped,
            type: .file
        )
    }
}
