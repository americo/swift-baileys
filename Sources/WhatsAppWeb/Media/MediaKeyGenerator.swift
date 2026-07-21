import Foundation
import Security

protocol MediaKeyGenerating: Sendable {
	func makeMediaKey() throws -> Data
}

struct SecureMediaKeyGenerator: MediaKeyGenerating {
	func makeMediaKey() throws -> Data {
		let mediaKeyLength = 32
		var data = Data(count: mediaKeyLength)
		let status = data.withUnsafeMutableBytes { buffer in
			SecRandomCopyBytes(kSecRandomDefault, mediaKeyLength, buffer.baseAddress!)
		}

		guard status == errSecSuccess else {
			throw MediaKeyGeneratorError.secureRandomFailed(status)
		}

		return data
	}
}

enum MediaKeyGeneratorError: Error, Equatable, Sendable {
	case secureRandomFailed(OSStatus)
}
