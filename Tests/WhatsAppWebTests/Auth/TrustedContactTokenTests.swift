import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Trusted contact tokens")
struct TrustedContactTokenTests {
	@Test("expired tokens preserve sender timestamp when cleared")
	func expiredTokensPreserveSenderTimestampWhenCleared() async throws {
		let keys = InMemorySignalKeyStore(storage: [
			.tcToken: [
				"123@s.whatsapp.net": try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data([0xaa]),
					timestamp: "1",
					senderTimestamp: "250"
				))
			]
		])

		let node = await TrustedContactTokenNodeBuilder.build(for: "123@s.whatsapp.net", keys: keys)

		#expect(node == nil)
		let data = try #require(await keys.get(.tcToken, ids: ["123@s.whatsapp.net"])["123@s.whatsapp.net"])
		#expect(try TrustedContactTokenCoding.decode(data) == TrustedContactToken(
			token: Data(),
			timestamp: "1",
			senderTimestamp: "250"
		))
	}

	@Test("prunes expired tokens using the persisted jid index")
	func prunesExpiredTokensUsingPersistedJIDIndex() async throws {
		let now = Date(timeIntervalSince1970: 1_700_000_000)
		let recentTimestamp = String(Int(now.timeIntervalSince1970) - 60)
		let expiredJID = "111@s.whatsapp.net"
		let senderJID = "222@s.whatsapp.net"
		let validJID = "333@s.whatsapp.net"
		let missingJID = "444@s.whatsapp.net"
		let keys = InMemorySignalKeyStore(storage: [
			.tcToken: [
				TrustedContactTokenCoding.indexKey: try TrustedContactTokenCoding.encodeIndex([
					expiredJID,
					senderJID,
					validJID,
					missingJID
				]),
				expiredJID: try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data([0x01]),
					timestamp: "1"
				)),
				senderJID: try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data([0x02]),
					timestamp: "1",
					senderTimestamp: recentTimestamp
				)),
				validJID: try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data([0x03]),
					timestamp: recentTimestamp
				))
			]
		])

		try await TrustedContactTokenCoding.pruneExpiredTokens(in: keys, now: now)

		let entries = try await keys.get(.tcToken, ids: [
			TrustedContactTokenCoding.indexKey,
			expiredJID,
			senderJID,
			validJID,
			missingJID
		])
		#expect(entries[expiredJID] == nil)
		#expect(entries[missingJID] == nil)
		#expect(try TrustedContactTokenCoding.decodeIndex(entries[TrustedContactTokenCoding.indexKey]) == [
			senderJID,
			validJID
		])
		#expect(try TrustedContactTokenCoding.decode(try #require(entries[senderJID])) == TrustedContactToken(
			token: Data(),
			timestamp: "1",
			senderTimestamp: recentTimestamp
		))
		#expect(try TrustedContactTokenCoding.decode(try #require(entries[validJID])) == TrustedContactToken(
			token: Data([0x03]),
			timestamp: recentTimestamp
		))
	}

	@Test("stores newer trusted contact tokens from history sync chats")
	func storesNewerTrustedContactTokensFromHistorySyncChats() async throws {
		let keys = InMemorySignalKeyStore(storage: [
			.tcToken: [
				"111@s.whatsapp.net": try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data([0x09]),
					timestamp: "300",
					senderTimestamp: "200"
				))
			]
		])
		var olderChat = Proto_Conversation()
		olderChat.id = "111@c.us"
		olderChat.tcToken = Data([0x01])
		olderChat.tcTokenTimestamp = 250
		olderChat.tcTokenSenderTimestamp = 240
		var newerChat = Proto_Conversation()
		newerChat.id = "222@c.us"
		newerChat.tcToken = Data([0x02])
		newerChat.tcTokenTimestamp = 400
		newerChat.tcTokenSenderTimestamp = 350

		try await TrustedContactTokenCoding.storeHistorySyncTokens(from: [olderChat, newerChat], in: keys)

		let entries = try await keys.get(.tcToken, ids: [
			"111@s.whatsapp.net",
			"222@s.whatsapp.net",
			TrustedContactTokenCoding.indexKey
		])
		#expect(try TrustedContactTokenCoding.decode(try #require(entries["111@s.whatsapp.net"])) == TrustedContactToken(
			token: Data([0x09]),
			timestamp: "300",
			senderTimestamp: "200"
		))
		#expect(try TrustedContactTokenCoding.decode(try #require(entries["222@s.whatsapp.net"])) == TrustedContactToken(
			token: Data([0x02]),
			timestamp: "400",
			senderTimestamp: "350"
		))
		#expect(try TrustedContactTokenCoding.decodeIndex(entries[TrustedContactTokenCoding.indexKey]) == ["222@s.whatsapp.net"])
	}

	@Test("stores history sync trusted contact tokens under mapped LID")
	func storesHistorySyncTrustedContactTokensUnderMappedLID() async throws {
		let keys = InMemorySignalKeyStore()
		var chat = Proto_Conversation()
		chat.id = "258840000000@c.us"
		chat.tcToken = Data([0x0a, 0x0b])
		chat.tcTokenTimestamp = 600
		chat.tcTokenSenderTimestamp = 500

		try await TrustedContactTokenCoding.storeHistorySyncTokens(from: [chat], in: keys) { jid in
			#expect(jid == "258840000000@s.whatsapp.net")
			return "111222333@lid"
		}

		let entries = try await keys.get(.tcToken, ids: [
			"258840000000@s.whatsapp.net",
			"111222333@lid",
			TrustedContactTokenCoding.indexKey
		])
		#expect(entries["258840000000@s.whatsapp.net"] == nil)
		#expect(try TrustedContactTokenCoding.decode(try #require(entries["111222333@lid"])) == TrustedContactToken(
			token: Data([0x0a, 0x0b]),
			timestamp: "600",
			senderTimestamp: "500"
		))
		#expect(try TrustedContactTokenCoding.decodeIndex(entries[TrustedContactTokenCoding.indexKey]) == ["111222333@lid"])
	}

	@Test("builds token node from mapped LID storage for PN input")
	func buildsTokenNodeFromMappedLIDStorageForPNInput() async throws {
		let keys = InMemorySignalKeyStore(storage: [
			.tcToken: [
				"111222333@lid": try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data([0xde, 0xad]),
					timestamp: "9999999999"
				))
			]
		])

		let node = await TrustedContactTokenNodeBuilder.build(
			for: "258840000000@s.whatsapp.net",
			keys: keys
		) { jid in
			#expect(jid == "258840000000@s.whatsapp.net")
			return "111222333@lid"
		}

		#expect(node == BinaryNode(tag: "tctoken", content: .data(Data([0xde, 0xad]))))
	}
}
