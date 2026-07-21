import Testing
@testable import WhatsAppWeb

@Suite("Message content normalizer")
struct MessageContentNormalizerTests {
	@Test("unwraps future proof message envelopes")
	func unwrapsFutureProofMessageEnvelopes() throws {
		let inner = MessageContentBuilder.text("wrapped")
		let message = futureProofMessage(inner) { $0.ephemeralMessage = $1 }

		#expect(MessageContentNormalizer.normalized(message).extendedTextMessage.text == "wrapped")
	}

	@Test("unwraps device sent message envelopes")
	func unwrapsDeviceSentMessageEnvelopes() throws {
		var deviceSent = Proto_Message.DeviceSentMessage()
		deviceSent.destinationJid = "123@s.whatsapp.net"
		deviceSent.message = MessageContentBuilder.text("linked device")
		var message = Proto_Message()
		message.deviceSentMessage = deviceSent

		#expect(MessageContentNormalizer.normalized(message).extendedTextMessage.text == "linked device")
	}

	@Test("stops after five future proof wrappers")
	func stopsAfterFiveFutureProofWrappers() {
		let inner = MessageContentBuilder.text("deep")
		let wrapped = (0..<6).reduce(inner) { content, _ in
			futureProofMessage(content) { $0.ephemeralMessage = $1 }
		}

		let normalized = MessageContentNormalizer.normalized(wrapped)

		#expect(normalized.hasEphemeralMessage)
		#expect(normalized.ephemeralMessage.message.extendedTextMessage.text == "deep")
	}

	@Test("preserves messages without future proof wrappers")
	func preservesMessagesWithoutFutureProofWrappers() throws {
		let message = MessageContentBuilder.text("plain")

		#expect(try MessageContentNormalizer.normalized(message).serializedData() == message.serializedData())
	}
}
