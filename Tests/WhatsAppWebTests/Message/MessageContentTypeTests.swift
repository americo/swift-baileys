import Testing
@testable import WhatsAppWeb

@Suite("Message content type resolver")
struct MessageContentTypeResolverTests {
	@Test("returns conversation before message fields")
	func returnsConversationBeforeMessageFields() {
		var message = MessageContentBuilder.text("extended")
		message.conversation = "plain"

		#expect(MessageContentTypeResolver.contentType(of: message) == .conversation)
	}

	@Test("ignores sender key distribution messages")
	func ignoresSenderKeyDistributionMessages() {
		var distribution = Proto_Message.SenderKeyDistributionMessage()
		distribution.groupID = "123@g.us"
		var message = Proto_Message()
		message.senderKeyDistributionMessage = distribution

		#expect(MessageContentTypeResolver.contentType(of: message) == nil)
	}

	@Test("returns the first non sender-key message field in proto order")
	func returnsFirstNonSenderKeyMessageFieldInProtoOrder() {
		var distribution = Proto_Message.SenderKeyDistributionMessage()
		distribution.groupID = "123@g.us"
		var image = Proto_Message.ImageMessage()
		image.url = "https://mmg.whatsapp.net/image"
		var message = MessageContentBuilder.text("extended")
		message.senderKeyDistributionMessage = distribution
		message.imageMessage = image

		#expect(MessageContentTypeResolver.contentType(of: message) == .imageMessage)
	}

	@Test("matches later message fields")
	func matchesLaterMessageFields() {
		var message = Proto_Message()
		message.pollResultSnapshotMessageV3 = Proto_Message.PollResultSnapshotMessage()

		#expect(MessageContentTypeResolver.contentType(of: message) == .pollResultSnapshotMessageV3)
	}

	@Test("matches manually named protobuf message fields")
	func matchesManuallyNamedProtobufMessageFields() {
		var callLog = Proto_Message()
		callLog.callLogMesssage = Proto_Message.CallLogMessage()

		var historyBundle = Proto_Message()
		historyBundle.messageHistoryBundle = Proto_Message.MessageHistoryBundle()

		var historyNotice = Proto_Message()
		historyNotice.messageHistoryNotice = Proto_Message.MessageHistoryNotice()

		#expect(MessageContentTypeResolver.contentType(of: callLog) == .callLogMesssage)
		#expect(MessageContentTypeResolver.contentType(of: historyBundle) == .messageHistoryBundle)
		#expect(MessageContentTypeResolver.contentType(of: historyNotice) == .messageHistoryNotice)
	}

	@Test("returns normalized content type for future proof wrappers")
	func returnsNormalizedContentTypeForFutureProofWrappers() {
		let inner = MessageContentBuilder.text("wrapped")
		let message = futureProofMessage(inner) { $0.ephemeralMessage = $1 }

		#expect(MessageContentTypeResolver.contentType(of: message) == .ephemeralMessage)
		#expect(MessageContentTypeResolver.normalizedContentType(of: message) == .extendedTextMessage)
	}

	@Test("returns normalized content type for device sent wrappers")
	func returnsNormalizedContentTypeForDeviceSentWrappers() {
		var deviceSent = Proto_Message.DeviceSentMessage()
		deviceSent.destinationJid = "123@s.whatsapp.net"
		deviceSent.message = MessageContentBuilder.text("linked device")
		var message = Proto_Message()
		message.deviceSentMessage = deviceSent

		#expect(MessageContentTypeResolver.contentType(of: message) == .deviceSentMessage)
		#expect(MessageContentTypeResolver.normalizedContentType(of: message) == .extendedTextMessage)
	}

	@Test("does not return non message metadata fields")
	func doesNotReturnNonMessageMetadataFields() {
		var message = Proto_Message()
		message.messageContextInfo = Proto_MessageContextInfo()

		#expect(MessageContentTypeResolver.contentType(of: message) == nil)
	}
}
