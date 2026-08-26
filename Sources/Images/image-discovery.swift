import FileTypes
import Foundation
import IO

public enum ImageDiscovery {
    static let supported: Set<PhotoFile> = [
        .png,
        .jpg,
        .jpeg,
        .webp,
        .gif,
        .svg,
        .tiff,
        .tif,
        .bmp,
        .avif,
    ]

    public static func sources(
        in project: ImageProject,
        fileSystem: FileSystem = .default
    ) throws -> [ImageSource] {
        guard fileSystem.exists(
            project.source
        ) else {
            throw ImageError.missingSourceDirectory(
                project.source
            )
        }

        let entries = try fileSystem.directory.entries(
            project.source,
            recursive: true,
            options: [
                .skipsHiddenFiles,
            ]
        )

        let rootComponents = fileSystem.resolve(
            project.root
        )
        .pathComponents

        return entries
            .filter {
                $0.kind == .file
            }
            .compactMap { entry in
                let url = entry.url

                guard let format = PhotoFile(
                    fileExtension: url.pathExtension
                ) else {
                    return nil
                }

                guard supported.contains(format) else {
                    return nil
                }

                let sourceComponents = fileSystem.resolve(
                    url
                )
                .pathComponents

                guard sourceComponents.starts(
                    with: rootComponents
                ) else {
                    return nil
                }

                let relative = Array(
                    sourceComponents.dropFirst(
                        rootComponents.count
                    )
                )

                return ImageSource(
                    url: url,
                    relative: ImagePath(
                        components: Array(
                            relative.dropLast()
                        ) + [
                            url.deletingPathExtension().lastPathComponent,
                        ],
                        filetype: format
                    ),
                    format: format
                )
            }
            .sorted {
                $0.relative.string < $1.relative.string
            }
    }
}
