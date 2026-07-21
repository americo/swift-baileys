import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client index-only app-state mutation events")
struct WhatsAppClientAppStateIndexMutationEventTests {
	@Test("sync app state emits archive updates from mutation index type")
	func syncAppStateEmitsArchiveUpdatesFromMutationIndexType() async throws {
		let (client, transport) = try appStateMutationClient()
		let patch = try encodedMutationPatch(
			action: Proto_SyncActionValue(),
			index: ["archive", "123@s.whatsapp.net"],
			type: .regularLow
		)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.regularLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "regular_low",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .chatsUpdated([
			ChatUpdate(id: "123@s.whatsapp.net", archived: true)
		]))
	}

	@Test("sync app state emits starred message updates from mutation index type")
	func syncAppStateEmitsStarredMessageUpdatesFromMutationIndexType() async throws {
		let (client, transport) = try appStateMutationClient()
		let patch = try encodedMutationPatch(
			action: Proto_SyncActionValue(),
			index: ["star", "123@s.whatsapp.net", "3EB0STAR", "0", "1"],
			type: .regularLow
		)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.regularLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "regular_low",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .messagesUpdated([
			ReceivedMessageUpdate(
				key: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "3EB0STAR"),
				status: nil,
				timestamp: nil,
				starred: true
			)
		]))
	}

	@Test("sync app state emits local message delete updates from mutation index type")
	func syncAppStateEmitsLocalMessageDeleteUpdatesFromMutationIndexType() async throws {
		let (client, transport) = try appStateMutationClient()
		let patch = try encodedMutationPatch(
			action: Proto_SyncActionValue(),
			index: ["deleteMessageForMe", "123@s.whatsapp.net", "3EB0DELETE", "1"],
			type: .regularHigh
		)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.regularHigh])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "regular_high",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .messagesDeleted(MessageDeleteUpdate(keys: [
			WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: true, id: "3EB0DELETE")
		])))
	}

	@Test("sync app state emits chat delete updates from mutation index type")
	func syncAppStateEmitsChatDeleteUpdatesFromMutationIndexType() async throws {
		let (client, transport) = try appStateMutationClient()
		let patch = try encodedMutationPatch(
			action: Proto_SyncActionValue(),
			index: ["deleteChat", "123@s.whatsapp.net"],
			type: .regularHigh
		)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.regularHigh])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "regular_high",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .chatsDeleted(ChatDeleteUpdate(ids: ["123@s.whatsapp.net"])))
	}
}
