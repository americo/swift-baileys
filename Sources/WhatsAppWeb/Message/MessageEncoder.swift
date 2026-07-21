import Foundation
import Security

struct MessageEncoder {
	private let randomByte: @Sendable () throws -> UInt8

	init(randomByte: @escaping @Sendable () throws -> UInt8 = MessageEncoder.secureRandomByte) {
		self.randomByte = randomByte
	}

	func encode(_ message: Proto_Message) throws -> Data {
		try MessagePadding.padded(message.serializedData(), randomByte: randomByte)
	}

	static func encodeNewsletterMessage(_ message: Proto_Message) throws -> Data {
		try message.serializedData()
	}

	private static func secureRandomByte() throws -> UInt8 {
		var byte: UInt8 = 0
		let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
		guard status == errSecSuccess else {
			throw MessageEncoderError.randomByteGenerationFailed(status)
		}

		return byte
	}
}

enum MessageEncoderError: Error, Equatable {
	case randomByteGenerationFailed(OSStatus)
}
