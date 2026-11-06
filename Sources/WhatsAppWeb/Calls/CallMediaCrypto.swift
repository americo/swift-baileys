import CommonCrypto
import CryptoKit
import Foundation

/// Session keys for the end-to-end SRTP cipher of a 1:1 call.
public struct CallSRTPKeys: Equatable, Sendable {
	public let cipherKey: Data
	public let salt: Data
	public let authKey: Data

	public init(cipherKey: Data, salt: Data, authKey: Data) {
		self.cipherKey = cipherKey
		self.salt = salt
		self.authKey = authKey
	}
}

public enum CallMediaCryptoError: Error, Equatable, Sendable {
	case callKeyTooShort
	case cipherFailure(Int32)
}

/// End-to-end media crypto for 1:1 calls.
///
/// Keys derive from the 32-byte `callKey` exchanged inside the encrypted offer and the participant
/// id (HKDF-SHA256), then expand with the libsrtp AES-CM PRF. Payloads use AES-128-CTR and are
/// authenticated with a truncated HMAC-SHA1 "WARP" tag keyed by the SRTP auth key.
public enum CallMediaCrypto {
	public static let callKeyLength = 32
	public static let warpTagLength = 4
	public static let srtcpAuthTagLength = 10

	private static let rtcpHeaderLength = 8

	// MARK: Key derivation

	/// Keys used for RTP. The participant id is the id of the party that SENDS with these keys.
	public static func deriveRTPKeys(callKey: Data, participantID: String) throws -> CallSRTPKeys {
		try deriveKeys(callKey: callKey, participantID: participantID, labels: (0x00, 0x01, 0x02))
	}

	/// Keys used for RTCP.
	public static func deriveRTCPKeys(callKey: Data, participantID: String) throws -> CallSRTPKeys {
		try deriveKeys(callKey: callKey, participantID: participantID, labels: (0x03, 0x04, 0x05))
	}

	private static func deriveKeys(
		callKey: Data,
		participantID: String,
		labels: (cipher: UInt8, auth: UInt8, salt: UInt8)
	) throws -> CallSRTPKeys {
		guard callKey.count >= callKeyLength else {
			throw CallMediaCryptoError.callKeyTooShort
		}

		let master = hkdfSHA256(
			salt: Data(repeating: 0, count: 32),
			inputKeyMaterial: callKey.prefix(callKeyLength),
			info: Data(participantID.utf8),
			length: 46
		)
		let masterKey = master.prefix(16)
		let masterSalt = master.dropFirst(16).prefix(14)

		return try CallSRTPKeys(
			cipherKey: aesCMKDF(masterKey: masterKey, masterSalt: masterSalt, label: labels.cipher, length: 16),
			salt: aesCMKDF(masterKey: masterKey, masterSalt: masterSalt, label: labels.salt, length: 14),
			authKey: aesCMKDF(masterKey: masterKey, masterSalt: masterSalt, label: labels.auth, length: 20)
		)
	}

	/// Device-qualified participant id used as HKDF `info`: strips the resource, keeps an existing
	/// `:N@lid` device suffix and gives a bare `@lid` an implicit `:0`.
	public static func formatParticipantID(_ jid: String) -> String {
		let bare = jid.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
			.first.map(String.init)?
			.trimmingCharacters(in: .whitespaces) ?? jid
		guard let at = bare.lastIndex(of: "@"), at != bare.startIndex else {
			return bare
		}

		let user = bare[..<at]
		let domain = bare[bare.index(after: at)...]
		if domain == "lid", !user.contains(":") {
			return "\(user):0@\(domain)"
		}

		return bare
	}

	static func hkdfSHA256(salt: Data, inputKeyMaterial: Data, info: Data, length: Int) -> Data {
		let key = HKDF<SHA256>.deriveKey(
			inputKeyMaterial: SymmetricKey(data: inputKeyMaterial),
			salt: salt,
			info: info,
			outputByteCount: length
		)
		return key.withUnsafeBytes { Data($0) }
	}

	/// libsrtp AES-CM PRF: IV is the master salt with `label` XORed into byte 7, zero padded to 16,
	/// and the output is the AES-128-CTR keystream.
	static func aesCMKDF(masterKey: Data, masterSalt: Data, label: UInt8, length: Int) throws -> Data {
		var iv = Data(count: 16)
		iv.replaceSubrange(0..<14, with: masterSalt)
		iv[7] ^= label
		return try aesCTR(key: masterKey, iv: iv, input: Data(count: length))
	}

	// MARK: RTP payload cipher

	/// RTP IV: salt right-aligned into 16 bytes, SSRC XORed at bytes 4-7 and the packet index
	/// (`roc << 16 | seq`) XORed at bytes 8-13.
	public static func rtpIV(salt: Data, ssrc: UInt32, roc: UInt32, sequence: UInt16) -> Data {
		var iv = [UInt8](repeating: 0, count: 16)
		let saltBytes = Array(salt.prefix(14))
		let offset = 14 - saltBytes.count
		for (index, byte) in saltBytes.enumerated() {
			iv[offset + index] = byte
		}
		for index in 0..<4 {
			iv[4 + index] ^= UInt8(truncatingIfNeeded: ssrc >> UInt32(24 - 8 * index))
		}

		let packetIndex = UInt64(roc) << 16 | UInt64(sequence)
		let hi16 = UInt16(truncatingIfNeeded: packetIndex >> 32)
		let lo32 = UInt32(truncatingIfNeeded: packetIndex)
		iv[8] ^= UInt8(hi16 >> 8)
		iv[9] ^= UInt8(truncatingIfNeeded: hi16)
		for index in 0..<4 {
			iv[10 + index] ^= UInt8(truncatingIfNeeded: lo32 >> UInt32(24 - 8 * index))
		}

		return Data(iv)
	}

	/// AES-128-CTR is symmetric, so this both encrypts and decrypts an RTP payload.
	public static func cryptPayload(
		_ payload: Data,
		keys: CallSRTPKeys,
		ssrc: UInt32,
		roc: UInt32,
		sequence: UInt16
	) throws -> Data {
		try aesCTR(
			key: keys.cipherKey,
			iv: rtpIV(salt: keys.salt, ssrc: ssrc, roc: roc, sequence: sequence),
			input: payload
		)
	}

	// MARK: WARP message integrity

	/// `HMAC-SHA1(authKey, packet || roc_be32)`, truncated to `length` bytes.
	public static func warpTag(
		authKey: Data,
		packetWithoutTag: Data,
		roc: UInt32,
		length: Int = warpTagLength
	) -> Data {
		var message = packetWithoutTag
		withUnsafeBytes(of: roc.bigEndian) { message.append(contentsOf: $0) }
		let mac = HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: authKey))
		return Data(mac).prefix(max(1, min(length, 20)))
	}

	/// Constant-time verification of a received tag. Callers must reject a packet whose tag fails
	/// before updating any rollover state.
	public static func verifyWarpTag(
		authKey: Data,
		packetWithoutTag: Data,
		roc: UInt32,
		receivedTag: Data
	) -> Bool {
		guard (1...20).contains(receivedTag.count) else {
			return false
		}

		let expected = warpTag(
			authKey: authKey,
			packetWithoutTag: packetWithoutTag,
			roc: roc,
			length: receivedTag.count
		)
		return constantTimeEqual(expected, receivedTag)
	}

	// MARK: SRTCP

	/// Protects one RTCP packet: the body after the 8-byte header is encrypted, then the
	/// E-flag/index word and an HMAC-SHA1-80 tag are appended.
	public static func protectRTCP(
		_ rtcp: Data,
		keys: CallSRTPKeys,
		senderSSRC: UInt32,
		index: UInt32
	) throws -> Data {
		let split = min(rtcp.count, rtcpHeaderLength)
		let iv = rtpIV(salt: keys.salt, ssrc: senderSSRC, roc: index >> 16, sequence: UInt16(index & 0xffff))
		var out = Data(rtcp.prefix(split))
		try out.append(aesCTR(key: keys.cipherKey, iv: iv, input: Data(rtcp.dropFirst(split))))
		withUnsafeBytes(of: (0x8000_0000 | (index & 0x7fff_ffff)).bigEndian) { out.append(contentsOf: $0) }
		let mac = HMAC<Insecure.SHA1>.authenticationCode(for: out, using: SymmetricKey(data: keys.authKey))
		out.append(Data(mac).prefix(srtcpAuthTagLength))
		return out
	}

	// MARK: Primitives

	static func aesCTR(key: Data, iv: Data, input: Data) throws -> Data {
		guard !input.isEmpty else {
			return Data()
		}

		let blockSize = 16
		let blockCount = (input.count + blockSize - 1) / blockSize
		var counter = [UInt8](iv)
		var counterBlocks = [UInt8]()
		counterBlocks.reserveCapacity(blockCount * blockSize)
		for _ in 0..<blockCount {
			counterBlocks.append(contentsOf: counter)
			incrementBigEndian(&counter)
		}

		var keystream = [UInt8](repeating: 0, count: counterBlocks.count + blockSize)
		var produced = 0
		let status = key.withUnsafeBytes { keyBuffer in
			CCCrypt(
				CCOperation(kCCEncrypt),
				CCAlgorithm(kCCAlgorithmAES),
				CCOptions(kCCOptionECBMode),
				keyBuffer.baseAddress,
				key.count,
				nil,
				counterBlocks,
				counterBlocks.count,
				&keystream,
				keystream.count,
				&produced
			)
		}
		guard status == kCCSuccess else {
			throw CallMediaCryptoError.cipherFailure(status)
		}

		var output = Data(input)
		for index in 0..<output.count {
			output[output.startIndex + index] ^= keystream[index]
		}

		return output
	}

	private static func incrementBigEndian(_ counter: inout [UInt8]) {
		var index = counter.count - 1
		while index >= 0 {
			counter[index] &+= 1
			if counter[index] != 0 {
				return
			}
			index -= 1
		}
	}

	private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
		guard lhs.count == rhs.count else {
			return false
		}

		var difference: UInt8 = 0
		for (a, b) in zip(lhs, rhs) {
			difference |= a ^ b
		}

		return difference == 0
	}
}
