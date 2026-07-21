import Foundation

public struct ReceivedCallContent: Equatable, Sendable {
	public let callKey: Data?
	public let conversionSource: String?
	public let conversionData: Data?
	public let conversionDelaySeconds: UInt32?
	public let ctwaSignals: String?
	public let ctwaPayload: Data?
	public let nativeFlowCallButtonPayload: String?
	public let deeplinkPayload: String?

	public init(
		callKey: Data?,
		conversionSource: String?,
		conversionData: Data?,
		conversionDelaySeconds: UInt32?,
		ctwaSignals: String?,
		ctwaPayload: Data?,
		nativeFlowCallButtonPayload: String?,
		deeplinkPayload: String?
	) {
		self.callKey = callKey
		self.conversionSource = conversionSource
		self.conversionData = conversionData
		self.conversionDelaySeconds = conversionDelaySeconds
		self.ctwaSignals = ctwaSignals
		self.ctwaPayload = ctwaPayload
		self.nativeFlowCallButtonPayload = nativeFlowCallButtonPayload
		self.deeplinkPayload = deeplinkPayload
	}
}

public struct ReceivedChatContent: Equatable, Sendable {
	public let displayName: String?
	public let id: String?

	public init(displayName: String?, id: String?) {
		self.displayName = displayName
		self.id = id
	}
}
