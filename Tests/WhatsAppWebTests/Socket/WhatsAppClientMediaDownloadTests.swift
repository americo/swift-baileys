import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client media download")
struct WhatsAppClientMediaDownloadTests {
	@Test("downloads received media requests through the configured downloader")
	func downloadsReceivedMediaRequestsThroughConfiguredDownloader() async throws {
		let encryptedFile = try Data(hexString: "3a3018e9b6b731f67593006398f95c50dc0d3938ce1c2652b64845c2c9eeb87b5ecae5e287aaeebc57b1")
		let transport = StubClientMediaDownloadTransport(data: encryptedFile)
		let client = WhatsAppClient(
			mediaDownloader: WhatsAppMediaDownloader(transport: transport)
		)
		let url = URL(string: "https://mmg.whatsapp.net/v/t62.7118-24/media")!

		let plaintext = try await client.downloadMedia(MediaDownloadRequest(
			url: url,
			mediaKey: try Data(hexString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"),
			mediaType: .image,
			fileEncSHA256: try Data(hexString: "00f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d03"),
			fileSHA256: try Data(hexString: "fe07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")
		))

		#expect(plaintext == Data("swift baileys media fixture".utf8))
		#expect(await transport.urls == [url])
	}

	@Test("downloads parsed received media content")
	func downloadsParsedReceivedMediaContent() async throws {
		let encryptedFile = try Data(hexString: "3a3018e9b6b731f67593006398f95c50dc0d3938ce1c2652b64845c2c9eeb87b5ecae5e287aaeebc57b1")
		let transport = StubClientMediaDownloadTransport(data: encryptedFile)
		let client = WhatsAppClient(
			mediaDownloader: WhatsAppMediaDownloader(transport: transport)
		)

		let plaintext = try await client.downloadMedia(from: imageContent())

		#expect(plaintext == Data("swift baileys media fixture".utf8))
		#expect(await transport.urls == [URL(string: "https://mmg.whatsapp.net/v/t62.7118-24/media")!])
	}

	@Test("requests reupload once for expired media downloads")
	func requestsReuploadOnceForExpiredMediaDownloads() async throws {
		let encryptedFile = try Data(hexString: "3a3018e9b6b731f67593006398f95c50dc0d3938ce1c2652b64845c2c9eeb87b5ecae5e287aaeebc57b1")
		let originalURL = URL(string: "https://mmg.whatsapp.net/v/expired")!
		let refreshedURL = URL(string: "https://mmg.whatsapp.net/v/refreshed")!
		let transport = StubClientMediaDownloadTransport(results: [
			.failure(URLSessionMediaDownloadTransportError.httpStatus(404, Data("missing".utf8))),
			.success(encryptedFile)
		])
		let client = WhatsAppClient(mediaDownloader: WhatsAppMediaDownloader(transport: transport))
		let request = try imageDownloadRequest(url: originalURL)

		let plaintext = try await client.downloadMedia(request) {
			try imageDownloadRequest(url: refreshedURL)
		}

		#expect(plaintext == Data("swift baileys media fixture".utf8))
		#expect(await transport.urls == [originalURL, refreshedURL])
	}

	@Test("returns nil when parsed content has no downloadable media")
	func returnsNilWhenParsedContentHasNoDownloadableMedia() async throws {
		let transport = StubClientMediaDownloadTransport(data: Data())
		let client = WhatsAppClient(
			mediaDownloader: WhatsAppMediaDownloader(transport: transport)
		)

		let plaintext = try await client.downloadMedia(from: ReceivedMessageContent.text("hello"))

		#expect(plaintext == nil)
		#expect(await transport.urls.isEmpty)
	}
}

private func imageDownloadRequest(url: URL) throws -> MediaDownloadRequest {
	MediaDownloadRequest(
		url: url,
		mediaKey: try Data(hexString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"),
		mediaType: .image,
		fileEncSHA256: try Data(hexString: "00f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d03"),
		fileSHA256: try Data(hexString: "fe07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")
	)
}

private func imageContent() throws -> ReceivedMessageContent {
	.image(ReceivedImageContent(
		url: "https://mmg.whatsapp.net/v/t62.7118-24/media",
		directPath: "/v/t62.7118-24/media",
		mediaKey: try Data(hexString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"),
		fileEncSHA256: try Data(hexString: "00f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d03"),
		fileSHA256: try Data(hexString: "fe07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce"),
		fileLength: 27,
		mediaKeyTimestamp: 1_700_000_000,
		mimetype: "image/jpeg",
		caption: nil,
		jpegThumbnail: nil
	))
}

private actor StubClientMediaDownloadTransport: MediaDownloading {
	private var results: [Result<Data, any Error>]
	private(set) var urls: [URL] = []

	init(data: Data) {
		self.results = [.success(data)]
	}

	init(results: [Result<Data, any Error>]) {
		self.results = results
	}

	func download(from url: URL) async throws -> Data {
		urls.append(url)
		let result = results.isEmpty ? .success(Data()) : results.removeFirst()
		return try result.get()
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw WhatsAppClientMediaDownloadTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum WhatsAppClientMediaDownloadTestError: Error {
	case invalidHex
}
