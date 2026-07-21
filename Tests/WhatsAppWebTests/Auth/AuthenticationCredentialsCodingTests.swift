import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Authentication credentials coding")
struct AuthenticationCredentialsCodingTests {
	@Test("encodes app-state key id with the Baileys TypeScript key")
	func encodesAppStateKeyIDWithTheBaileysTypeScriptKey() throws {
		let data = try JSONEncoder().encode(sampleCredentials(myAppStateKeyID: "AQIDBAUGBwg="))
		let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

		#expect(object["myAppStateKeyId"] as? String == "AQIDBAUGBwg=")
		#expect(object["myAppStateKeyID"] == nil)
	}

	@Test("decodes app-state key id from the Baileys TypeScript key")
	func decodesAppStateKeyIDFromTheBaileysTypeScriptKey() throws {
		var object = try credentialsObject()
		object["myAppStateKeyId"] = "AQIDBAUGBwg="
		let data = try JSONSerialization.data(withJSONObject: object)

		let credentials = try JSONDecoder().decode(AuthenticationCredentials.self, from: data)

		#expect(credentials.myAppStateKeyID == "AQIDBAUGBwg=")
	}

	@Test("decodes app-state key id from the legacy Swift key")
	func decodesAppStateKeyIDFromTheLegacySwiftKey() throws {
		var object = try credentialsObject()
		object["myAppStateKeyID"] = "legacy-key"
		let data = try JSONSerialization.data(withJSONObject: object)

		let credentials = try JSONDecoder().decode(AuthenticationCredentials.self, from: data)

		#expect(credentials.myAppStateKeyID == "legacy-key")
	}

	@Test("encodes and decodes processed history messages")
	func encodesAndDecodesProcessedHistoryMessages() throws {
		let processed = ProcessedHistoryMessage(
			key: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: false,
				id: "history-id",
				participant: "123:1@s.whatsapp.net"
			),
			messageTimestamp: 1_700_000_007
		)
		let data = try JSONEncoder().encode(sampleCredentials(
			myAppStateKeyID: nil,
			processedHistoryMessages: [processed]
		))
		let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

		#expect((object["processedHistoryMessages"] as? [[String: Any]])?.count == 1)
		#expect(try JSONDecoder().decode(AuthenticationCredentials.self, from: data).processedHistoryMessages == [processed])
	}

	@Test("asserts authenticated user id like Baileys")
	func assertsAuthenticatedUserIDLikeBaileys() throws {
		var credentials = sampleCredentials(myAppStateKeyID: nil)

		#expect(throws: AuthenticationCredentialsValidationError.missingAuthenticatedUser) {
			try credentials.assertMeID()
		}

		credentials.me = WhatsAppUser(id: "")
		#expect(throws: AuthenticationCredentialsValidationError.missingAuthenticatedUser) {
			try credentials.assertMeID()
		}

		credentials.me = WhatsAppUser(id: "123@s.whatsapp.net")
		#expect(try credentials.assertMeID() == "123@s.whatsapp.net")
	}
}

private func credentialsObject() throws -> [String: Any] {
	let data = try JSONEncoder().encode(sampleCredentials(myAppStateKeyID: nil))
	return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func sampleCredentials(
	myAppStateKeyID: String?,
	processedHistoryMessages: [ProcessedHistoryMessage] = []
) -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([6])),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([8])),
			signature: Data([9]),
			keyID: 1
		),
		registrationID: 559,
		advSecretKey: "adv-secret",
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true,
		myAppStateKeyID: myAppStateKeyID,
		processedHistoryMessages: processedHistoryMessages
	)
}
