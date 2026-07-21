import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("URLSession media upload transport", .serialized)
struct URLSessionMediaUploadTransportTests {
	@Test("posts encrypted media and parses upload response")
	func postsEncryptedMediaAndParsesUploadResponse() async throws {
		let store = URLProtocolRequestStore()
		URLProtocolMediaUploadMock.handler = { request in
			store.append(request)
			let body = try #require(request.httpBodyStream.flatMap { stream in
				stream.open()
				defer { stream.close() }
				var data = Data()
				var buffer = [UInt8](repeating: 0, count: 1024)
				while stream.hasBytesAvailable {
					let count = stream.read(&buffer, maxLength: buffer.count)
					if count > 0 {
						data.append(buffer, count: count)
					} else {
						break
					}
				}
				return data
			})
			#expect(body == Data([1, 2, 3, 4]))

			let response = HTTPURLResponse(
				url: request.url!,
				statusCode: 200,
				httpVersion: nil,
				headerFields: ["Content-Type": "application/json"]
			)!
			let payload = Data(
				#"{"url":"https://mmg.whatsapp.net/o1/v/t62.7118-24/uploaded","direct_path":"/v/t62.7118-24/uploaded.enc?ccb=11-4&oh=01","meta_hmac":"meta","ts":42,"fbid":99}"#.utf8
			)
			return (response, payload)
		}
		defer { URLProtocolMediaUploadMock.handler = nil }

		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [URLProtocolMediaUploadMock.self]
		let session = URLSession(configuration: configuration)
		let transport = URLSessionMediaUploadTransport(session: session)
		let request = MediaUploadRequest(
			url: URL(string: "https://upload.whatsapp.net/mms/image/token")!,
			headers: [
				"Content-Type": "application/octet-stream",
				"Origin": "https://web.whatsapp.com"
			]
		)

		let result = try await transport.upload(data: Data([1, 2, 3, 4]), request: request)

		let captured = try #require(store.requests.first)
		#expect(captured.httpMethod == "POST")
		#expect(captured.url?.absoluteString == "https://upload.whatsapp.net/mms/image/token")
		#expect(captured.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
		#expect(captured.value(forHTTPHeaderField: "Origin") == "https://web.whatsapp.com")
		#expect(result == MediaUploadTransportResult(
			mediaURL: "https://mmg.whatsapp.net/o1/v/t62.7118-24/uploaded",
			directPath: "/v/t62.7118-24/uploaded.enc?ccb=11-4&oh=01",
			metaHMAC: "meta",
			timestamp: 42,
			fileID: 99
		))
	}

	@Test("throws typed errors for failed media uploads")
	func throwsTypedErrorsForFailedMediaUploads() async throws {
		URLProtocolMediaUploadMock.handler = { request in
			let response = HTTPURLResponse(
				url: request.url!,
				statusCode: 500,
				httpVersion: nil,
				headerFields: ["Content-Type": "text/plain"]
			)!
			return (response, Data("server error".utf8))
		}
		defer { URLProtocolMediaUploadMock.handler = nil }

		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [URLProtocolMediaUploadMock.self]
		let transport = URLSessionMediaUploadTransport(session: URLSession(configuration: configuration))
		let request = MediaUploadRequest(
			url: URL(string: "https://upload.whatsapp.net/mms/image/token")!,
			headers: [:]
		)

		await #expect(throws: URLSessionMediaUploadTransportError.httpStatus(500, Data("server error".utf8))) {
			_ = try await transport.upload(data: Data([1]), request: request)
		}
	}
}

private final class URLProtocolRequestStore: @unchecked Sendable {
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

private final class URLProtocolMediaUploadMock: URLProtocol, @unchecked Sendable {
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
