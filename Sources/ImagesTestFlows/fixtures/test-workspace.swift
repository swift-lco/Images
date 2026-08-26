import Foundation

struct TestWorkspace {
    let root: URL

    var raw: URL {
        root.appendingPathComponent(
            "raw",
            isDirectory: true
        )
    }

    var compressed: URL {
        root.appendingPathComponent(
            "compressed",
            isDirectory: true
        )
    }

    var configuration: URL {
        root.appendingPathComponent(
            "simg-config.json",
            isDirectory: false
        )
    }

    init(
        name: String,
        fileManager: FileManager = .default
    ) throws {
        let safeName = name
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber
                    ? character
                    : "-"
            }
            .reduce(into: "") { result, character in
                result.append(character)
            }

        root = fileManager.temporaryDirectory
            .appendingPathComponent(
                "swift-imagery-testflows",
                isDirectory: true
            )
            .appendingPathComponent(
                "\(safeName)-\(UUID().uuidString)",
                isDirectory: true
            )

        try fileManager.createDirectory(
            at: raw,
            withIntermediateDirectories: true
        )

        try fileManager.createDirectory(
            at: compressed,
            withIntermediateDirectories: true
        )
    }

    @discardableResult
    func write(
        _ data: Data,
        relativePath: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let destination = root.appendingPathComponent(
            relativePath,
            isDirectory: false
        )

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard !fileManager.fileExists(
            atPath: destination.path
        ) else {
            throw CocoaError(
                .fileWriteFileExists
            )
        }

        try data.write(
            to: destination,
            options: .atomic
        )

        return destination
    }

    func remove(
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(
            atPath: root.path
        ) else {
            return
        }

        try fileManager.removeItem(
            at: root
        )
    }
}
