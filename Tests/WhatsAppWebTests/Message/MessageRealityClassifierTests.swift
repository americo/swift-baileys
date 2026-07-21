import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Message reality classifier")
struct MessageRealityClassifierTests {
	@Test("treats normal content messages as real")
	func treatsNormalContentMessagesAsReal() {
		#expect(MessageRealityClassifier.isRealMessage(message(content: .text("hello"))))
	}

	@Test("excludes reaction poll update and normalized protocol messages")
	func excludesReactionPollUpdateAndNormalizedProtocolMessages() {
		#expect(!MessageRealityClassifier.isRealMessage(message(content: .reaction(ReceivedReactionContent(
			key: nil,
			text: "👍",
			groupingKey: nil,
			senderTimestampMilliseconds: nil
		)))))
		#expect(!MessageRealityClassifier.isRealMessage(message(content: .encryptedReaction(ReceivedEncryptedReactionContent(
			targetMessageKey: nil,
			encryptedPayload: Data([0x01]),
			encryptedIV: Data([0x02])
		)))))
		#expect(!MessageRealityClassifier.isRealMessage(message(content: .pollUpdate(ReceivedPollUpdateContent(
			pollCreationMessageKey: nil,
			encryptedPayload: Data([0x01]),
			encryptedIV: Data([0x02]),
			senderTimestampMilliseconds: nil
		)))))
		#expect(!MessageRealityClassifier.isRealMessage(message(content: .messageRevoked(ReceivedMessageRevokedContent(
			key: nil,
			timestampMilliseconds: nil
		)))))
		#expect(!MessageRealityClassifier.isRealMessage(message(content: .historySyncNotification(
			ReceivedHistorySyncNotificationContent(
				fileSHA256: nil,
				fileLength: nil,
				mediaKey: nil,
				fileEncSHA256: nil,
				directPath: nil,
				syncType: .initialBootstrap,
				chunkOrder: nil,
				originalMessageID: nil,
				progress: nil,
				oldestMessageInChunkTimestampSeconds: nil,
				initialHistoryBootstrapInlinePayload: nil,
				peerDataRequestSessionID: nil,
				encryptedHandle: nil,
				messageAccessStatus: nil
			)
		))))
	}

	@Test("treats Baileys real stubs as real messages")
	func treatsBaileysRealStubsAsRealMessages() {
		#expect(MessageRealityClassifier.isRealMessage(stubMessage(type: .callMissedVoice)))
		#expect(MessageRealityClassifier.isRealMessage(stubMessage(type: .callMissedVideo)))
		#expect(MessageRealityClassifier.isRealMessage(stubMessage(type: .callMissedGroupVoice)))
		#expect(MessageRealityClassifier.isRealMessage(stubMessage(type: .callMissedGroupVideo)))
		#expect(MessageRealityClassifier.isRealMessage(stubMessage(type: .groupParticipantAdd)))
	}

	@Test("excludes non real stubs")
	func excludesNonRealStubs() {
		#expect(!MessageRealityClassifier.isRealMessage(stubMessage(type: .groupChangeSubject)))
	}

	private func message(content: ReceivedMessageContent) -> ReceivedMessage {
		ReceivedMessage(
			id: "message-id",
			from: "123@s.whatsapp.net",
			timestamp: 1_720_000_000,
			content: content,
			fromMe: false
		)
	}

	private func stubMessage(type: ReceivedMessageStubType) -> ReceivedMessage {
		let stub = ReceivedMessageStubContent(type: type, parameters: [])
		return ReceivedMessage(
			id: "message-id",
			from: "123@g.us",
			timestamp: 1_720_000_000,
			content: .stub(stub),
			fromMe: false,
			stub: stub
		)
	}
}
