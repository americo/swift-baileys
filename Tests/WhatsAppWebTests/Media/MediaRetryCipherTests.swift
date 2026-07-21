import CryptoKit
import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Media retry cipher")
struct MediaRetryCipherTests {
	@Test("builds Baileys media retry request receipts")
	func buildsBaileysMediaRetryRequestReceipts() throws {
		let node = try MediaRetryCipher.encryptRetryRequest(
			key: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: true,
				id: "MEDIA-1",
				participant: "456@s.whatsapp.net"
			),
			mediaKey: mediaKey,
			meID: "258840000100:3@s.whatsapp.net",
			randomBytes: { count in Data(repeating: 0x07, count: count) }
		)

		#expect(node.tag == "receipt")
		#expect(node.attrs["id"] == "MEDIA-1")
		#expect(node.attrs["to"] == "258840000100@s.whatsapp.net")
		#expect(node.attrs["type"] == "server-error")

		let encrypt = try #require(node.firstChild(named: "encrypt"))
		#expect(try #require(encrypt.childData(named: "enc_iv")) == Data(repeating: 0x07, count: 12))
		let ciphertext = try #require(encrypt.childData(named: "enc_p"))
		#expect(ciphertext.count > 16)

		let rmr = try #require(node.firstChild(named: "rmr"))
		#expect(rmr.attrs["jid"] == "123@s.whatsapp.net")
		#expect(rmr.attrs["from_me"] == "true")
		#expect(rmr.attrs["participant"] == "456@s.whatsapp.net")
	}

	@Test("decrypts media retry notifications")
	func decryptsMediaRetryNotifications() throws {
		var notification = Proto_MediaRetryNotification()
		notification.stanzaID = "MEDIA-2"
		notification.directPath = "/v/refreshed"
		notification.result = .success
		notification.messageSecret = Data([0x01, 0x02, 0x03])
		let encrypted = try encryptNotification(notification, mediaKey: mediaKey, messageID: "MEDIA-2")

		let decrypted = try MediaRetryCipher.decryptRetryNotification(
			RetriedMedia(ciphertext: encrypted.ciphertext, iv: encrypted.iv),
			mediaKey: mediaKey,
			messageID: "MEDIA-2"
		)

		#expect(decrypted == DecryptedMediaRetryNotification(
			stanzaID: "MEDIA-2",
			directPath: "/v/refreshed",
			resultCode: 1,
			resultStatusCode: 200,
			messageSecret: Data([0x01, 0x02, 0x03])
		))
	}

	@Test("rejects incomplete media retry request keys")
	func rejectsIncompleteMediaRetryRequestKeys() {
		#expect(throws: MediaRetryCipherError.incompleteMessageKey) {
			try MediaRetryCipher.encryptRetryRequest(
				key: WhatsAppMessageKey(remoteJID: nil, fromMe: false, id: "MEDIA-3"),
				mediaKey: mediaKey,
				meID: "258840000100@s.whatsapp.net",
				randomBytes: { count in Data(repeating: 0x07, count: count) }
			)
		}
	}
}

private let mediaKey = Data((0..<32).map(UInt8.init))

private func encryptNotification(
	_ notification: Proto_MediaRetryNotification,
	mediaKey: Data,
	messageID: String
) throws -> RetriedMedia {
	let retryKey = HKDF<SHA256>.deriveKey(
		inputKeyMaterial: SymmetricKey(data: mediaKey),
		salt: Data(),
		info: Data("WhatsApp Media Retry Notification".utf8),
		outputByteCount: 32
	)
	let iv = Data((0..<12).map(UInt8.init))
	let box = try AES.GCM.seal(
		try notification.serializedData(),
		using: retryKey,
		nonce: AES.GCM.Nonce(data: iv),
		authenticating: Data(messageID.utf8)
	)
	return RetriedMedia(ciphertext: box.ciphertext + box.tag, iv: iv)
}
