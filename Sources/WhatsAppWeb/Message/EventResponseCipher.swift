import CryptoKit
import Foundation

public struct OutgoingEventResponseContent: Equatable, Sendable {
	public let response: OutgoingEventResponseType
	public let timestampMilliseconds: Int64
	public let extraGuestCount: Int32?

	public init(
		response: OutgoingEventResponseType,
		timestampMilliseconds: Int64,
		extraGuestCount: Int32? = nil
	) {
		self.response = response
		self.timestampMilliseconds = timestampMilliseconds
		self.extraGuestCount = extraGuestCount
	}
}

public enum OutgoingEventResponseType: Equatable, Sendable {
	case going
	case notGoing
	case maybe
}

public struct EncryptedEventResponseContent: Equatable, Sendable {
	public let encPayload: Data
	public let encIv: Data

	public init(encPayload: Data, encIv: Data) {
		self.encPayload = encPayload
		self.encIv = encIv
	}
}

public struct EventResponseCipher: Sendable {
	private let ivGenerator: @Sendable () throws -> Data

	public init(ivGenerator: @escaping @Sendable () throws -> Data = { try MessageIDGenerator.secureRandomBytes(count: 12) }) {
		self.ivGenerator = ivGenerator
	}

	public func encrypt(
		_ content: OutgoingEventResponseContent,
		eventMessageID: String,
		eventCreatorJID: String,
		responderJID: String,
		eventMessageSecret: Data
	) throws -> EncryptedEventResponseContent {
		let iv = try ivGenerator()
		var response = Proto_Message.EventResponseMessage()
		response.response = content.response.protoValue
		response.timestampMs = content.timestampMilliseconds
		if let extraGuestCount = content.extraGuestCount {
			response.extraGuestCount = extraGuestCount
		}

		let plaintext = try response.serializedData()
		let key = Self.derivedKey(
			eventMessageID: eventMessageID,
			eventCreatorJID: eventCreatorJID,
			responderJID: responderJID,
			eventMessageSecret: eventMessageSecret
		)
		let aad = Data("\(eventMessageID)\u{0000}\(responderJID)".utf8)
		let nonce = try AES.GCM.Nonce(data: iv)
		let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), nonce: nonce, authenticating: aad)
		return EncryptedEventResponseContent(encPayload: box.ciphertext + box.tag, encIv: iv)
	}

	public func decrypt(
		_ content: ReceivedEncryptedEventResponseContent,
		eventMessageID: String,
		eventCreatorJID: String,
		responderJID: String,
		eventMessageSecret: Data
	) throws -> ReceivedEventResponseContent {
		guard let encryptedPayload = content.encryptedPayload else {
			throw EventResponseCipherError.missingEncryptedPayload
		}
		guard let encryptedIV = content.encryptedIV else {
			throw EventResponseCipherError.missingEncryptedIV
		}
		guard encryptedPayload.count >= 16 else {
			throw EventResponseCipherError.invalidEncryptedPayloadLength
		}

		let key = Self.derivedKey(
			eventMessageID: eventMessageID,
			eventCreatorJID: eventCreatorJID,
			responderJID: responderJID,
			eventMessageSecret: eventMessageSecret
		)
		let aad = Data("\(eventMessageID)\u{0000}\(responderJID)".utf8)
		let nonce = try AES.GCM.Nonce(data: encryptedIV)
		let tagStart = encryptedPayload.index(encryptedPayload.endIndex, offsetBy: -16)
		let box = try AES.GCM.SealedBox(
			nonce: nonce,
			ciphertext: Data(encryptedPayload[..<tagStart]),
			tag: Data(encryptedPayload[tagStart...])
		)
		let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: aad)
		let response = try Proto_Message.EventResponseMessage(serializedBytes: plaintext)
		return ReceivedEventResponseContent(
			response: ReceivedEventResponseType(protoValue: response.response),
			timestampMilliseconds: response.hasTimestampMs ? response.timestampMs : nil,
			extraGuestCount: response.hasExtraGuestCount ? response.extraGuestCount : nil
		)
	}

	private static func derivedKey(
		eventMessageID: String,
		eventCreatorJID: String,
		responderJID: String,
		eventMessageSecret: Data
	) -> Data {
		let key0 = Data(HMAC<SHA256>.authenticationCode(
			for: eventMessageSecret,
			using: SymmetricKey(data: Data(repeating: 0, count: 32))
		))
		let sign = Data(eventMessageID.utf8)
			+ Data(eventCreatorJID.utf8)
			+ Data(responderJID.utf8)
			+ Data("Event Response".utf8)
			+ Data([1])
		return Data(HMAC<SHA256>.authenticationCode(for: sign, using: SymmetricKey(data: key0)))
	}
}

public enum EventResponseCipherError: Error, Equatable {
	case missingEncryptedPayload
	case missingEncryptedIV
	case invalidEncryptedPayloadLength
}

private extension OutgoingEventResponseType {
	var protoValue: Proto_Message.EventResponseMessage.EventResponseType {
		switch self {
		case .going:
			.going
		case .notGoing:
			.notGoing
		case .maybe:
			.maybe
		}
	}
}

private extension ReceivedEventResponseType {
	init(protoValue: Proto_Message.EventResponseMessage.EventResponseType) {
		switch protoValue {
		case .unknown:
			self = .unknown
		case .going:
			self = .going
		case .notGoing:
			self = .notGoing
		case .maybe:
			self = .maybe
		case .UNRECOGNIZED(let value):
			self = .unrecognized(value)
		}
	}
}
