import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Crypto digest helpers")
struct CryptoDigestTests {
	@Test("hashes SHA-256 like Node crypto")
	func hashesSHA256LikeNodeCrypto() throws {
		#expect(CryptoDigest.sha256(data) == expectedSHA256)
	}

	@Test("signs HMAC-SHA256 like Node crypto")
	func signsHMACSHA256LikeNodeCrypto() throws {
		#expect(CryptoDigest.hmacSign(data, key: key) == expectedHMACSHA256)
	}

	@Test("signs HMAC-SHA512 like Node crypto")
	func signsHMACSHA512LikeNodeCrypto() throws {
		#expect(CryptoDigest.hmacSign(data, key: key, variant: .sha512) == expectedHMACSHA512)
	}

	private let data = try! hexData("53776966744261696c6579732063727970746f206469676573742066697874757265")
	private let key = try! hexData("000102030405060708090a0b0c0d0e0f")
	private let expectedSHA256 = try! hexData("462747657df363c57fb227d78974e05ae05435bf9da053bc305a3750395ccc7e")
	private let expectedHMACSHA256 = try! hexData("8c260eabe918e5531acdd692545a025a2ed1b34e9af31f961b4923a03032d7e5")
	private let expectedHMACSHA512 = try! hexData("0626f7748268ef252096ca4f8f30022068f5f4ae8159ba0bb2852487906ec5fdab43aadfaff5ae4db19e9b3059de7ba84f008691a8ac1bc5f0bedc3f9411272f")
}
