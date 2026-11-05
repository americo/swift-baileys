import CryptoKit
import Foundation

/// What is needed to decrypt an edit of a message: the secret that message was sent with, and who sent it.
public struct MessageSecretContext: Equatable, Sendable {
	public let secret: Data
	public let senderJID: String

	public init(secret: Data, senderJID: String) {
		self.secret = secret
		self.senderJID = senderJID
	}
}

/// Looks up the secret of a message we received earlier, so a later edit of it can be decrypted.
public protocol MessageSecretResolving: Sendable {
	func context(forMessageID messageID: String) async -> MessageSecretContext?
}

/// Newer WhatsApp clients send an edit as a `SecretEncryptedMessage` instead of a plain protocol message.
/// Its payload is AES-GCM encrypted with a key derived from the original message's secret.
struct SecretEncryptedEditCipher: Sendable {
	enum CipherError: Error, Equatable {
		case missingPayload
		case invalidPayloadLength
		case undecryptable
	}

	/// The modification-type labels clients are known to mix into the key derivation.
	static let useCaseLabels = ["Message Edit", "Event Edit"]

	func decrypt(
		_ content: ReceivedSecretEncryptedContent,
		originalMessageID: String,
		originalSenderJID: String,
		editorJID: String,
		secret: Data
	) throws -> ReceivedMessageContent? {
		guard let payload = content.encryptedPayload, let iv = content.encryptedIV else {
			throw CipherError.missingPayload
		}
		guard payload.count >= 16 else { throw CipherError.invalidPayloadLength }

		let tagStart = payload.index(payload.endIndex, offsetBy: -16)
		let nonce = try AES.GCM.Nonce(data: iv)
		let box = try AES.GCM.SealedBox(
			nonce: nonce,
			ciphertext: Data(payload[..<tagStart]),
			tag: Data(payload[tagStart...])
		)
		for sender in Self.variants(of: originalSenderJID) {
			for editor in Self.variants(of: editorJID) {
				let aad = Data("\(originalMessageID)\u{0000}\(editor)".utf8)
				for label in Self.useCaseLabels {
					let info = Data(originalMessageID.utf8) + Data(sender.utf8) + Data(editor.utf8) + Data(label.utf8)
					let key = HKDF<SHA256>.deriveKey(
						inputKeyMaterial: SymmetricKey(data: secret),
						salt: Data(),
						info: info,
						outputByteCount: 32
					)
					guard let plaintext = try? AES.GCM.open(box, using: key, authenticating: aad) else { continue }
					let message = try Proto_Message(serializedBytes: plaintext)
					let parsed = ReceivedMessageContentParser.parse(message)
					if case .messageEdited(let edited)? = parsed { return edited.content }
					return parsed
				}
			}
		}
		throw CipherError.undecryptable
	}

	/// A JID as given, and without its device (`user:device@server` → `user@server`).
	private static func variants(of jid: String) -> [String] {
		guard let at = jid.firstIndex(of: "@") else { return [jid] }
		let user = jid[..<at].prefix { $0 != ":" }
		let bare = String(user + jid[at...])
		return bare == jid ? [jid] : [jid, bare]
	}
}
