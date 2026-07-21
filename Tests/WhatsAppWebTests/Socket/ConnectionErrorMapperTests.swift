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
}
