import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("URLSession media download transport", .serialized)
struct URLSessionMediaDownloadTransportTests {
	@Test("gets encrypted media bytes")
	func getsEncryptedMediaBytes() async throws {
		let store = URLProtocolDownloadRequestStore()
		URLProtocolMediaDownloadMock.handler = { request in
			store.append(request)
			let response = HTTPURLResponse(
				url: request.url!,
				statusCode: 200,
				httpVersion: nil,
				headerFields: ["Content-Type": "application/octet-stream"]
			)!
			return (response, Data([0x01, 0x02, 0x03]))
		}
		defer { URLProtocolMediaDownloadMock.handler = nil }

		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [URLProtocolMediaDownloadMock.self]
		let session = URLSession(configuration: configuration)
		let transport = URLSessionMediaDownloadTransport(session: session)
		let url = URL(string: "https://mmg.whatsapp.net/v/t62.7118-24/media.enc")!

		let data = try await transport.download(from: url)

		let captured = try #require(store.requests.first)
		#expect(captured.httpMethod == "GET")
		#expect(captured.url == url)
		#expect(data == Data([0x01, 0x02, 0x03]))
	}

	@Test("throws typed errors for failed media downloads")
	func throwsTypedErrorsForFailedMediaDownloads() async throws {
		URLProtocolMediaDownloadMock.handler = { request in
			let response = HTTPURLResponse(
				url: request.url!,
				statusCode: 404,
				httpVersion: nil,
				headerFields: ["Content-Type": "text/plain"]
			)!
			return (response, Data("missing".utf8))
		}
		defer { URLProtocolMediaDownloadMock.handler = nil }

		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [URLProtocolMediaDownloadMock.self]
		let transport = URLSessionMediaDownloadTransport(session: URLSession(configuration: configuration))

		await #expect(throws: URLSessionMediaDownloadTransportError.httpStatus(404, Data("missing".utf8))) {
			try await transport.download(from: URL(string: "https://mmg.whatsapp.net/missing.enc")!)
		}
	}
}

private final class URLProtocolDownloadRequestStore: @unchecked Sendable {
	private let lock = NSLock()
	private var storedRequests: [URLRequest] = []

	var requests: [URLRequest] {
		lock.withLock { storedRequests }
	}

	func append(_ request: URLRequest) {
		lock.withLock {
			storedRequests.append(request)
		}
	}
}

private final class URLProtocolMediaDownloadMock: URLProtocol, @unchecked Sendable {
	nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

	override class func canInit(with request: URLRequest) -> Bool {
		true
	}

	override class func canonicalRequest(for request: URLRequest) -> URLRequest {
		request
	}

	override func startLoading() {
		do {
			let handler = try #require(Self.handler)
			let (response, data) = try handler(request)
			client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
			client?.urlProtocol(self, didLoad: data)
			client?.urlProtocolDidFinishLoading(self)
		} catch {
			client?.urlProtocol(self, didFailWithError: error)
		}
	}

	override func stopLoading() {}
}
