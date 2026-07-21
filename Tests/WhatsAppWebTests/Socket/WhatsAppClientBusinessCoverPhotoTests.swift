import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client business cover photo")
struct WhatsAppClientBusinessCoverPhotoTests {
	@Test("updates business cover photo after raw media upload")
	func updatesBusinessCoverPhotoAfterRawMediaUpload() async throws {
		let transport = MockBusinessWebSocketTransport()
		let mediaUploader = StubWhatsAppMediaUploader(result: MediaUploadResult(
			mediaURL: "https://media.example/cover",
			directPath: "/pps/biz-cover-photo/cover",
			metaHMAC: "cover-token",
			timestamp: 1_700_000_001,
			fileID: 99
		))
		let client = WhatsAppClient(transportFactory: { _ in transport }, mediaUploader: mediaUploader)
		try await client.connect()

		let photoData = Data("business cover photo".utf8)
		let task = Task {
			try await client.updateBusinessCoverPhoto(photoData, requestID: "cover-update-1")
		}
		let request = try await transport.waitForSentNode()

		#expect(await mediaUploader.calls == [
			MediaUploadCall(
				data: photoData,
				fileEncSha256Base64: "TPzDC3tXyq11WYY0mCqeNETX7+p9Q0iL/xurTr2ZRR0=",
				mediaType: .businessCoverPhoto
			)
		])
		#expect(request.attrs["id"] == "cover-update-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "w:biz")
		let profile = try #require(request.firstChild(named: "business_profile"))
		#expect(profile.attrs["v"] == "3")
		#expect(profile.attrs["mutation_type"] == "delta")
		let coverPhoto = try #require(profile.firstChild(named: "cover_photo"))
		#expect(coverPhoto.attrs["id"] == "99")
		#expect(coverPhoto.attrs["op"] == "update")
		#expect(coverPhoto.attrs["token"] == "cover-token")
		#expect(coverPhoto.attrs["ts"] == "1700000001")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "cover-update-1", "type": "result"]))
		#expect(try await task.value == 99)
	}

	@Test("Baileys cover photo update alias sends update mutation")
	func baileysCoverPhotoUpdateAliasSendsUpdateMutation() async throws {
		let transport = MockBusinessWebSocketTransport()
		let mediaUploader = StubWhatsAppMediaUploader(result: MediaUploadResult(
			mediaURL: "https://media.example/cover",
			directPath: "/pps/biz-cover-photo/cover",
			metaHMAC: "alias-token",
			timestamp: 1_700_000_002,
			fileID: 100
		))
		let client = WhatsAppClient(transportFactory: { _ in transport }, mediaUploader: mediaUploader)
		try await client.connect()

		let task = Task {
			try await client.updateCoverPhoto(Data([0x01, 0x02]), requestID: "cover-update-alias")
		}
		let request = try await transport.waitForSentNode()
		let coverPhoto = try #require(request.firstChild(named: "business_profile")?.firstChild(named: "cover_photo"))
		#expect(coverPhoto.attrs["id"] == "100")
		#expect(coverPhoto.attrs["op"] == "update")
		#expect(coverPhoto.attrs["token"] == "alias-token")
		#expect(coverPhoto.attrs["ts"] == "1700000002")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "cover-update-alias", "type": "result"]))
		#expect(try await task.value == 100)
	}

	@Test("throws when business cover photo upload response misses required fields")
	func throwsWhenBusinessCoverPhotoUploadResponseMissesRequiredFields() async throws {
		let transport = MockBusinessWebSocketTransport()
		let mediaUploader = StubWhatsAppMediaUploader(result: MediaUploadResult(
			mediaURL: "https://media.example/cover",
			directPath: "/pps/biz-cover-photo/cover"
		))
		let client = WhatsAppClient(transportFactory: { _ in transport }, mediaUploader: mediaUploader)
		try await client.connect()

		await #expect(throws: WhatsAppClientError.missingBusinessCoverPhotoUploadResponse) {
			try await client.updateBusinessCoverPhoto(Data([0x01]), requestID: "cover-update-missing")
		}
	}
}
