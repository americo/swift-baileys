import Foundation

enum RegistrationIDGenerator {
	static func generate(randomBytes: (Int) throws -> Data) throws -> Int {
		let bytes = try randomBytes(2)
		guard bytes.count == 2 else {
			throw RegistrationIDGeneratorError.invalidRandomByteCount
		}

		let value = UInt16(bytes[bytes.startIndex]) | (UInt16(bytes[bytes.index(after: bytes.startIndex)]) << 8)
		return Int(value & 16_383)
	}
}

enum RegistrationIDGeneratorError: Error, Equatable, Sendable {
	case invalidRandomByteCount
}
