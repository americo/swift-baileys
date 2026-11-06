import CryptoKit
import Foundation

/// STUN framing used by the WhatsApp relay: RFC 5389 TLV messages with MESSAGE-INTEGRITY
/// (HMAC-SHA1) and FINGERPRINT (CRC-32), plus WhatsApp's own ping/pong.
public enum CallSTUN {
	public static let magicCookie: UInt32 = 0x2112_a442
	public static let fingerprintXOR: UInt32 = 0x5354_554e

	public static let bindingRequest: UInt16 = 0x0001
	public static let allocateRequest: UInt16 = 0x0003
	public static let bindingSuccess: UInt16 = 0x0101
	public static let bindingError: UInt16 = 0x0111
	public static let allocateSuccess: UInt16 = 0x0103
	public static let allocateError: UInt16 = 0x0113
	public static let whatsAppPing: UInt16 = 0x0801
	public static let whatsAppPong: UInt16 = 0x0802

	public static let attributeErrorCode: UInt16 = 0x0009
	public static let attributeMessageIntegrity: UInt16 = 0x0008
	public static let attributeFingerprint: UInt16 = 0x8028
	public static let attributeRelayToken: UInt16 = 0x4000

	public struct Attribute: Equatable, Sendable {
		public let type: UInt16
		public let value: Data
	}

	/// One TLV attribute, padded to a 4-byte boundary.
	public static func attribute(_ type: UInt16, _ value: Data) -> Data {
		var out = Data()
		out.append(contentsOf: bigEndian(type))
		out.append(contentsOf: bigEndian(UInt16(value.count)))
		out.append(value)
		out.append(Data(count: padding(value.count)))
		return out
	}

	/// Encodes a request. `integrityKey` appends MESSAGE-INTEGRITY computed over a header whose
	/// length already counts that attribute; `includeFingerprint` then appends FINGERPRINT.
	public static func encode(
		type: UInt16,
		transactionID: Data,
		attributes: Data = Data(),
		integrityKey: Data? = nil,
		includeFingerprint: Bool = false
	) -> Data {
		precondition(transactionID.count == 12, "STUN transaction ids are 12 bytes")
		var body = attributes

		if let integrityKey {
			let header = pseudoHeader(type: type, length: body.count + 24, transactionID: transactionID)
			var message = header
			message.append(body)
			let mac = HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: integrityKey))
			body.append(attribute(attributeMessageIntegrity, Data(mac)))
		}

		if includeFingerprint {
			var input = pseudoHeader(type: type, length: body.count + 8, transactionID: transactionID)
			input.append(body)
			body.append(attribute(attributeFingerprint, Data(bigEndian(crc32(input) ^ fingerprintXOR))))
		}

		var out = pseudoHeader(type: type, length: body.count, transactionID: transactionID)
		out.append(body)
		return out
	}

	/// WhatsApp consent ping: type 0x0801, empty body.
	public static func ping(transactionID: Data) -> Data {
		encode(type: whatsAppPing, transactionID: transactionID)
	}

	/// XOR-encoded IPv4:port (6 bytes) as used by the relay endpoint attribute.
	public static func xorRelayEndpoint(ipv4: String, port: UInt16) -> Data? {
		let octets = ipv4.split(separator: ".").compactMap { UInt8($0) }
		guard octets.count == 4 else {
			return nil
		}

		let cookie = bigEndian(magicCookie)
		var out = Data(bigEndian(port ^ UInt16(magicCookie >> 16)))
		for index in 0..<4 {
			out.append(octets[index] ^ cookie[index])
		}

		return out
	}

	// MARK: Parsing

	public static func isSTUN(_ data: Data) -> Bool {
		data.count >= 2 && data[data.startIndex] & 0xc0 == 0
	}

	public static func messageType(_ data: Data) -> UInt16? {
		guard data.count >= 2 else {
			return nil
		}

		return UInt16(data[data.startIndex] & 0x3f) << 8 | UInt16(data[data.startIndex + 1])
	}

	public static func transactionID(_ data: Data) -> Data? {
		data.count >= 20 ? data.subdata(in: (data.startIndex + 8)..<(data.startIndex + 20)) : nil
	}

	/// A full message: STUN-prefixed, 20-byte header, magic cookie, and a 4-aligned body that did
	/// not arrive truncated. Garbage that merely starts like STUN must not drive allocate decisions.
	public static func isComplete(_ data: Data) -> Bool {
		let bytes = Array(data)
		guard isSTUN(data), bytes.count >= 20, Array(bytes[4..<8]) == bigEndian(magicCookie) else {
			return false
		}

		let bodyLength = Int(bytes[2]) << 8 | Int(bytes[3])
		return bodyLength % 4 == 0 && bytes.count >= 20 + bodyLength
	}

	public static func isAllocateOrBindingSuccess(_ data: Data) -> Bool {
		isComplete(data) && [allocateSuccess, bindingSuccess].contains(messageType(data))
	}

	public static func isAllocateError(_ data: Data) -> Bool {
		isComplete(data) && messageType(data) == allocateError
	}

	public static func isPong(_ data: Data, transactionID expected: Data? = nil) -> Bool {
		guard isSTUN(data), messageType(data) == whatsAppPong else {
			return false
		}

		guard let expected, !expected.isEmpty else {
			return true
		}

		return transactionID(data) == expected
	}

	public static func attributes(of data: Data) -> [Attribute] {
		let bytes = Array(data)
		guard isSTUN(data), bytes.count >= 20 else {
			return []
		}

		var result = [Attribute]()
		var offset = 20
		while offset + 4 <= bytes.count {
			let type = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
			let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
			offset += 4
			guard offset + length <= bytes.count else {
				break
			}

			result.append(Attribute(type: type, value: Data(bytes[offset..<offset + length])))
			offset += length + padding(length)
		}

		return result
	}

	/// Numeric error code (`class * 100 + number`) of an allocate or binding error response. The
	/// value must lie inside the declared body.
	public static func errorCode(_ data: Data) -> Int? {
		let bytes = Array(data)
		guard isComplete(data), let type = messageType(data), type == allocateError || type == bindingError else {
			return nil
		}

		let end = min(20 + (Int(bytes[2]) << 8 | Int(bytes[3])), bytes.count)
		var offset = 20
		while offset + 4 <= end {
			let attributeType = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
			let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
			if attributeType == attributeErrorCode, length >= 4, offset + 8 <= end {
				return Int(bytes[offset + 6]) * 100 + Int(bytes[offset + 7])
			}

			offset += 4 + length + padding(length)
		}

		return nil
	}

	// MARK: Primitives

	static func crc32(_ data: Data) -> UInt32 {
		var crc: UInt32 = 0xffff_ffff
		for byte in data {
			crc ^= UInt32(byte)
			for _ in 0..<8 {
				crc = (crc >> 1) ^ (0xedb8_8320 & (0 &- (crc & 1)))
			}
		}

		return ~crc
	}

	private static func pseudoHeader(type: UInt16, length: Int, transactionID: Data) -> Data {
		var header = Data()
		header.append(contentsOf: bigEndian(type))
		header.append(contentsOf: bigEndian(UInt16(length)))
		header.append(contentsOf: bigEndian(magicCookie))
		header.append(transactionID)
		return header
	}

	private static func padding(_ length: Int) -> Int {
		(4 - length % 4) % 4
	}

	private static func bigEndian(_ value: UInt16) -> [UInt8] {
		[UInt8(value >> 8), UInt8(truncatingIfNeeded: value)]
	}

	private static func bigEndian(_ value: UInt32) -> [UInt8] {
		(0..<4).map { UInt8(truncatingIfNeeded: value >> UInt32(24 - 8 * $0)) }
	}
}
