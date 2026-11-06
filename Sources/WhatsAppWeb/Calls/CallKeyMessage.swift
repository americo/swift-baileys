import Foundation
import Security

/// The Signal-encrypted payload that carries the 32-byte call key inside a call offer: a padded
/// `Message` whose only field is `call.callKey`.
enum CallKeyMessage {
	static func generateCallKey() throws -> Data {
		var bytes = [UInt8](repeating: 0, count: CallMediaCrypto.callKeyLength)
		let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		guard status == errSecSuccess else {
			throw CallKeyMessageError.randomGenerationFailed(status)
		}

		return Data(bytes)
	}

	static func encode(callKey: Data, encoder: MessageEncoder = MessageEncoder()) throws -> Data {
		var message = Proto_Message()
		message.call.callKey = callKey
		return try encoder.encode(message)
	}

	static func callKey(from message: Proto_Message) -> Data? {
		guard message.hasCall, message.call.hasCallKey else {
			return nil
		}

		let key = message.call.callKey
		return key.count >= CallMediaCrypto.callKeyLength ? key : nil
	}
}

enum CallKeyMessageError: Error, Equatable {
	case randomGenerationFailed(OSStatus)
}
