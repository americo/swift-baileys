import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client participant node alias")
struct WhatsAppClientParticipantNodesAliasTests {
	@Test("Baileys createParticipantNodes alias encrypts serialized messages")
	func baileysCreateParticipantNodesAliasEncryptsSerializedMessages() async throws {
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "pkmsg", ciphertext: Data([0xaa])),
			EncryptedMessage(type: "msg", ciphertext: Data([0xbb]))
		])
		let client = WhatsAppClient(messageEncryptor: encryptor)
		let encoded = try MessageContentBuilder.text("hello").serializedData()

		let result = try await client.createParticipantNodes(
			recipientJIDs: ["111:0@s.whatsapp.net", "222:0@s.whatsapp.net"],
			encodedMessage: encoded,
			extraAttributes: ["mediatype": "image"]
		)

		#expect(result.shouldIncludeDeviceIdentity)
		#expect(result.nodes.map { $0.attrs["jid"] } == ["111:0@s.whatsapp.net", "222:0@s.whatsapp.net"])
		#expect(result.nodes[0].firstChild(named: "enc")?.attrs["type"] == "pkmsg")
		#expect(result.nodes[0].firstChild(named: "enc")?.attrs["mediatype"] == "image")
		#expect(result.nodes[1].firstChild(named: "enc")?.attrs["type"] == "msg")
	}

	@Test("Baileys createParticipantNodes alias requires message encryptor")
	func baileysCreateParticipantNodesAliasRequiresMessageEncryptor() async {
		let client = WhatsAppClient()
		let encoded = Data([0x08, 0x01])

		await #expect(throws: WhatsAppClientError.missingMessageEncryptor) {
			try await client.createParticipantNodes(
				recipientJIDs: ["111:0@s.whatsapp.net"],
				encodedMessage: encoded
			)
		}
	}
}
