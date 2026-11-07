import Foundation

/// A reaction someone sent during a group call.
public struct CallParticipantReaction: Equatable, Sendable {
	/// The device's id in the call's keys.
	public let participantID: String
	public let userJID: String
	/// `nil` takes back their last reaction.
	public let emoji: String?

	public init(participantID: String, userJID: String, emoji: String?) {
		self.participantID = participantID
		self.userJID = userJID
		self.emoji = emoji
	}
}

public enum CallAppDataError: Error, Equatable, Sendable {
	case malformed
	case tooLarge
	case invalidText
	case missingTransaction
}

/// What a group call's app data stream carries, on its own SSRC: nested protobuf holding one reaction
/// per message, each numbered so a receiver can drop the repeats its sender makes of it.
enum CallAppData {
	static let payloadType: UInt8 = 119
	static let timestampStride: UInt32 = 50
	/// The captured sender sends each reaction ten times, 50 ms apart.
	static let sendCount = 10
	static let resendInterval: Duration = .milliseconds(50)

	static let maxPayloadBytes = 4096
	static let maxReactionBytes = 256

	struct Reaction: Equatable {
		let transactionID: UInt64
		let emoji: String
	}

	/// An empty `emoji` takes back the sender's last reaction.
	static func encode(transactionID: UInt64, emoji: String) throws -> Data {
		guard transactionID != 0 else {
			throw CallAppDataError.missingTransaction
		}

		let text = Data(emoji.utf8)
		guard text.count <= maxReactionBytes else {
			throw CallAppDataError.tooLarge
		}

		var reaction = Data()
		appendVarint(1 << 3, to: &reaction)
		appendVarint(transactionID, to: &reaction)
		appendBytes(text, field: 2, to: &reaction)

		var message = Data()
		appendBytes(reaction, field: 1, to: &message)
		var payload = Data()
		appendBytes(message, field: 1, to: &payload)
		return payload
	}

	/// Unknown fields are skipped, so a later kind of message does not stop the reactions around it.
	static func decode(_ payload: Data) throws -> [Reaction] {
		guard payload.count <= maxPayloadBytes else {
			throw CallAppDataError.tooLarge
		}

		var reactions = [Reaction]()
		try visitFields(payload) { field, wire, value in
			guard field == 1, wire == 2 else {
				return
			}
			if let reaction = try decodeMessage(bytesValue(value)) {
				reactions.append(reaction)
			}
		}
		return reactions
	}

	private static func decodeMessage(_ message: Data) throws -> Reaction? {
		var result: Reaction?
		try visitFields(message) { field, wire, value in
			if result == nil, field == 1, wire == 2 {
				result = try decodeReaction(bytesValue(value))
			}
		}
		return result
	}

	private static func decodeReaction(_ message: Data) throws -> Reaction {
		var transactionID: UInt64 = 0
		var emoji = ""
		try visitFields(message) { field, wire, value in
			switch (field, wire) {
			case (1, 0):
				transactionID = try consumeVarint(value).value
			case (2, 2):
				let bytes = try bytesValue(value)
				guard bytes.count <= maxReactionBytes else {
					throw CallAppDataError.tooLarge
				}
				guard let text = String(data: bytes, encoding: .utf8) else {
					throw CallAppDataError.invalidText
				}
				emoji = text
			default:
				break
			}
		}
		guard transactionID != 0 else {
			throw CallAppDataError.missingTransaction
		}

		return Reaction(transactionID: transactionID, emoji: emoji)
	}

	/// Gives each field's raw value, with its length prefix if it has one.
	private static func visitFields(_ input: Data, visit: (UInt64, UInt8, Data) throws -> Void) throws {
		var data = Data(input)
		while !data.isEmpty {
			let (key, keyLength) = try consumeVarint(data)
			data = data.dropFirst(keyLength)
			let field = key >> 3
			let wire = UInt8(key & 7)
			guard field != 0 else {
				throw CallAppDataError.malformed
			}

			let valueLength: Int
			switch wire {
			case 0:
				valueLength = try consumeVarint(data).length
			case 1:
				valueLength = 8
			case 2:
				let (length, prefix) = try consumeVarint(data)
				guard length <= UInt64(maxPayloadBytes) else {
					throw CallAppDataError.tooLarge
				}
				valueLength = prefix + Int(length)
			case 5:
				valueLength = 4
			default:
				throw CallAppDataError.malformed
			}
			guard data.count >= valueLength else {
				throw CallAppDataError.malformed
			}

			try visit(field, wire, Data(data.prefix(valueLength)))
			data = data.dropFirst(valueLength)
		}
	}

	private static func bytesValue(_ value: Data) throws -> Data {
		let (length, prefix) = try consumeVarint(value)
		guard length <= UInt64(maxPayloadBytes), value.count >= prefix + Int(length) else {
			throw CallAppDataError.malformed
		}

		return Data(value.dropFirst(prefix).prefix(Int(length)))
	}

	private static func consumeVarint(_ data: Data) throws -> (value: UInt64, length: Int) {
		var value: UInt64 = 0
		for (index, byte) in data.prefix(10).enumerated() {
			if index == 9, byte > 1 {
				throw CallAppDataError.malformed
			}
			value |= UInt64(byte & 0x7f) << UInt64(index * 7)
			if byte & 0x80 == 0 {
				return (value, index + 1)
			}
		}
		throw CallAppDataError.malformed
	}

	private static func appendVarint(_ input: UInt64, to output: inout Data) {
		var value = input
		while value >= 0x80 {
			output.append(UInt8(value & 0x7f) | 0x80)
			value >>= 7
		}
		output.append(UInt8(value))
	}

	private static func appendBytes(_ bytes: Data, field: UInt64, to output: inout Data) {
		appendVarint(field << 3 | 2, to: &output)
		appendVarint(UInt64(bytes.count), to: &output)
		output.append(bytes)
	}
}
