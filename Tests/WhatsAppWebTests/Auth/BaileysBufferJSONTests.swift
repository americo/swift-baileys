import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Baileys Buffer JSON")
struct BaileysBufferJSONTests {
	@Test("encodes Data as Baileys BufferJSON objects")
	func encodesDataAsBaileysBufferJSONObjects() throws {
		let object = BaileysBufferJSON.object(from: Data([1, 2, 3]))

		#expect(object["type"] as? String == "Buffer")
		#expect(object["data"] as? String == "AQID")
		#expect(try BaileysBufferJSON.data(from: object) == Data([1, 2, 3]))
	}

	@Test("decodes numeric byte objects from legacy Buffer JSON")
	func decodesNumericByteObjectsFromLegacyBufferJSON() throws {
		let object: [String: Any] = ["2": 3, "0": 1, "1": 2]

		#expect(try BaileysBufferJSON.data(from: object) == Data([1, 2, 3]))
	}

	@Test("decodes credentials written with Baileys BufferJSON byte fields")
	func decodesCredentialsWrittenWithBaileysBufferJSONByteFields() throws {
		let json = """
		{
			"noiseKey": {
				"privateKey": { "type": "Buffer", "data": "AQ==" },
				"publicKey": { "type": "Buffer", "data": "Ag==" }
			},
			"pairingEphemeralKeyPair": {
				"privateKey": { "type": "Buffer", "data": "Aw==" },
				"publicKey": { "type": "Buffer", "data": "BA==" }
			},
			"signedIdentityKey": {
				"privateKey": { "type": "Buffer", "data": "BQ==" },
				"publicKey": { "type": "Buffer", "data": "Bg==" }
			},
			"signedPreKey": {
				"keyPair": {
					"privateKey": { "type": "Buffer", "data": "Bw==" },
					"publicKey": { "type": "Buffer", "data": "CA==" }
				},
				"signature": { "0": 9 },
				"keyID": 1
			},
			"registrationID": 559,
			"advSecretKey": "adv-secret",
			"signalIdentities": [],
			"nextPreKeyID": 1,
			"firstUnuploadedPreKeyID": 1,
			"accountSyncCounter": 0,
			"accountSettings": { "unarchiveChats": false },
			"registered": true,
			"routingInfo": { "type": "Buffer", "data": "ChQ=" },
			"processedHistoryMessages": []
		}
		"""

		let credentials = try BaileysBufferJSON.decode(AuthenticationCredentials.self, from: Data(json.utf8))

		#expect(credentials.noiseKey.privateKey == Data([1]))
		#expect(credentials.signedPreKey.signature == Data([9]))
		#expect(credentials.routingInfo == Data([10, 20]))
	}

	@Test("throws typed error for non-buffer objects")
	func throwsTypedErrorForNonBufferObjects() {
		#expect(throws: BaileysBufferJSONError.invalidBufferObject) {
			try BaileysBufferJSON.data(from: ["type": "Buffer", "data": 1])
		}
	}
}
