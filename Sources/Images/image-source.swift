import FileTypes
import Foundation

public struct ImageSource: Sendable {
    public let url: URL
    public let relative: ImagePath
    public let format: PhotoFile

    public init(
        url: URL,
        relative: ImagePath,
        format: PhotoFile
    ) {
        self.url = url.standardizedFileURL
        self.relative = relative
        self.format = format
    }
}
