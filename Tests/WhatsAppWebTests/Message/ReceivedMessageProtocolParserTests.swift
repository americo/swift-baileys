import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message protocol parser")
struct ReceivedMessageProtocolParserTests {
	@Test("parses ephemeral setting protocol messages")
	func parsesEphemeralSettingProtocolMessages() throws {
		var disappearingMode = Proto_DisappearingMode()
		disappearingMode.initiator = .initiatedByOther
		disappearingMode.trigger = .chatSetting
		disappearingMode.initiatorDeviceJid = "device@s.whatsapp.net"
		disappearingMode.initiatedByMe = false
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .ephemeralSetting
		protocolMessage.ephemeralExpiration = 86_400
		protocolMessage.ephemeralSettingTimestamp = 1_700_000_000
		protocolMessage.disappearingMode = disappearingMode
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .ephemeralSetting(ReceivedEphemeralSettingContent(
			expirationSeconds: 86_400,
			settingTimestampSeconds: 1_700_000_000,
			disappearingMode: ReceivedDisappearingModeContent(
				initiator: .initiatedByOther,
				trigger: .chatSetting,
				initiatorDeviceJID: "device@s.whatsapp.net",
				initiatedByMe: false
			)
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent ephemeral setting protocol fields")
	func preservesAbsentEphemeralSettingProtocolFields() throws {
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .ephemeralSetting
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .ephemeralSetting(ReceivedEphemeralSettingContent(
			expirationSeconds: nil,
			settingTimestampSeconds: nil,
			disappearingMode: nil
		)))
	}

	@Test("preserves unrecognized disappearing mode values")
	func preservesUnrecognizedDisappearingModeValues() throws {
		var disappearingMode = Proto_DisappearingMode()
		disappearingMode.initiator = .UNRECOGNIZED(44)
		disappearingMode.trigger = .UNRECOGNIZED(55)
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .ephemeralSetting
		protocolMessage.disappearingMode = disappearingMode
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .ephemeralSetting(ReceivedEphemeralSettingContent(
			expirationSeconds: nil,
			settingTimestampSeconds: nil,
			disappearingMode: ReceivedDisappearingModeContent(
				initiator: .unrecognized(44),
				trigger: .unrecognized(55),
				initiatorDeviceJID: nil,
				initiatedByMe: nil
			)
		)))
	}

	@Test("parses history sync notification protocol messages")
	func parsesHistorySyncNotificationProtocolMessages() throws {
		let fileSHA256 = Data([0x01, 0x02])
		let mediaKey = Data([0x03, 0x04])
		let fileEncSHA256 = Data([0x05, 0x06])
		let inlinePayload = Data([0x07, 0x08])
		var accessStatus = Proto_Message.HistorySyncMessageAccessStatus()
		accessStatus.completeAccessGranted = true
		var notification = Proto_Message.HistorySyncNotification()
		notification.fileSha256 = fileSHA256
		notification.fileLength = 123_456
		notification.mediaKey = mediaKey
		notification.fileEncSha256 = fileEncSHA256
		notification.directPath = "/v/t62.7118/history"
		notification.syncType = .onDemand
		notification.chunkOrder = 4
		notification.originalMessageID = "history-origin"
		notification.progress = 75
		notification.oldestMsgInChunkTimestampSec = 1_700_000_000
		notification.initialHistBootstrapInlinePayload = inlinePayload
		notification.peerDataRequestSessionID = "peer-session"
		notification.encHandle = "enc-handle"
		notification.messageAccessStatus = accessStatus
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .historySyncNotification
		protocolMessage.historySyncNotification = notification
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .historySyncNotification(ReceivedHistorySyncNotificationContent(
			fileSHA256: fileSHA256,
			fileLength: 123_456,
			mediaKey: mediaKey,
			fileEncSHA256: fileEncSHA256,
			directPath: "/v/t62.7118/history",
			syncType: .onDemand,
			chunkOrder: 4,
			originalMessageID: "history-origin",
			progress: 75,
			oldestMessageInChunkTimestampSeconds: 1_700_000_000,
			initialHistoryBootstrapInlinePayload: inlinePayload,
			peerDataRequestSessionID: "peer-session",
			encryptedHandle: "enc-handle",
			messageAccessStatus: ReceivedHistorySyncMessageAccessStatusContent(completeAccessGranted: true)
		)))
		#expect(try content.mediaDownloadRequest() == MediaDownloadRequest(
			url: try #require(URL(string: "https://mmg.whatsapp.net/v/t62.7118/history")),
			mediaKey: mediaKey,
			mediaType: .mdMessageHistory,
			fileEncSHA256: fileEncSHA256,
			fileSHA256: fileSHA256
		))
	}

	@Test("preserves absent history sync notification protocol fields")
	func preservesAbsentHistorySyncNotificationProtocolFields() throws {
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .historySyncNotification
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .historySyncNotification(ReceivedHistorySyncNotificationContent(
			fileSHA256: nil,
			fileLength: nil,
			mediaKey: nil,
			fileEncSHA256: nil,
			directPath: nil,
			syncType: nil,
			chunkOrder: nil,
			originalMessageID: nil,
			progress: nil,
			oldestMessageInChunkTimestampSeconds: nil,
			initialHistoryBootstrapInlinePayload: nil,
			peerDataRequestSessionID: nil,
			encryptedHandle: nil,
			messageAccessStatus: nil
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("does not download inline history sync payloads")
	func doesNotDownloadInlineHistorySyncPayloads() throws {
		var notification = Proto_Message.HistorySyncNotification()
		notification.initialHistBootstrapInlinePayload = Data([0x01, 0x02])
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .historySyncNotification
		protocolMessage.historySyncNotification = notification
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves unrecognized history sync type raw values")
	func preservesUnrecognizedHistorySyncTypeRawValues() throws {
		var notification = Proto_Message.HistorySyncNotification()
		notification.syncType = .UNRECOGNIZED(99)
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .historySyncNotification
		protocolMessage.historySyncNotification = notification
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .historySyncNotification(ReceivedHistorySyncNotificationContent(
			fileSHA256: nil,
			fileLength: nil,
			mediaKey: nil,
			fileEncSHA256: nil,
			directPath: nil,
			syncType: .unrecognized(99),
			chunkOrder: nil,
			originalMessageID: nil,
			progress: nil,
			oldestMessageInChunkTimestampSeconds: nil,
			initialHistoryBootstrapInlinePayload: nil,
			peerDataRequestSessionID: nil,
			encryptedHandle: nil,
			messageAccessStatus: nil
		)))
	}

	@Test("parses peer data placeholder resend responses")
	func parsesPeerDataPlaceholderResendResponses() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "123@s.whatsapp.net"
		key.id = "resend-1"
		var webMessage = Proto_WebMessageInfo()
		webMessage.key = key
		webMessage.message = MessageContentBuilder.text("retried")
		webMessage.messageTimestamp = 1_700_000_001
		let bytes = try webMessage.serializedData()
		var placeholder = Proto_Message.PeerDataOperationRequestResponseMessage
			.PeerDataOperationResult
			.PlaceholderMessageResendResponse()
		placeholder.webMessageInfoBytes = bytes
		var result = Proto_Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult()
		result.placeholderMessageResendResponse = placeholder
		var response = Proto_Message.PeerDataOperationRequestResponseMessage()
		response.stanzaID = "pdo-1"
		response.peerDataOperationResult = [result]
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .peerDataOperationRequestResponseMessage
		protocolMessage.peerDataOperationRequestResponseMessage = response
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .peerDataOperationRequestResponse(ReceivedPeerDataOperationRequestResponseContent(
			stanzaID: "pdo-1",
			placeholderResendMessages: [
				ReceivedMessage(
					id: "resend-1",
					from: "123@s.whatsapp.net",
					timestamp: 1_700_000_001,
					content: .text("retried")
				)
			]
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("ignores peer data placeholder resend responses without decodable messages")
	func ignoresPeerDataPlaceholderResendResponsesWithoutDecodableMessages() throws {
		var emptyResult = Proto_Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult()
		emptyResult.placeholderMessageResendResponse = Proto_Message.PeerDataOperationRequestResponseMessage
			.PeerDataOperationResult
			.PlaceholderMessageResendResponse()
		var invalidPlaceholder = Proto_Message.PeerDataOperationRequestResponseMessage
			.PeerDataOperationResult
			.PlaceholderMessageResendResponse()
		invalidPlaceholder.webMessageInfoBytes = Data([0xff])
		var invalidResult = Proto_Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult()
		invalidResult.placeholderMessageResendResponse = invalidPlaceholder
		var response = Proto_Message.PeerDataOperationRequestResponseMessage()
		response.peerDataOperationResult = [emptyResult, invalidResult]
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .peerDataOperationRequestResponseMessage
		protocolMessage.peerDataOperationRequestResponseMessage = response
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .peerDataOperationRequestResponse(ReceivedPeerDataOperationRequestResponseContent(
			stanzaID: nil,
			placeholderResendMessages: []
		)))
	}

	@Test("parses share phone number protocol messages")
	func parsesSharePhoneNumberProtocolMessages() throws {
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .sharePhoneNumber
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .phoneNumberShared(ReceivedPhoneNumberSharedContent()))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses limit sharing protocol messages")
	func parsesLimitSharingProtocolMessages() throws {
		var limitSharing = Proto_LimitSharing()
		limitSharing.sharingLimited = true
		limitSharing.trigger = .bizSupportsFbHosting
		limitSharing.limitSharingSettingTimestamp = 1_717_777_000
		limitSharing.initiatedByMe = false
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .limitSharing
		protocolMessage.limitSharing = limitSharing
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .limitSharing(ReceivedLimitSharingContent(
			sharingLimited: true,
			trigger: .bizSupportsFBHosting,
			settingTimestampMilliseconds: 1_717_777_000,
			initiatedByMe: false
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent limit sharing protocol fields")
	func preservesAbsentLimitSharingProtocolFields() throws {
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .limitSharing
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .limitSharing(ReceivedLimitSharingContent(
			sharingLimited: nil,
			trigger: nil,
			settingTimestampMilliseconds: nil,
			initiatedByMe: nil
		)))
	}
}
