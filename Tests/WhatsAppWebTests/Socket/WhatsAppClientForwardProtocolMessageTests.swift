import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward protocol messages")
struct WhatsAppClientForwardProtocolMessageTests {
	@Test("forwards received ephemeral setting messages through the encrypted send path")
	func forwardsReceivedEphemeralSettingMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedMessage(content: .ephemeralSetting(ReceivedEphemeralSettingContent(
			expirationSeconds: 86_400,
			settingTimestampSeconds: 1_700_003_000,
			disappearingMode: ReceivedDisappearingModeContent(
				initiator: .initiatedByOther,
				trigger: .chatSetting,
				initiatorDeviceJID: "456.0@s.whatsapp.net",
				initiatedByMe: false
			)
		)))

		#expect(message.protocolMessage.type == .ephemeralSetting)
		#expect(message.protocolMessage.ephemeralExpiration == 86_400)
		#expect(message.protocolMessage.ephemeralSettingTimestamp == 1_700_003_000)
		#expect(message.protocolMessage.disappearingMode.initiator == .initiatedByOther)
		#expect(message.protocolMessage.disappearingMode.trigger == .chatSetting)
		#expect(message.protocolMessage.disappearingMode.initiatorDeviceJid == "456.0@s.whatsapp.net")
		#expect(!message.protocolMessage.disappearingMode.initiatedByMe)
	}

	@Test("forwards received limit sharing messages through the encrypted send path")
	func forwardsReceivedLimitSharingMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedMessage(content: .limitSharing(ReceivedLimitSharingContent(
			sharingLimited: true,
			trigger: .bizSupportsFBHosting,
			settingTimestampMilliseconds: 1_717_777_000,
			initiatedByMe: false
		)))

		#expect(message.protocolMessage.type == .limitSharing)
		#expect(message.protocolMessage.limitSharing.sharingLimited)
		#expect(message.protocolMessage.limitSharing.trigger == .bizSupportsFbHosting)
		#expect(message.protocolMessage.limitSharing.limitSharingSettingTimestamp == 1_717_777_000)
		#expect(!message.protocolMessage.limitSharing.initiatedByMe)
	}

	@Test("forwards received group member label change messages through the encrypted send path")
	func forwardsReceivedGroupMemberLabelChangeMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedMessage(content: .groupMemberLabelChange(ReceivedGroupMemberLabelChangeContent(
			label: "vip",
			labelTimestamp: 1_700_000_004
		)))

		#expect(message.protocolMessage.type == .groupMemberLabelChange)
		#expect(message.protocolMessage.memberLabel.label == "vip")
		#expect(message.protocolMessage.memberLabel.labelTimestamp == 1_700_000_004)
	}

	private func forwardedMessage(content: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x42]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "PROTOCOL1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDEDPROTOCOL"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
