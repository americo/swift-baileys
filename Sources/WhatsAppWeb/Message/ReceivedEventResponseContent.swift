import Foundation

public struct ReceivedEventResponseContent: Equatable, Sendable {
	public let response: ReceivedEventResponseType
	public let timestampMilliseconds: Int64?
	public let extraGuestCount: Int32?

	public init(
		response: ReceivedEventResponseType,
		timestampMilliseconds: Int64?,
		extraGuestCount: Int32? = nil
	) {
		self.response = response
		self.timestampMilliseconds = timestampMilliseconds
		self.extraGuestCount = extraGuestCount
	}
}

public enum ReceivedEventResponseType: Equatable, Sendable {
	case unknown
	case going
	case notGoing
	case maybe
	case unrecognized(Int)
}

public struct ReceivedEncryptedEventResponseContent: Equatable, Sendable {
	public let eventCreationMessageKey: ReceivedMessageKey?
	public let encryptedPayload: Data?
	public let encryptedIV: Data?

	public init(
		eventCreationMessageKey: ReceivedMessageKey?,
		encryptedPayload: Data?,
		encryptedIV: Data?
	) {
		self.eventCreationMessageKey = eventCreationMessageKey
		self.encryptedPayload = encryptedPayload
		self.encryptedIV = encryptedIV
	}
}

public struct ReceivedMessageEventResponseUpdate: Equatable, Sendable {
	public let key: WhatsAppMessageKey
	public let eventResponseMessageKey: WhatsAppMessageKey
	public let encryptedPayload: Data?
	public let encryptedIV: Data?
	public let response: ReceivedEventResponseContent?

	public init(
		key: WhatsAppMessageKey,
		eventResponseMessageKey: WhatsAppMessageKey,
		encryptedPayload: Data?,
		encryptedIV: Data?,
		response: ReceivedEventResponseContent? = nil
	) {
		self.key = key
		self.eventResponseMessageKey = eventResponseMessageKey
		self.encryptedPayload = encryptedPayload
		self.encryptedIV = encryptedIV
		self.response = response
	}
}

public struct EventResponseDecryptionContext: Equatable, Sendable {
	public let eventMessageID: String
	public let eventCreatorJID: String
	public let responderJID: String
	public let eventMessageSecret: Data

	public init(eventMessageID: String, eventCreatorJID: String, responderJID: String, eventMessageSecret: Data) {
		self.eventMessageID = eventMessageID
		self.eventCreatorJID = eventCreatorJID
		self.responderJID = responderJID
		self.eventMessageSecret = eventMessageSecret
	}
}

public protocol EventResponseContextResolving: Sendable {
	func context(
		for key: WhatsAppMessageKey,
		responseMessageKey: WhatsAppMessageKey
	) async throws -> EventResponseDecryptionContext?
}
