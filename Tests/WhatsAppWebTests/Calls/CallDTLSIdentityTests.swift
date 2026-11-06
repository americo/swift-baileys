import CryptoKit
import Foundation
import Security
import Testing
@testable import WhatsAppWeb

@Suite("Call DTLS identity")
struct CallDTLSIdentityTests {
	@Test("builds an identity holding both certificate and private key")
	func buildsIdentity() throws {
		let identity = try CallDTLSIdentity.make()

		var certificate: SecCertificate?
		#expect(SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess)
		#expect(certificate.flatMap { SecCertificateCopySubjectSummary($0) as String? } == "wa-voip")

		var key: SecKey?
		#expect(SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess)
		#expect(key != nil)
	}

	@Test("the private key signs what the certificate's public key verifies")
	func keyMatchesCertificate() throws {
		let identity = try CallDTLSIdentity.make()
		var certificate: SecCertificate?
		var key: SecKey?
		SecIdentityCopyCertificate(identity, &certificate)
		SecIdentityCopyPrivateKey(identity, &key)
		let privateKey = try #require(key)
		let publicKey = try #require(certificate.flatMap(SecCertificateCopyKey))

		let message = Data("handshake".utf8) as CFData
		var error: Unmanaged<CFError>?
		let signature = SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256, message, &error)
		let signed = try #require(signature)
		#expect(SecKeyVerifySignature(publicKey, .ecdsaSignatureMessageX962SHA256, message, signed, &error))
	}

	@Test("every identity uses a new key")
	func generatesNewKeys() throws {
		let first = try CallDTLSIdentity.makeCertificate(key: P256.Signing.PrivateKey(), now: Date())
		let second = try CallDTLSIdentity.makeCertificate(key: P256.Signing.PrivateKey(), now: Date())

		#expect(first != second)
		#expect(SecCertificateCreateWithData(nil, first as CFData) != nil)
	}
}
