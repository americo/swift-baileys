public struct ReceivedAlbumContent: Equatable, Sendable {
	public let expectedImageCount: UInt32?
	public let expectedVideoCount: UInt32?

	public init(expectedImageCount: UInt32?, expectedVideoCount: UInt32?) {
		self.expectedImageCount = expectedImageCount
		self.expectedVideoCount = expectedVideoCount
	}
}
