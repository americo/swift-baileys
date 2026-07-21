import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp version resolver", .serialized)
struct WhatsAppVersionResolverTests {
	@Test("parses Baileys Defaults version")
	func parsesBaileysDefaultsVersion() {
		let source = """
		export const NOISE_MODE = 'Noise_XX_25519_AESGCM_SHA256\0\0\0\0'
		const version = [2, 3000, 123456]
		export const Browsers = {
		"""

		#expect(WhatsAppVersionResolver.parseBaileysVersion(from: source) == WhatsAppVersion(2, 3000, 123456))
	}

	@Test("parses WhatsApp web client revision")
	func parsesWhatsAppWebClientRevision() {
		#expect(WhatsAppVersionResolver.parseClientRevision(from: #"self.__WB_MANIFEST={"client_revision":987654}"#) == 987654)
		#expect(WhatsAppVersionResolver.parseClientRevision(from: #"\"client_revision\": 123"#) == 123)
	}

	@Test("fetches latest Baileys version from Defaults source")
	func fetchesLatestBaileysVersionFromDefaultsSource() async throws {
		URLProtocolWhatsAppVersionMock.handler = { request in
			#expect(request.url?.host == "raw.githubusercontent.com")
			#expect(request.url?.path == "/WhiskeySockets/Baileys/master/src/Defaults/index.ts")
			let response = HTTPURLResponse(
				url: request.url!,
				statusCode: 200,
				httpVersion: nil,
				headerFields: ["Content-Type": "text/plain"]
			)!
			return (response, Data("const version = [2, 3000, 999]\n".utf8))
		}
		defer { URLProtocolWhatsAppVersionMock.handler = nil }

		let result = await WhatsAppVersionResolver.fetchLatestBaileysVersion(session: makeMockSession())

		#expect(result == LatestWhatsAppVersionResult(version: WhatsAppVersion(2, 3000, 999), isLatest: true))
	}

	@Test("fetches latest WhatsApp web revision with Baileys headers")
	func fetchesLatestWhatsAppWebRevisionWithBaileysHeaders() async throws {
		let store = URLProtocolWhatsAppVersionRequestStore()
		URLProtocolWhatsAppVersionMock.handler = { request in
			store.append(request)
			let response = HTTPURLResponse(
				url: request.url!,
				statusCode: 200,
				httpVersion: nil,
				headerFields: ["Content-Type": "application/javascript"]
			)!
			return (response, Data(#"self.__WB_MANIFEST={"client_revision":777}"#.utf8))
		}
		defer { URLProtocolWhatsAppVersionMock.handler = nil }

		let result = await WhatsAppVersionResolver.fetchLatestWaWebVersion(session: makeMockSession())

		let request = try #require(store.requests.first)
		#expect(request.url == URL(string: "https://web.whatsapp.com/sw.js")!)
		#expect(request.value(forHTTPHeaderField: "sec-fetch-site") == "none")
		#expect(request.value(forHTTPHeaderField: "user-agent")?.contains("Chrome/131.0.0.0") == true)
		#expect(result == LatestWhatsAppVersionResult(version: WhatsAppVersion(2, 3000, 777), isLatest: true))
	}

	@Test("falls back to bundled version when fetch result is unusable")
	func fallsBackToBundledVersionWhenFetchResultIsUnusable() async {
		URLProtocolWhatsAppVersionMock.handler = { request in
			let response = HTTPURLResponse(
				url: request.url!,
				statusCode: 500,
				httpVersion: nil,
				headerFields: ["Content-Type": "text/plain"]
			)!
			return (response, Data("server error".utf8))
		}
		defer { URLProtocolWhatsAppVersionMock.handler = nil }

		let result = await WhatsAppVersionResolver.fetchLatestBaileysVersion(session: makeMockSession())

		#expect(result.version == WhatsAppVersionResolver.bundledBaileysVersion)
		#expect(result.isLatest == false)
		#expect(result.errorDescription != nil)
	}

	private func makeMockSession() -> URLSession {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [URLProtocolWhatsAppVersionMock.self]
		return URLSession(configuration: configuration)
	}
}

private final class URLProtocolWhatsAppVersionRequestStore: @unchecked Sendable {
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

private final class URLProtocolWhatsAppVersionMock: URLProtocol, @unchecked Sendable {
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
