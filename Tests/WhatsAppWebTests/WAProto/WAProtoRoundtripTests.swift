import Testing
@testable import WhatsAppWeb

@Suite("WAProto")
struct WAProtoRoundtripTests {
	@Test("roundtrips WebMessageInfo key fields")
	func roundtripsWebMessageInfoKeyFields() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "258840000000@s.whatsapp.net"
		key.fromMe = true
		key.id = "TEST_MESSAGE_ID"

		var messageInfo = Proto_WebMessageInfo()
		messageInfo.key = key
		messageInfo.messageTimestamp = 1_714_000_000

		let data = try messageInfo.serializedData()
		let decoded = try Proto_WebMessageInfo(serializedBytes: data)

		#expect(decoded.key.remoteJid == "258840000000@s.whatsapp.net")
		#expect(decoded.key.fromMe)
		#expect(decoded.key.id == "TEST_MESSAGE_ID")
		#expect(decoded.messageTimestamp == 1_714_000_000)
	}
}
