public struct GroupMemberLabelUpdate: Equatable, Sendable {
	public let groupID: String
	public let label: String
	public let participant: String?
	public let participantAlt: String?
	public let messageTimestamp: UInt64?

	public init(
		groupID: String,
		label: String,
		participant: String?,
		participantAlt: String?,
		messageTimestamp: UInt64?
	) {
		self.groupID = groupID
		self.label = label
		self.participant = participant
		self.participantAlt = participantAlt
		self.messageTimestamp = messageTimestamp
	}
}
