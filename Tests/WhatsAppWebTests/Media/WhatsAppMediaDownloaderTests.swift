import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp media downloader")
struct WhatsAppMediaDownloaderTests {
	@Test("downloads and decrypts media")
	func downloadsAndDecryptsMedia() async throws {
		let encryptedFile = try Data(hexString: "3a3018e9b6b731f67593006398f95c50dc0d3938ce1c2652b64845c2c9eeb87b5ecae5e287aaeebc57b1")
		let transport = StubMediaDownloadTransport(data: encryptedFile)
		let downloader = WhatsAppMediaDownloader(transport: transport)
		let url = URL(string: "https://mmg.whatsapp.net/v/t62.7118-24/media")!

		let plaintext = try await downloader.download(MediaDownloadRequest(
			url: url,
			mediaKey: try Data(hexString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"),
			mediaType: .image,
			fileEncSHA256: try Data(hexString: "00f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d03"),
			fileSHA256: try Data(hexString: "fe07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")
		))

		#expect(plaintext == Data("swift baileys media fixture".utf8))
		#expect(await transport.urls == [url])
	}

	@Test("rejects invalid media download requests before transport")
	func rejectsInvalidMediaDownloadRequestsBeforeTransport() async throws {
		let transport = StubMediaDownloadTransport(data: Data([0x01]))
		let downloader = WhatsAppMediaDownloader(transport: transport)
		let url = URL(string: "https://mmg.whatsapp.net/v/t62.7118-24/media")!

		await #expect(throws: MediaDownloadRequestValidationError.emptyMediaKey) {
			try await downloader.download(validRequest(url: url, mediaKey: Data()))
		}
		await #expect(throws: MediaDownloadRequestValidationError.invalidFileEncSHA256) {
			try await downloader.download(validRequest(url: url, fileEncSHA256: Data(repeating: 0x01, count: 31)))
		}
		await #expect(throws: MediaDownloadRequestValidationError.invalidFileSHA256) {
			try await downloader.download(validRequest(url: url, fileSHA256: Data(repeating: 0x02, count: 31)))
		}
		#expect(await transport.urls.isEmpty)
	}
}

private func validRequest(
	url: URL,
	mediaKey: Data = Data(repeating: 0x01, count: 32),
	fileEncSHA256: Data = Data(repeating: 0x02, count: 32),
	fileSHA256: Data = Data(repeating: 0x03, count: 32)
) -> MediaDownloadRequest {
	MediaDownloadRequest(
		url: url,
		mediaKey: mediaKey,
		mediaType: .image,
		fileEncSHA256: fileEncSHA256,
		fileSHA256: fileSHA256
	)
}

private actor StubMediaDownloadTransport: MediaDownloading {
	private let data: Data
	private(set) var urls: [URL] = []

	init(data: Data) {
		self.data = data
	}

	func download(from url: URL) async throws -> Data {
		urls.append(url)
		return data
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw WhatsAppMediaDownloaderTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum WhatsAppMediaDownloaderTestError: Error {
	case invalidHex
}
