import Testing
@testable import WhatsAppWeb

@Suite("Stanza ACK builder")
struct StanzaAckTests {
	@Test("omits error attribute for zero error code")
	func omitsErrorAttributeForZeroErrorCode() {
		let ack = StanzaAck.build(
			for: BinaryNode(tag: "message", attrs: ["id": "msg-1", "from": "123@s.whatsapp.net"]),
			errorCode: 0
		)

		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: ["id": "msg-1", "to": "123@s.whatsapp.net", "class": "message"]
		))
	}
}
