import Testing
@testable import WhatsAppWeb

@Suite("Connection error mapper")
struct ConnectionErrorMapperTests {
	@Test("maps stream errors like Baileys")
	func mapsStreamErrorsLikeBaileys() {
		#expect(ConnectionErrorMapper.streamErrorInfo(from: BinaryNode(
			tag: "stream:error",
			content: .nodes([BinaryNode(tag: "conflict")])
		)) == StreamErrorInfo(reason: "conflict", statusCode: DisconnectReasonCode.connectionReplaced))
		#expect(ConnectionErrorMapper.streamErrorInfo(from: BinaryNode(
			tag: "stream:error",
			attrs: ["code": "515"],
			content: .nodes([BinaryNode(tag: "restart")])
		)) == StreamErrorInfo(reason: "restart required", statusCode: DisconnectReasonCode.restartRequired))
		#expect(ConnectionErrorMapper.streamErrorInfo(from: BinaryNode(tag: "stream:error")) == StreamErrorInfo(
			reason: "unknown",
			statusCode: DisconnectReasonCode.badSession
		))
	}

	@Test("maps websocket error descriptions like Baileys")
	func mapsWebSocketErrorDescriptionsLikeBaileys() {
		#expect(ConnectionErrorMapper.statusCode(fromWebSocketErrorDescription: "Unexpected server response: 403") == 403)
		#expect(ConnectionErrorMapper.statusCode(fromWebSocketErrorDescription: "operation timed out") == 408)
		#expect(ConnectionErrorMapper.statusCode(fromWebSocketErrorDescription: "code: ENOTFOUND") == 408)
		#expect(ConnectionErrorMapper.statusCode(fromWebSocketErrorDescription: "boom") == 500)
	}

	@Test("a removed device is a logout, any other conflict a replacement")
	func mapsConflictTypes() {
		#expect(ConnectionErrorMapper.streamErrorInfo(from: BinaryNode(
			tag: "stream:error",
			content: .nodes([BinaryNode(tag: "conflict", attrs: ["type": "device_removed"])])
		)).statusCode == DisconnectReasonCode.loggedOut)
		#expect(ConnectionErrorMapper.streamErrorInfo(from: BinaryNode(
			tag: "stream:error",
			content: .nodes([BinaryNode(tag: "conflict", attrs: ["type": "replaced"])])
		)).statusCode == DisconnectReasonCode.connectionReplaced)
	}

	@Test("reads the login failure reason as a status code")
	func readsFailureReason() {
		#expect(ConnectionErrorMapper.statusCode(fromFailure: BinaryNode(tag: "failure", attrs: ["reason": "405"])) == 405)
		#expect(ConnectionErrorMapper.statusCode(fromFailure: BinaryNode(tag: "failure")) == DisconnectReasonCode.badSession)
	}

	@Test("only transient endings and restarts allow reconnecting")
	func classifiesDisconnects() {
		func kind(_ code: Int) -> WhatsAppDisconnect.Kind { WhatsAppDisconnect(reason: "", statusCode: code).kind }
		#expect(kind(401) == .loggedOut)
		#expect(kind(403) == .loggedOut)
		#expect(kind(406) == .loggedOut)
		#expect(kind(402) == .banned)
		#expect(kind(440) == .replaced)
		#expect(kind(405) == .clientRejected)
		#expect(kind(409) == .clientRejected)
		#expect(kind(411) == .clientRejected)
		#expect(kind(515) == .restartRequired)
		#expect(kind(428) == .transient)
		#expect(kind(408) == .transient)
		#expect(kind(500) == .transient)
		#expect(WhatsAppDisconnect(reason: "", statusCode: 515).allowsReconnect)
		#expect(WhatsAppDisconnect(reason: "", statusCode: 503).allowsReconnect)
		#expect(!WhatsAppDisconnect(reason: "", statusCode: 401).allowsReconnect)
		#expect(!WhatsAppDisconnect(reason: "", statusCode: 440).allowsReconnect)
	}
}

@Suite("WhatsApp version cache")
struct WhatsAppVersionCacheTests {
	actor Counter { var value = 0; func increment() { value += 1 } }

	@Test("reuses a fetched version and refetches after invalidation")
	func reusesFetchedVersion() async {
		let counter = Counter()
		let cache = WhatsAppVersionCache(fetch: {
			await counter.increment()
			return LatestWhatsAppVersionResult(version: WhatsAppVersion(2, 3000, 1), isLatest: true)
		})
		#expect(await cache.version() == WhatsAppVersion(2, 3000, 1))
		#expect(await cache.version() == WhatsAppVersion(2, 3000, 1))
		#expect(await counter.value == 1)
		await cache.invalidate()
		_ = await cache.version()
		#expect(await counter.value == 2)
	}

	@Test("does not keep the fallback of a failed lookup")
	func skipsFallback() async {
		let counter = Counter()
		let cache = WhatsAppVersionCache(fetch: {
			await counter.increment()
			return LatestWhatsAppVersionResult(version: WhatsAppVersionResolver.bundledBaileysVersion, isLatest: false, errorDescription: "offline")
		})
		_ = await cache.version()
		_ = await cache.version()
		#expect(await counter.value == 2)
	}
}

