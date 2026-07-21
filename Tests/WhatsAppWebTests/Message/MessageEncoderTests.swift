import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Message encoder")
struct MessageEncoderTests {
	@Test("encodes WAProto message with Baileys minimum random padding")
	func encodesWAProtoMessageWithBaileysMinimumRandomPadding() throws {
		let message = MessageContentBuilder.text("hello from swift")
		let encoder = MessageEncoder(randomByte: { 0x00 })

		let encoded = try encoder.encode(message)
		let expected = try Data(hexString: "32120a1068656c6c6f2066726f6d20737769667401")

		#expect(encoded == expected)
	}

	@Test("encodes WAProto message with Baileys maximum random padding")
	func encodesWAProtoMessageWithBaileysMaximumRandomPadding() throws {
		let message = MessageContentBuilder.text("hello from swift")
		let encoder = MessageEncoder(randomByte: { 0x0f })

		let encoded = try encoder.encode(message)
		let expected = try Data(hexString: "32120a1068656c6c6f2066726f6d20737769667410101010101010101010101010101010")

		#expect(encoded == expected)
	}

	@Test("encodes newsletter messages without Baileys random padding")
	func encodesNewsletterMessagesWithoutBaileysRandomPadding() throws {
		let message = MessageContentBuilder.text("hello from swift")

		let encoded = try MessageEncoder.encodeNewsletterMessage(message)
		let expected = try Data(hexString: "32120a1068656c6c6f2066726f6d207377696674")

		#expect(encoded == expected)
	}

	@Test("unpads Baileys random padding")
	func unpadsBaileysRandomPadding() throws {
		let padded = Data([0xde, 0xad, 0xbe, 0xef, 0x04, 0x04, 0x04, 0x04])

		let unpadded = try MessagePadding.unpadded(padded)

		#expect(unpadded == Data([0xde, 0xad, 0xbe, 0xef]))
	}

	@Test("throws for empty padded messages")
	func throwsForEmptyPaddedMessages() {
		#expect(throws: MessagePaddingError.emptyPaddedMessage) {
			try MessagePadding.unpadded(Data())
		}
	}

	@Test("throws when padding is longer than the message")
	func throwsWhenPaddingIsLongerThanTheMessage() {
		#expect(throws: MessagePaddingError.invalidPadding) {
			try MessagePadding.unpadded(Data([0x03, 0x03]))
		}
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw MessageEncoderTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum MessageEncoderTestError: Error {
	case invalidHex
}
