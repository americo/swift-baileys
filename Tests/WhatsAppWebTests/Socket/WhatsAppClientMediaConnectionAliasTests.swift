import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client media connection aliases")
struct WhatsAppClientMediaConnectionAliasTests {
	@Test("Baileys refreshMediaConn alias queries media connection")
	func baileysRefreshMediaConnAliasQueriesMediaConnection() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.refreshMediaConn(forceGet: true)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "w:m")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.firstChild(named: "media_conn") != nil)

		await transport.enqueueInbound(mediaConnectionResponse(id: try #require(request.attrs["id"])))
		let connection = try await task.value
		#expect(connection == MediaConnectionInfo(
			hosts: [
				MediaConnectionHost(hostname: "mmg.whatsapp.net", maxContentLengthBytes: 1_048_576),
				MediaConnectionHost(hostname: "mmg-alt.whatsapp.net", maxContentLengthBytes: 2_097_152)
			],
			auth: "media-auth",
			ttl: 1_200
		))
	}

	@Test("Baileys getMediaHost alias returns first media host")
	func baileysGetMediaHostAliasReturnsFirstMediaHost() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.getMediaHost(forceRefresh: true)
		}
		let request = try await transport.waitForSentNode()
		await transport.enqueueInbound(mediaConnectionResponse(id: try #require(request.attrs["id"])))

		#expect(try await task.value == "mmg.whatsapp.net")
	}

	@Test("Baileys waUploadToServer alias delegates to configured uploader")
	func baileysWaUploadToServerAliasDelegatesToConfiguredUploader() async throws {
		let mediaUploader = StubWhatsAppMediaUploader(result: MediaUploadResult(
			mediaURL: "https://media.example/uploaded",
			directPath: "/v/uploaded",
			metaHMAC: "meta",
			timestamp: 42,
			fileID: 99
		))
		let client = WhatsAppClient(mediaUploader: mediaUploader)
		let data = Data([1, 2, 3])

		let result = try await client.waUploadToServer(
			data,
			fileEncSha256Base64: "AB+//ZA==",
			mediaType: .image
		)

		#expect(result == MediaUploadResult(
			mediaURL: "https://media.example/uploaded",
			directPath: "/v/uploaded",
			metaHMAC: "meta",
			timestamp: 42,
			fileID: 99
		))
		#expect(await mediaUploader.calls == [
			MediaUploadCall(data: data, fileEncSha256Base64: "AB+//ZA==", mediaType: .image)
		])
	}
}

private func mediaConnectionResponse(id: String) -> BinaryNode {
	BinaryNode(
		tag: "iq",
		attrs: ["id": id, "type": "result"],
		content: .nodes([
			BinaryNode(
				tag: "media_conn",
				attrs: ["auth": "media-auth", "ttl": "1200"],
				content: .nodes([
					BinaryNode(tag: "host", attrs: [
						"hostname": "mmg.whatsapp.net",
						"maxContentLengthBytes": "1048576"
					]),
					BinaryNode(tag: "host", attrs: [
						"hostname": "mmg-alt.whatsapp.net",
						"maxContentLengthBytes": "2097152"
					])
				])
			)
		])
	)
}
