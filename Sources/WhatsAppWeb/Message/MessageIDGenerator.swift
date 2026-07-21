import CryptoKit
import Foundation
import Security

public struct MessageIDGenerator: Sendable {
	private let unixTimestampSeconds: @Sendable () -> UInt64
	private let randomBytes: @Sendable (Int) throws -> Data

	public init(
		unixTimestampSeconds: @escaping @Sendable () -> UInt64 = {
			UInt64(UnixTimestamp.seconds())
		},
		randomBytes: @escaping @Sendable (Int) throws -> Data = Self.secureRandomBytes(count:)
	) {
		self.unixTimestampSeconds = unixTimestampSeconds
		self.randomBytes = randomBytes
	}

	public func generateV2(userID: String? = nil) throws -> String {
		var data = Data(repeating: 0, count: 44)
		data.replaceSubrange(0..<8, with: BigEndianEncoder.encode(Int(unixTimestampSeconds()), count: 8))

		if let user = JID(userID)?.user {
			let jidBytes = Data("\(user)@c.us".utf8).prefix(20)
			data.replaceSubrange(8..<(8 + jidBytes.count), with: jidBytes)
		}

		let random = try randomBytes(16)
		guard random.count == 16 else {
			throw MessageIDGeneratorError.invalidRandomByteCount
		}

		data.replaceSubrange(28..<44, with: random)
		let hash = SHA256.hash(data: data)
		return "3EB0" + Data(hash).prefix(9).map { String(format: "%02X", $0) }.joined()
	}

	public func generate() throws -> String {
		let random = try randomBytes(18)
		guard random.count == 18 else {
			throw MessageIDGeneratorError.invalidRandomByteCount
		}

		return "3EB0" + random.map { String(format: "%02X", $0) }.joined()
	}

	public static func secureRandomBytes(count: Int) throws -> Data {
		var data = Data(repeating: 0, count: count)
		let status = data.withUnsafeMutableBytes {
			SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
		}

		guard status == errSecSuccess else {
			throw MessageIDGeneratorError.randomGenerationFailed(status)
		}

		return data
	}
}

public enum MessageIDGeneratorError: Error, Equatable, Sendable {
	case invalidRandomByteCount
	case randomGenerationFailed(OSStatus)
}

public enum MessageIDDevice: String, Equatable, Sendable {
	case iOS
	case web
	case android
	case desktop
	case unknown
}

public enum MessageIDDeviceClassifier {
	public static func device(for id: String) -> MessageIDDevice {
		if id.hasPrefix("3A"), id.count == 20 {
			return .iOS
		}

		if id.hasPrefix("3E"), id.count == 22 {
			return .web
		}

		if id.count == 21 || id.count == 32 {
			return .android
		}

		if id.hasPrefix("3F") || id.count == 18 {
			return .desktop
		}

		return .unknown
	}
}

public enum ParticipantHashGenerator {
	public static func generateV2(participants: [String]) -> String {
		let joinedParticipants = participants.sorted().joined()
		let hash = Data(SHA256.hash(data: Data(joinedParticipants.utf8))).base64EncodedString()
		return "2:" + String(hash.prefix(6))
	}
}
