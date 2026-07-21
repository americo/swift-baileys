import CryptoKit
import Foundation

enum MessageReportingTokenBuilder {
	static func shouldIncludeReportingToken(_ message: Proto_Message) -> Bool {
		!message.hasReactionMessage &&
			!message.hasEncReactionMessage &&
			!message.hasEncEventResponseMessage &&
			!message.hasPollUpdateMessage
	}

	static func reportingNode(encodedMessage: Data, message: Proto_Message, key: WhatsAppMessageKey) -> BinaryNode? {
		guard message.hasMessageContextInfo,
			  message.messageContextInfo.hasMessageSecret,
			  let messageID = key.id,
			  !messageID.isEmpty,
			  let remoteJID = key.remoteJID else {
			return nil
		}

		guard let content = extractReportingTokenContent(encodedMessage, fields: compiledReportingFields),
			  !content.isEmpty else {
			return nil
		}

		let from = key.fromMe ? remoteJID : key.participant ?? remoteJID
		let to = key.fromMe ? key.participant ?? remoteJID : remoteJID
		let info = Data(messageID.utf8) + Data(from.utf8) + Data(to.utf8) + Data(reportTokenInfo.utf8)
		let reportingSecret = HKDF<SHA256>.deriveKey(
			inputKeyMaterial: SymmetricKey(data: message.messageContextInfo.messageSecret),
			salt: Data(),
			info: info,
			outputByteCount: 32
		)
		let authenticationCode = HMAC<SHA256>.authenticationCode(
			for: content,
			using: reportingSecret
		)
		let reportingToken = Data(authenticationCode).prefix(16)

		return BinaryNode(
			tag: "reporting",
			content: .nodes([
				BinaryNode(
					tag: "reporting_token",
					attrs: ["v": "2"],
					content: .data(Data(reportingToken))
				)
			])
		)
	}

	private static let reportTokenInfo = "Report Token"
	private static let emptyFields: [Int: ReportingField] = [:]
	private static let compiledReportingFields: [Int: ReportingField] = [
		1: ReportingField(),
		3: ReportingField(children: [2: ReportingField(), 3: ReportingField(), 8: ReportingField(), 11: ReportingField(), 17: ReportingField(children: [21: ReportingField(), 22: ReportingField()]), 25: ReportingField()]),
		4: ReportingField(children: [1: ReportingField(), 16: ReportingField(), 17: ReportingField(children: [21: ReportingField(), 22: ReportingField()])]),
		5: ReportingField(children: [3: ReportingField(), 4: ReportingField(), 5: ReportingField(), 16: ReportingField(), 17: ReportingField(children: [21: ReportingField(), 22: ReportingField()])]),
		6: ReportingField(children: [1: ReportingField(), 17: ReportingField(children: [21: ReportingField(), 22: ReportingField()]), 30: ReportingField()]),
		7: ReportingField(children: [2: ReportingField(), 7: ReportingField(), 10: ReportingField(), 17: ReportingField(children: [21: ReportingField(), 22: ReportingField()]), 20: ReportingField()]),
		8: ReportingField(children: [2: ReportingField(), 7: ReportingField(), 9: ReportingField(), 17: ReportingField(children: [21: ReportingField(), 22: ReportingField()]), 21: ReportingField()]),
		9: ReportingField(children: [2: ReportingField(), 6: ReportingField(), 7: ReportingField(), 13: ReportingField(), 17: ReportingField(children: [21: ReportingField(), 22: ReportingField()]), 20: ReportingField()]),
		12: ReportingField(children: [1: ReportingField(), 2: ReportingField(), 14: ReportingField(message: true), 15: ReportingField()]),
		18: ReportingField(children: [6: ReportingField(), 16: ReportingField(), 17: ReportingField(children: [21: ReportingField(), 22: ReportingField()])]),
		26: ReportingField(children: [4: ReportingField(), 5: ReportingField(), 8: ReportingField(), 13: ReportingField(), 17: ReportingField(children: [21: ReportingField(), 22: ReportingField()])]),
		28: ReportingField(children: [1: ReportingField(), 2: ReportingField(), 4: ReportingField(), 5: ReportingField(), 6: ReportingField(), 7: ReportingField(children: [21: ReportingField(), 22: ReportingField()])]),
		37: ReportingField(children: [1: ReportingField(message: true)]),
		49: ReportingField(children: [2: ReportingField(), 3: ReportingField(children: [1: ReportingField(), 2: ReportingField()]), 5: ReportingField(children: [21: ReportingField(), 22: ReportingField()]), 8: ReportingField(children: [1: ReportingField(), 2: ReportingField()])]),
		53: ReportingField(children: [1: ReportingField(message: true)]),
		55: ReportingField(children: [1: ReportingField(message: true)]),
		58: ReportingField(children: [1: ReportingField(message: true)]),
		59: ReportingField(children: [1: ReportingField(message: true)]),
		60: ReportingField(children: [2: ReportingField(), 3: ReportingField(children: [1: ReportingField(), 2: ReportingField()]), 5: ReportingField(children: [21: ReportingField(), 22: ReportingField()]), 8: ReportingField(children: [1: ReportingField(), 2: ReportingField()])]),
		64: ReportingField(children: [2: ReportingField(), 3: ReportingField(children: [1: ReportingField(), 2: ReportingField()]), 5: ReportingField(children: [21: ReportingField(), 22: ReportingField()]), 8: ReportingField(children: [1: ReportingField(), 2: ReportingField()])]),
		66: ReportingField(children: [2: ReportingField(), 6: ReportingField(), 7: ReportingField(), 13: ReportingField(), 17: ReportingField(children: [21: ReportingField(), 22: ReportingField()]), 20: ReportingField()]),
		74: ReportingField(children: [1: ReportingField(message: true)]),
		87: ReportingField(children: [1: ReportingField(message: true)]),
		88: ReportingField(children: [1: ReportingField(), 2: ReportingField(children: [1: ReportingField()]), 3: ReportingField(children: [21: ReportingField(), 22: ReportingField()])]),
		92: ReportingField(children: [1: ReportingField(message: true)]),
		93: ReportingField(children: [1: ReportingField(message: true)]),
		94: ReportingField(children: [1: ReportingField(message: true)])
	]

	private static func extractReportingTokenContent(_ data: Data, fields: [Int: ReportingField]) -> Data? {
		let bytes = Array(data)
		var output: [FieldBytes] = []
		var index = 0

		while index < bytes.count {
			guard let tag = decodeVarint(bytes, offset: index) else {
				return nil
			}

			let fieldNumber = Int(tag.value >> 3)
			let wireType = Int(tag.value & 0x7)
			let fieldStart = index
			index += tag.bytes

			let field = fields[fieldNumber]
			if wireType == 0 {
				guard let value = decodeVarint(bytes, offset: index) else {
					return nil
				}

				let end = index + value.bytes
				guard end <= bytes.count else {
					return nil
				}

				if field != nil {
					output.append(FieldBytes(number: fieldNumber, bytes: Data(bytes[fieldStart..<end])))
				}

				index = end
			} else if wireType == 1 {
				let end = index + 8
				guard end <= bytes.count else {
					return nil
				}

				if field != nil {
					output.append(FieldBytes(number: fieldNumber, bytes: Data(bytes[fieldStart..<end])))
				}

				index = end
			} else if wireType == 5 {
				let end = index + 4
				guard end <= bytes.count else {
					return nil
				}

				if field != nil {
					output.append(FieldBytes(number: fieldNumber, bytes: Data(bytes[fieldStart..<end])))
				}

				index = end
			} else if wireType == 2 {
				guard let length = decodeVarint(bytes, offset: index) else {
					return nil
				}

				let valueStart = index + length.bytes
				let valueEnd = valueStart + Int(length.value)
				guard valueEnd <= bytes.count else {
					return nil
				}

				guard let field else {
					index = valueEnd
					continue
				}

				if field.message || field.children != nil {
					guard let nested = extractReportingTokenContent(
						Data(bytes[valueStart..<valueEnd]),
						fields: field.children ?? emptyFields
					) else {
						return nil
					}

					if !nested.isEmpty {
						output.append(FieldBytes(
							number: fieldNumber,
							bytes: encodeVarint(tag.value) + encodeVarint(UInt64(nested.count)) + nested
						))
					}
				} else {
					output.append(FieldBytes(number: fieldNumber, bytes: Data(bytes[fieldStart..<valueEnd])))
				}

				index = valueEnd
			} else {
				return nil
			}
		}

		return output
			.sorted { $0.number < $1.number }
			.reduce(into: Data()) { $0.append($1.bytes) }
	}

	private static func decodeVarint(_ bytes: [UInt8], offset: Int) -> Varint? {
		var value: UInt64 = 0
		var count = 0
		var shift: UInt64 = 0

		while offset + count < bytes.count {
			let current = bytes[offset + count]
			value |= UInt64(current & 0x7f) << shift
			count += 1

			if (current & 0x80) == 0 {
				return Varint(value: value, bytes: count)
			}

			shift += 7
			if shift > 35 {
				return nil
			}
		}

		return nil
	}

	private static func encodeVarint(_ value: UInt64) -> Data {
		var remaining = value
		var bytes: [UInt8] = []
		while remaining > 0x7f {
			bytes.append(UInt8(remaining & 0x7f) | 0x80)
			remaining >>= 7
		}

		bytes.append(UInt8(remaining))
		return Data(bytes)
	}
}

private struct ReportingField {
	let message: Bool
	let children: [Int: ReportingField]?

	init(message: Bool = false, children: [Int: ReportingField]? = nil) {
		self.message = message
		self.children = children
	}
}

private struct FieldBytes {
	let number: Int
	let bytes: Data
}

private struct Varint {
	let value: UInt64
	let bytes: Int
}
