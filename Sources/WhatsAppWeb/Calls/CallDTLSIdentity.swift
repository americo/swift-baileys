import CryptoKit
import Foundation
import Security

public enum CallDTLSIdentityError: Error, Equatable, Sendable {
	case importFailed(OSStatus)
	case noIdentity
	case unavailable
}

/// A throwaway self-signed client certificate for the DTLS handshake with the call relay.
///
/// The relay asks for a client certificate but media is authenticated by the call key, so nothing
/// depends on this identity beyond the handshake completing. A fresh key per connection means no
/// private key ships with the library. The Security framework has no public call that pairs a
/// certificate with a key in memory, so the pair goes through an in-memory PKCS#12 import.
enum CallDTLSIdentity {
	private static let commonName = "wa-voip"
	private static let password = "wa-voip"

	static func make(now: Date = Date()) throws -> SecIdentity {
		guard #available(macOS 15.0, iOS 18.0, *) else {
			throw CallDTLSIdentityError.unavailable
		}

		let key = P256.Signing.PrivateKey()
		let certificate = try makeCertificate(key: key, now: now)
		let archive = try makePKCS12(certificate: certificate, key: key)
		let options: [String: Any] = [
			kSecImportExportPassphrase as String: password,
			kSecImportToMemoryOnly as String: true
		]

		var items: CFArray?
		let status = SecPKCS12Import(archive as CFData, options as CFDictionary, &items)
		guard status == errSecSuccess else {
			throw CallDTLSIdentityError.importFailed(status)
		}
		guard let entries = items as? [[String: Any]],
			  let value = entries.first?[kSecImportItemIdentity as String] else {
			throw CallDTLSIdentityError.noIdentity
		}

		// The dictionary value is always a SecIdentity; CF types cannot be conditionally cast.
		return value as! SecIdentity
	}

	// MARK: X.509

	static func makeCertificate(key: P256.Signing.PrivateKey, now: Date) throws -> Data {
		let signatureAlgorithm = DER.sequence(DER.oid([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02]))
		let name = DER.sequence(DER.set(DER.sequence(
			DER.oid([0x55, 0x04, 0x03]) + DER.tagged(0x0c, Array(commonName.utf8))
		)))
		var serial = (0..<16).map { _ in UInt8.random(in: 0...255) }
		serial[0] &= 0x7f
		serial[0] |= 0x40

		let validity = DER.sequence(
			DER.utcTime(now.addingTimeInterval(-86_400)) + DER.utcTime(now.addingTimeInterval(86_400 * 30))
		)
		let tbs = DER.sequence(
			DER.tagged(0xa0, DER.integer([2]))
				+ DER.integer(serial)
				+ signatureAlgorithm
				+ name
				+ validity
				+ name
				+ Array(key.publicKey.derRepresentation)
		)
		let signature = try key.signature(for: Data(tbs)).derRepresentation
		return Data(DER.sequence(tbs + signatureAlgorithm + DER.tagged(0x03, [0] + Array(signature))))
	}

	// MARK: PKCS#12

	static func makePKCS12(certificate: Data, key: P256.Signing.PrivateKey) throws -> Data {
		let localKeyID = Array(SHA256.hash(data: certificate))
		let attributes = DER.set(DER.sequence(
			DER.oid([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x15])
				+ DER.set(DER.tagged(0x04, localKeyID))
		))
		let certificateBag = DER.sequence(
			DER.oid([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x0c, 0x0a, 0x01, 0x03])
				+ DER.tagged(0xa0, DER.sequence(
					DER.oid([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x16, 0x01])
						+ DER.tagged(0xa0, DER.tagged(0x04, Array(certificate)))
				))
				+ attributes
		)
		// The importer ignores a key in a plain keyBag and returns no identity, so it has to be encrypted.
		let keyBag = DER.sequence(
			DER.oid([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x0c, 0x0a, 0x01, 0x02])
				+ DER.tagged(0xa0, try encryptedPrivateKeyInfo(key))
				+ attributes
		)

		let authenticatedSafe = DER.sequence(
			contentInfo(DER.sequence(certificateBag)) + contentInfo(DER.sequence(keyBag))
		)
		return Data(DER.sequence(
			DER.integer([3])
				+ contentInfo(authenticatedSafe)
				+ macData(over: authenticatedSafe)
		))
	}

	/// PKCS#8 `EncryptedPrivateKeyInfo` using PBES2: PBKDF2-HMAC-SHA256 and AES-256-CBC.
	private static func encryptedPrivateKeyInfo(_ key: P256.Signing.PrivateKey) throws -> [UInt8] {
		let salt = (0..<16).map { _ in UInt8.random(in: 0...255) }
		let iv = (0..<16).map { _ in UInt8.random(in: 0...255) }
		let iterations = 2_048
		let derived = try PBKDF2KeyDerivation.sha256(
			password: Data(password.utf8),
			salt: Data(salt),
			iterations: UInt32(iterations),
			outputByteCount: 32
		)
		let ciphertext = try AESCBCipher.encrypt(key.derRepresentation, key: derived, iv: Data(iv))

		let keyDerivation = DER.sequence(
			DER.oid([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x05, 0x0c])
				+ DER.sequence(
					DER.tagged(0x04, salt)
						+ DER.integer([UInt8(iterations >> 8), UInt8(iterations & 0xff)])
						+ DER.sequence(DER.oid([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x02, 0x09]) + [0x05, 0x00])
				)
		)
		let encryption = DER.sequence(
			DER.oid([0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x01, 0x2a]) + DER.tagged(0x04, iv)
		)
		return DER.sequence(
			DER.sequence(
				DER.oid([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x05, 0x0d])
					+ DER.sequence(keyDerivation + encryption)
			)
				+ DER.tagged(0x04, Array(ciphertext))
		)
	}

	private static func contentInfo(_ content: [UInt8]) -> [UInt8] {
		DER.sequence(
			DER.oid([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x01])
				+ DER.tagged(0xa0, DER.tagged(0x04, content))
		)
	}

	private static func macData(over content: [UInt8]) -> [UInt8] {
		let salt = (0..<16).map { _ in UInt8.random(in: 0...255) }
		let iterations = 2_048
		let macKey = pkcs12MACKey(password: password, salt: salt, iterations: iterations)
		let mac = HMAC<SHA256>.authenticationCode(for: Data(content), using: SymmetricKey(data: macKey))
		let digestInfo = DER.sequence(
			DER.sequence(DER.oid([0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]) + [0x05, 0x00])
				+ DER.tagged(0x04, Array(mac))
		)
		return DER.sequence(
			digestInfo
				+ DER.tagged(0x04, salt)
				+ DER.integer([UInt8(iterations >> 8), UInt8(iterations & 0xff)])
		)
	}

	/// RFC 7292 appendix B key derivation with SHA-256, for the MAC (ID 3). The output is one hash
	/// long, so a single round of the construction is enough.
	static func pkcs12MACKey(password: String, salt: [UInt8], iterations: Int) -> Data {
		let blockSize = 64
		var bmpPassword = [UInt8]()
		for unit in password.utf16 {
			bmpPassword.append(UInt8(unit >> 8))
			bmpPassword.append(UInt8(unit & 0xff))
		}
		bmpPassword += [0, 0]

		func stretched(_ input: [UInt8]) -> [UInt8] {
			guard !input.isEmpty else {
				return []
			}

			let length = blockSize * ((input.count + blockSize - 1) / blockSize)
			return (0..<length).map { input[$0 % input.count] }
		}

		var digest = [UInt8](repeating: 3, count: blockSize) + stretched(salt) + stretched(bmpPassword)
		for _ in 0..<iterations {
			digest = Array(SHA256.hash(data: Data(digest)))
		}

		return Data(digest)
	}
}

/// The handful of DER encodings the certificate and archive above need.
private enum DER {
	static func tagged(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
		[tag] + length(content.count) + content
	}

	static func sequence(_ content: [UInt8]) -> [UInt8] {
		tagged(0x30, content)
	}

	static func set(_ content: [UInt8]) -> [UInt8] {
		tagged(0x31, content)
	}

	static func oid(_ encoded: [UInt8]) -> [UInt8] {
		tagged(0x06, encoded)
	}

	/// `bytes` is a big-endian magnitude; a leading zero keeps it positive when needed.
	static func integer(_ bytes: [UInt8]) -> [UInt8] {
		tagged(0x02, (bytes.first ?? 0) & 0x80 != 0 ? [0] + bytes : bytes)
	}

	static func utcTime(_ date: Date) -> [UInt8] {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "yyMMddHHmmss'Z'"
		return tagged(0x17, Array(formatter.string(from: date).utf8))
	}

	private static func length(_ count: Int) -> [UInt8] {
		if count < 0x80 {
			return [UInt8(count)]
		}

		var remaining = count
		var bytes = [UInt8]()
		while remaining > 0 {
			bytes.insert(UInt8(remaining & 0xff), at: 0)
			remaining >>= 8
		}

		return [0x80 | UInt8(bytes.count)] + bytes
	}
}
