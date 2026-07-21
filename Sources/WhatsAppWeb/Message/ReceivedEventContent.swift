import Foundation

public struct ReceivedEventContent: Equatable, Sendable {
	public let name: String?
	public let description: String?
	public let startTime: Int64?
	public let endTime: Int64?
	public let joinLink: String?
	public let isCanceled: Bool?
	public let extraGuestsAllowed: Bool?
	public let isScheduledCall: Bool?
	public let location: ReceivedLocationContent?

	public init(
		name: String?,
		description: String?,
		startTime: Int64?,
		endTime: Int64?,
		joinLink: String?,
		isCanceled: Bool?,
		extraGuestsAllowed: Bool?,
		isScheduledCall: Bool?,
		location: ReceivedLocationContent?
	) {
		self.name = name
		self.description = description
		self.startTime = startTime
		self.endTime = endTime
		self.joinLink = joinLink
		self.isCanceled = isCanceled
		self.extraGuestsAllowed = extraGuestsAllowed
		self.isScheduledCall = isScheduledCall
		self.location = location
	}
}
