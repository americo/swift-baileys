import Foundation
import Compression
import Testing
@testable import WhatsAppWeb

@Suite("History sync processor")
struct HistorySyncProcessorTests {
	@Test("processes chats contacts messages and LID mappings")
	func processesChatsContactsMessagesAndLIDMappings() throws {
		var explicitMapping = Proto_PhoneNumberToLIDMapping()
		explicitMapping.pnJid = "111@s.whatsapp.net"
		explicitMapping.lidJid = "111@lid"
		var history = Proto_HistorySync()
		history.syncType = .recent
		history.progress = 45
		history.phoneNumberToLidMappings = [explicitMapping]
		history.conversations = [
			conversation(
				id: "222@lid",
				displayName: "Swift LID",
				name: "Fallback",
				username: "swiftuser",
				pnJid: "222@s.whatsapp.net",
				messages: [
					historyMessage(
						id: "outgoing",
						remoteJID: "222@lid",
						fromMe: true,
						timestamp: 1_700_000_001,
						text: "sent"
					),
					historyMessage(
						id: "incoming",
						remoteJID: "222@lid",
						fromMe: false,
						timestamp: 1_700_000_002,
						text: "received"
					)
				]
			)
		]

		let result = HistorySyncProcessor.process(history)

		#expect(result.syncType == .recent)
		#expect(result.progress == 45)
		#expect(result.lidPnMappings == [
			LIDMapping(pn: "111@s.whatsapp.net", lid: "111@lid"),
			LIDMapping(pn: "222@s.whatsapp.net", lid: "222@lid")
		])
		#expect(result.contacts == [
			HistorySyncContact(
				id: "222@lid",
				name: "Swift LID",
				username: "swiftuser",
				lid: nil,
				phoneNumber: "222@s.whatsapp.net",
				notify: nil,
				verifiedName: nil
			)
		])
		#expect(result.messages.map(\.id) == ["outgoing", "incoming"])
		#expect(result.messages.map(\.content) == [.text("sent"), .text("received")])
		#expect(result.chats == [
			HistorySyncChat(
				id: "222@lid",
				name: "Fallback",
				displayName: "Swift LID",
				username: "swiftuser",
				lid: nil,
				phoneNumber: "222@s.whatsapp.net",
				lastMessageReceivedTimestamp: 1_700_000_002,
				latestMessage: result.messages[0]
			)
		])
	}

	@Test("extracts PN from outgoing receipts when LID chat has no PN")
	func extractsPNFromOutgoingReceiptsWhenLIDChatHasNoPN() {
		var receipt = Proto_UserReceipt()
		receipt.userJid = "333@s.whatsapp.net"
		var sentMessage = webMessage(
			id: "sent-to-lid",
			remoteJID: "333@lid",
			fromMe: true,
			timestamp: 1_700_000_003,
			text: "receipt"
		)
		sentMessage.userReceipt = [receipt]
		var historyItem = Proto_HistorySyncMsg()
		historyItem.message = sentMessage
		var history = Proto_HistorySync()
		history.syncType = .full
		history.conversations = [
			conversation(id: "333@lid", messages: [historyItem])
		]

		let result = HistorySyncProcessor.process(history)

		#expect(result.lidPnMappings == [
			LIDMapping(pn: "333@s.whatsapp.net", lid: "333@lid")
		])
	}

	@Test("processes push name sync contacts")
	func processesPushNameSyncContacts() {
		var first = Proto_Pushname()
		first.id = "444@s.whatsapp.net"
		first.pushname = "Ana"
		var missingName = Proto_Pushname()
		missingName.id = "555@s.whatsapp.net"
		var history = Proto_HistorySync()
		history.syncType = .pushName
		history.pushnames = [first, missingName]

		let result = HistorySyncProcessor.process(history)

		#expect(result.chats.isEmpty)
		#expect(result.messages.isEmpty)
		#expect(result.contacts == [
			HistorySyncContact(
				id: "444@s.whatsapp.net",
				name: nil,
				username: nil,
				lid: nil,
				phoneNumber: nil,
				notify: "Ana",
				verifiedName: nil
			)
		])
	}

	@Test("adds verified business contacts from privacy mode stubs")
	func addsVerifiedBusinessContactsFromPrivacyModeStubs() {
		var businessMessage = webMessage(
			id: "biz",
			remoteJID: "666@s.whatsapp.net",
			fromMe: false,
			timestamp: 1_700_000_004
		)
		businessMessage.messageStubType = .bizPrivacyModeToBsp
		businessMessage.messageStubParameters = ["Verified Biz"]
		var historyItem = Proto_HistorySyncMsg()
		historyItem.message = businessMessage
		var history = Proto_HistorySync()
		history.syncType = .initialBootstrap
		history.conversations = [
			conversation(id: "666@s.whatsapp.net", messages: [historyItem])
		]

		let result = HistorySyncProcessor.process(history)

		#expect(result.contacts.last == HistorySyncContact(
			id: "666@s.whatsapp.net",
			name: nil,
			username: nil,
			lid: nil,
			phoneNumber: nil,
			notify: nil,
			verifiedName: "Verified Biz"
		))
	}

	@Test("processes inline compressed history sync notifications")
	func processesInlineCompressedHistorySyncNotifications() async throws {
		var history = Proto_HistorySync()
		history.syncType = .onDemand
		history.conversations = [
			conversation(
				id: "777@s.whatsapp.net",
				messages: [
					historyMessage(
						id: "inline-history",
						remoteJID: "777@s.whatsapp.net",
						fromMe: false,
						timestamp: 1_700_000_005,
						text: "inline"
					)
				]
			)
		]
		let client = WhatsAppClient()
		let notification = ReceivedHistorySyncNotificationContent(
			fileSHA256: nil,
			fileLength: nil,
			mediaKey: nil,
			fileEncSHA256: nil,
			directPath: nil,
			syncType: .onDemand,
			chunkOrder: 12,
			originalMessageID: nil,
			progress: nil,
			oldestMessageInChunkTimestampSeconds: nil,
			initialHistoryBootstrapInlinePayload: try zlibCompress(history.serializedData()),
			peerDataRequestSessionID: "peer-session",
			encryptedHandle: nil,
			messageAccessStatus: nil
		)

		let result = try await client.processHistorySyncNotification(notification)

		#expect(result.syncType == .onDemand)
		#expect(result.chunkOrder == 12)
		#expect(result.peerDataRequestSessionID == "peer-session")
		#expect(result.isLatest == nil)
		#expect(result.messages.map(\.id) == ["inline-history"])
		#expect(result.messages.map(\.content) == [.text("inline")])
	}
}

private func conversation(
	id: String,
	displayName: String? = nil,
	name: String? = nil,
	username: String? = nil,
	pnJid: String? = nil,
	lidJid: String? = nil,
	messages: [Proto_HistorySyncMsg]
) -> Proto_Conversation {
	var chat = Proto_Conversation()
	chat.id = id
	if let displayName {
		chat.displayName = displayName
	}
	if let name {
		chat.name = name
	}
	if let username {
		chat.username = username
	}
	if let pnJid {
		chat.pnJid = pnJid
	}
	if let lidJid {
		chat.lidJid = lidJid
	}
	chat.messages = messages
	return chat
}

private func historyMessage(
	id: String,
	remoteJID: String,
	fromMe: Bool,
	timestamp: UInt64,
	text: String
) -> Proto_HistorySyncMsg {
	var item = Proto_HistorySyncMsg()
	item.message = webMessage(id: id, remoteJID: remoteJID, fromMe: fromMe, timestamp: timestamp, text: text)
	return item
}

private func webMessage(
	id: String,
	remoteJID: String,
	fromMe: Bool,
	timestamp: UInt64,
	text: String? = nil
) -> Proto_WebMessageInfo {
	var key = Proto_MessageKey()
	key.id = id
	key.remoteJid = remoteJID
	key.fromMe = fromMe
	var message = Proto_WebMessageInfo()
	message.key = key
	message.messageTimestamp = timestamp
	if let text {
		var content = Proto_Message()
		content.conversation = text
		message.message = content
	}
	return message
}

private func zlibCompress(_ data: Data) throws -> Data {
	var capacity = max(64, data.count * 2)
	while capacity < 1024 * 1024 {
		var output = Data(count: capacity)
		let encodedCount = output.withUnsafeMutableBytes { outputBuffer in
			data.withUnsafeBytes { inputBuffer in
				compression_encode_buffer(
					outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
					capacity,
					inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
					data.count,
					nil,
					COMPRESSION_ZLIB
				)
			}
		}
		if encodedCount > 0 {
			output.removeSubrange(encodedCount..<output.count)
			return output
		}
		capacity *= 2
	}
	throw HistorySyncProcessorTestError.compressionFailed
}

private enum HistorySyncProcessorTestError: Error {
	case compressionFailed
}
