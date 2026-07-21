import Foundation
import Security

struct MDTagPrefixGenerator {
	private let randomBytes: @Sendable (Int) throws -> Data

	init(randomBytes: @escaping @Sendable (Int) throws -> Data = Self.secureRandomBytes(count:)) {
		self.randomBytes = randomBytes
	}

	func generate() throws -> String {
		let bytes = try randomBytes(4)
		guard bytes.count == 4 else {
			throw MDTagPrefixGeneratorError.invalidRandomByteCount
		}

		let first = UInt16(bytes[bytes.startIndex]) << 8 | UInt16(bytes[bytes.index(after: bytes.startIndex)])
		let thirdIndex = bytes.index(bytes.startIndex, offsetBy: 2)
		let second = UInt16(bytes[thirdIndex]) << 8 | UInt16(bytes[bytes.index(after: thirdIndex)])
		return "\(first).\(second)-"
	}

	private static func secureRandomBytes(count: Int) throws -> Data {
		var bytes = [UInt8](repeating: 0, count: count)
		let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
		guard status == errSecSuccess else {
			throw MDTagPrefixGeneratorError.randomBytesFailed(status)
		}

		return Data(bytes)
	}
}

enum MDTagPrefixGeneratorError: Error, Equatable, Sendable {
	case invalidRandomByteCount
	case randomBytesFailed(OSStatus)
}
