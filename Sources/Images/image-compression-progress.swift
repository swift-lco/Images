public struct ImageCompressionProgress:
    Sendable,
    Hashable
{
    public let completedCount: Int
    public let totalCount: Int
    public let item: ImageCompressionItem

    public init(
        completedCount: Int,
        totalCount: Int,
        item: ImageCompressionItem
    ) {
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.item = item
    }
}
