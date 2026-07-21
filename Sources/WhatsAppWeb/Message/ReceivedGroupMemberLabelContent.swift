public struct ReceivedGroupMemberLabelChangeContent: Equatable, Sendable {
	public let label: String?
	public let labelTimestamp: Int64?

	public init(
		label: String?,
		labelTimestamp: Int64?
	) {
		self.label = label
		self.labelTimestamp = labelTimestamp
	}
}
