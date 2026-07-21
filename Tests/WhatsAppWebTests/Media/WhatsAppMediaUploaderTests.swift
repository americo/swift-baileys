import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp media uploader")
struct WhatsAppMediaUploaderTests {
	@Test("tries media hosts in order and returns upload metadata")
	func triesMediaHostsInOrderAndReturnsUploadMetadata() async throws {
		let connectionResolver = StubMediaConnectionResolver(result: MediaConnectionInfo(
			hosts: [
				MediaConnectionHost(hostname: "first.whatsapp.net", maxContentLengthBytes: 1024),
				MediaConnectionHost(hostname: "second.whatsapp.net", maxContentLengthBytes: 2048)
			],
			auth: "auth/token+value=",
			ttl: 1_200
		))
		let transport = StubMediaUploadTransport(results: [
			nil,
			MediaUploadTransportResult(
				mediaURL: "https://mmg.whatsapp.net/o1/v/t62.7118-24/uploaded",
				directPath: "/v/t62.7118-24/uploaded.enc?ccb=11-4&oh=01",
				metaHMAC: "meta",
				timestamp: 42,
				fileID: 99
			)
		])
		let uploader = WhatsAppMediaUploader(
			connectionResolver: connectionResolver,
			transport: transport
		)
		let encryptedFile = Data([1, 2, 3, 4])

		let result = try await uploader.upload(
			encryptedFile,
			fileEncSha256Base64: "AB+//ZA==",
			mediaType: .image
		)

		#expect(await connectionResolver.calls == 1)
		#expect(await transport.calls.map(\.request.url.absoluteString) == [
			"https://first.whatsapp.net/mms/image/AB-__ZA?auth=auth%2Ftoken%2Bvalue%3D&token=AB-__ZA",
			"https://second.whatsapp.net/mms/image/AB-__ZA?auth=auth%2Ftoken%2Bvalue%3D&token=AB-__ZA"
		])
		#expect(await transport.calls.map(\.data) == [encryptedFile, encryptedFile])
		#expect(result == MediaUploadResult(
			mediaURL: "https://mmg.whatsapp.net/o1/v/t62.7118-24/uploaded",
			directPath: "/v/t62.7118-24/uploaded.enc?ccb=11-4&oh=01",
			metaHMAC: "meta",
			timestamp: 42,
			fileID: 99
		))
	}

	@Test("falls back to the next media host after upload errors")
	func fallsBackToNextMediaHostAfterUploadErrors() async throws {
		let connectionResolver = StubMediaConnectionResolver(result: MediaConnectionInfo(
			hosts: [
				MediaConnectionHost(hostname: "first.whatsapp.net", maxContentLengthBytes: 1024),
				MediaConnectionHost(hostname: "second.whatsapp.net", maxContentLengthBytes: 2048)
			],
			auth: "auth-token",
			ttl: 1_200
		))
		let transport = StubMediaUploadTransport(results: [
			.failure(URLSessionMediaUploadTransportError.httpStatus(500, Data("busy".utf8))),
			.success(MediaUploadTransportResult(
				mediaURL: "https://mmg.whatsapp.net/o1/v/t62.7118-24/uploaded",
				directPath: "/v/t62.7118-24/uploaded.enc"
			))
		])
		let uploader = WhatsAppMediaUploader(connectionResolver: connectionResolver, transport: transport)

		let result = try await uploader.upload(Data([1, 2]), fileEncSha256Base64: "ABCD", mediaType: .image)

		let attemptedHosts = await transport.calls.map { $0.request.url.host() }
		#expect(attemptedHosts == [
			"first.whatsapp.net",
			"second.whatsapp.net"
		])
		#expect(result == MediaUploadResult(
			mediaURL: "https://mmg.whatsapp.net/o1/v/t62.7118-24/uploaded",
			directPath: "/v/t62.7118-24/uploaded.enc"
		))
	}

	@Test("rejects empty upload data before fetching media hosts")
	func rejectsEmptyUploadDataBeforeFetchingMediaHosts() async {
		let connectionResolver = StubMediaConnectionResolver(result: MediaConnectionInfo(
			hosts: [MediaConnectionHost(hostname: "first.whatsapp.net", maxContentLengthBytes: 1024)],
			auth: "auth-token",
			ttl: 1_200
		))
		let transport = StubMediaUploadTransport(results: [MediaUploadTransportResult?]())
		let uploader = WhatsAppMediaUploader(connectionResolver: connectionResolver, transport: transport)

		await #expect(throws: WhatsAppMediaUploaderError.emptyUploadData) {
			try await uploader.upload(Data(), fileEncSha256Base64: "ABCD", mediaType: .image)
		}
		#expect(await connectionResolver.calls == 0)
		#expect(await transport.calls.isEmpty)
	}

	@Test("falls back after empty upload metadata")
	func fallsBackAfterEmptyUploadMetadata() async throws {
		let connectionResolver = StubMediaConnectionResolver(result: MediaConnectionInfo(
			hosts: [
				MediaConnectionHost(hostname: "first.whatsapp.net", maxContentLengthBytes: 1024),
				MediaConnectionHost(hostname: "second.whatsapp.net", maxContentLengthBytes: 2048)
			],
			auth: "auth-token",
			ttl: 1_200
		))
		let transport = StubMediaUploadTransport(results: [
			MediaUploadTransportResult(mediaURL: "", directPath: "/v/t62.7118-24/uploaded.enc"),
			MediaUploadTransportResult(
				mediaURL: "https://mmg.whatsapp.net/o1/v/t62.7118-24/uploaded",
				directPath: "/v/t62.7118-24/uploaded.enc"
			)
		])
		let uploader = WhatsAppMediaUploader(connectionResolver: connectionResolver, transport: transport)

		let result = try await uploader.upload(Data([1, 2]), fileEncSha256Base64: "ABCD", mediaType: .image)

		#expect(await transport.calls.map { $0.request.url.host() } == [
			"first.whatsapp.net",
			"second.whatsapp.net"
		])
		#expect(result == MediaUploadResult(
			mediaURL: "https://mmg.whatsapp.net/o1/v/t62.7118-24/uploaded",
			directPath: "/v/t62.7118-24/uploaded.enc"
		))
	}
}

private actor StubMediaConnectionResolver: MediaConnectionResolving {
	private let result: MediaConnectionInfo
	private(set) var calls = 0

	init(result: MediaConnectionInfo) {
		self.result = result
	}

	func fetchConnection() async throws -> MediaConnectionInfo {
		calls += 1
		return result
	}
}

private actor StubMediaUploadTransport: MediaUploading {
	private var results: [Result<MediaUploadTransportResult?, any Error>]
	private(set) var calls: [MediaUploadTransportCall] = []

	init(results: [MediaUploadTransportResult?]) {
		self.results = results.map(Result.success)
	}

	init(results: [Result<MediaUploadTransportResult?, any Error>]) {
		self.results = results
	}

	func upload(data: Data, request: MediaUploadRequest) async throws -> MediaUploadTransportResult? {
		calls.append(MediaUploadTransportCall(data: data, request: request))
		return try results.removeFirst().get()
	}
}

private struct MediaUploadTransportCall: Equatable, Sendable {
	let data: Data
	let request: MediaUploadRequest
}
