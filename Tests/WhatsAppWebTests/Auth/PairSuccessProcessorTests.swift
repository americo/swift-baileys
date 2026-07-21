import Foundation
import CryptoKit
import Testing
@testable import WhatsAppWeb

@Suite("Pair success processor")
struct PairSuccessProcessorTests {
	@Test("rejects pair-success without device identity")
	func rejectsPairSuccessWithoutDeviceIdentity() throws {
		let processor = DefaultPairSuccessProcessor()
		let stanza = BinaryNode(
			tag: "iq",
			attrs: ["id": "pair-1"],
			content: .nodes([
				BinaryNode(
					tag: "pair-success",
					content: .nodes([
						BinaryNode(tag: "device", attrs: ["jid": "123@s.whatsapp.net", "lid": "123@lid"])
					])
				)
			])
		)

		#expect(throws: PairSuccessProcessingError.missingDeviceIdentityOrDevice) {
			try processor.processPairSuccess(stanza: stanza, credentials: sampleCredentials())
		}
	}

	@Test("rejects pair-success without device")
	func rejectsPairSuccessWithoutDevice() throws {
		let processor = DefaultPairSuccessProcessor()
		let stanza = BinaryNode(
			tag: "iq",
			attrs: ["id": "pair-2"],
			content: .nodes([
				BinaryNode(
					tag: "pair-success",
					content: .nodes([
						BinaryNode(tag: "device-identity", content: .data(Data([1, 2, 3])))
					])
				)
			])
		)

		#expect(throws: PairSuccessProcessingError.missingDeviceIdentityOrDevice) {
			try processor.processPairSuccess(stanza: stanza, credentials: sampleCredentials())
		}
	}

	@Test("rejects invalid device identity HMAC payload")
	func rejectsInvalidDeviceIdentityHMACPayload() throws {
		let processor = DefaultPairSuccessProcessor()
		let stanza = BinaryNode(
			tag: "iq",
			attrs: ["id": "pair-3"],
			content: .nodes([
				BinaryNode(
					tag: "pair-success",
					content: .nodes([
						BinaryNode(tag: "device-identity", content: .data(Data([0xff]))),
						BinaryNode(tag: "device", attrs: ["jid": "123@s.whatsapp.net", "lid": "123@lid"])
					])
				)
			])
		)

		#expect(throws: PairSuccessProcessingError.invalidDeviceIdentityHMAC) {
			try processor.processPairSuccess(stanza: stanza, credentials: sampleCredentials())
		}
	}

	@Test("rejects device identity HMAC without details or hmac")
	func rejectsDeviceIdentityHMACWithoutDetailsOrHMAC() throws {
		let processor = DefaultPairSuccessProcessor()
		let emptyHMAC = try Proto_ADVSignedDeviceIdentityHMAC().serializedData()
		let stanza = BinaryNode(
			tag: "iq",
			attrs: ["id": "pair-4"],
			content: .nodes([
				BinaryNode(
					tag: "pair-success",
					content: .nodes([
						BinaryNode(tag: "device-identity", content: .data(emptyHMAC)),
						BinaryNode(tag: "device", attrs: ["jid": "123@s.whatsapp.net", "lid": "123@lid"])
					])
				)
			])
		)

		#expect(throws: PairSuccessProcessingError.missingDeviceIdentityHMACFields) {
			try processor.processPairSuccess(stanza: stanza, credentials: sampleCredentials())
		}
	}

	@Test("rejects device identity HMAC with invalid account signature")
	func rejectsDeviceIdentityHMACWithInvalidAccountSignature() throws {
		let processor = DefaultPairSuccessProcessor()
		var signedDeviceIdentityHMAC = Proto_ADVSignedDeviceIdentityHMAC()
		signedDeviceIdentityHMAC.details = Data([1, 2, 3])
		signedDeviceIdentityHMAC.hmac = Data(repeating: 0, count: 32)
		let stanza = BinaryNode(
			tag: "iq",
			attrs: ["id": "pair-5"],
			content: .nodes([
				BinaryNode(
					tag: "pair-success",
					content: .nodes([
						BinaryNode(
							tag: "device-identity",
							content: .data(try signedDeviceIdentityHMAC.serializedData())
						),
						BinaryNode(tag: "device", attrs: ["jid": "123@s.whatsapp.net", "lid": "123@lid"])
					])
				)
			])
		)

		#expect(throws: PairSuccessProcessingError.invalidAccountSignature) {
			try processor.processPairSuccess(
				stanza: stanza,
				credentials: sampleCredentials(advSecretKey: Data([9, 9, 9]).base64EncodedString())
			)
		}
	}

	@Test("rejects valid account HMAC with invalid signed device identity")
	func rejectsValidAccountHMACWithInvalidSignedDeviceIdentity() throws {
		let processor = DefaultPairSuccessProcessor()
		let details = Data([1, 2, 3])
		let advSecretKey = Data(repeating: 7, count: 32)
		var signedDeviceIdentityHMAC = Proto_ADVSignedDeviceIdentityHMAC()
		signedDeviceIdentityHMAC.details = details
		signedDeviceIdentityHMAC.hmac = Data(HMAC<SHA256>.authenticationCode(
			for: details,
			using: SymmetricKey(data: advSecretKey)
		))
		let stanza = BinaryNode(
			tag: "iq",
			attrs: ["id": "pair-6"],
			content: .nodes([
				BinaryNode(
					tag: "pair-success",
					content: .nodes([
						BinaryNode(
							tag: "device-identity",
							content: .data(try signedDeviceIdentityHMAC.serializedData())
						),
						BinaryNode(tag: "device", attrs: ["jid": "123@s.whatsapp.net", "lid": "123@lid"])
					])
				)
			])
		)

		#expect(throws: PairSuccessProcessingError.invalidSignedDeviceIdentity) {
			try processor.processPairSuccess(
				stanza: stanza,
				credentials: sampleCredentials(advSecretKey: advSecretKey.base64EncodedString())
			)
		}
	}

	@Test("rejects signed device identity with invalid account signature")
	func rejectsSignedDeviceIdentityWithInvalidAccountSignature() throws {
		let processor = DefaultPairSuccessProcessor()
		let stanza = BinaryNode(
			tag: "iq",
			attrs: ["id": "pair-7"],
			content: .nodes([
				BinaryNode(
					tag: "pair-success",
					content: .nodes([
						BinaryNode(
							tag: "device-identity",
							content: .data(try Data(hexString: pairSuccessHMACPayloadHex))
						),
						BinaryNode(tag: "device", attrs: ["jid": "123@s.whatsapp.net", "lid": "123@lid"])
					])
				)
			])
		)

		#expect(throws: PairSuccessProcessingError.failedAccountSignatureVerification) {
			try processor.processPairSuccess(
				stanza: stanza,
				credentials: sampleCredentials(
					advSecretKey: "BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc=",
					signedIdentityPublicKey: Data(repeating: 0, count: 32)
				)
			)
		}
	}

	@Test("uses default libsignal signer for valid pair success")
	func usesDefaultLibsignalSignerForValidPairSuccess() throws {
		let processor = DefaultPairSuccessProcessor()
		let stanza = BinaryNode(
			tag: "iq",
			attrs: ["id": "pair-8"],
			content: .nodes([
				BinaryNode(
					tag: "pair-success",
					content: .nodes([
						BinaryNode(
							tag: "device-identity",
							content: .data(try Data(hexString: pairSuccessHMACPayloadHex))
						),
						BinaryNode(tag: "device", attrs: ["jid": "123@s.whatsapp.net", "lid": "123@lid"])
					])
				)
			])
		)

		let result = try processor.processPairSuccess(
			stanza: stanza,
			credentials: sampleCredentials(
				advSecretKey: "BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc=",
				signedIdentityPrivateKey: Data(repeating: 0x11, count: 32),
				signedIdentityPublicKey: try Data(
					hexString: "65666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f8081828384"
				)
			)
		)
		let pairDeviceSign = try #require(result.reply.firstChild(named: "pair-device-sign"))
		let deviceIdentityNode = try #require(pairDeviceSign.firstChild(named: "device-identity"))
		guard case let .data(encodedIdentity) = deviceIdentityNode.content else {
			Issue.record("expected encoded device identity data")
			return
		}

		let signedDeviceIdentity = try Proto_ADVSignedDeviceIdentity(serializedBytes: encodedIdentity)
		let expectedSignature = try Data(hexString:
			"9d54ee3885b993985afa8df0b3fcd9502e4a598c1f268cddb4c6dc859f316e4827b6cbddb79d6a2a88db8bed8603ea10ea21e1936824004b7e3c1ef302be1181"
		)
		#expect(signedDeviceIdentity.deviceSignature == expectedSignature)
	}

	@Test("builds pair device signature reply with signed device identity")
	func buildsPairDeviceSignatureReplyWithSignedDeviceIdentity() throws {
		let signature = Data(repeating: 0xaa, count: 64)
		let signer = CapturingDeviceSignatureSigner(signature: signature)
		let processor = DefaultPairSuccessProcessor(deviceSignatureSigner: signer)
		let stanza = BinaryNode(
			tag: "iq",
			attrs: ["id": "pair-9"],
			content: .nodes([
				BinaryNode(
					tag: "pair-success",
					content: .nodes([
						BinaryNode(
							tag: "device-identity",
							content: .data(try Data(hexString: pairSuccessHMACPayloadHex))
						),
						BinaryNode(tag: "device", attrs: ["jid": "123@s.whatsapp.net", "lid": "123@lid"])
					])
				)
			])
		)

		let result = try processor.processPairSuccess(
			stanza: stanza,
			credentials: sampleCredentials(
				advSecretKey: "BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc=",
				signedIdentityPrivateKey: Data(repeating: 0x11, count: 32),
				signedIdentityPublicKey: try Data(
					hexString: "65666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f8081828384"
				)
			)
		)

		#expect(signer.privateKey == Data(repeating: 0x11, count: 32))
		let expectedDeviceMessage = try Data(hexString:
			"06010801100218032000280065666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838407a37cbc142093c8b755dc1b10e86cb426374ad16aa853ed0bdfc0b2b86d1c7c"
		)
		#expect(signer.message == expectedDeviceMessage)
		#expect(result.reply.tag == "iq")
		#expect(result.reply.attrs["to"] == "@s.whatsapp.net")
		#expect(result.reply.attrs["type"] == "result")
		#expect(result.reply.attrs["id"] == "pair-9")
		let pairDeviceSign = try #require(result.reply.firstChild(named: "pair-device-sign"))
		let deviceIdentityNode = try #require(pairDeviceSign.firstChild(named: "device-identity"))
		#expect(deviceIdentityNode.attrs["key-index"] == "3")
		guard case let .data(encodedIdentity) = deviceIdentityNode.content else {
			Issue.record("expected encoded device identity data")
			return
		}

		let signedDeviceIdentity = try Proto_ADVSignedDeviceIdentity(serializedBytes: encodedIdentity)
		#expect(signedDeviceIdentity.hasDetails)
		#expect(!signedDeviceIdentity.hasAccountSignatureKey)
		#expect(signedDeviceIdentity.hasAccountSignature)
		#expect(signedDeviceIdentity.deviceSignature == signature)
	}

	@Test("applies pair success credential updates")
	func appliesPairSuccessCredentialUpdates() throws {
		let signer = CapturingDeviceSignatureSigner(signature: Data(repeating: 0xaa, count: 64))
		let processor = DefaultPairSuccessProcessor(deviceSignatureSigner: signer)
		let stanza = BinaryNode(
			tag: "iq",
			attrs: ["id": "pair-10"],
			content: .nodes([
				BinaryNode(
					tag: "pair-success",
					content: .nodes([
						BinaryNode(
							tag: "device-identity",
							content: .data(try Data(hexString: pairSuccessHMACPayloadHex))
						),
						BinaryNode(tag: "platform", attrs: ["name": "macOS"]),
						BinaryNode(tag: "biz", attrs: ["name": "Acme"]),
						BinaryNode(tag: "device", attrs: [
							"jid": "123@s.whatsapp.net",
							"lid": "456@lid"
						])
					])
				)
			])
		)
		let result = try processor.processPairSuccess(
			stanza: stanza,
			credentials: sampleCredentials(
				advSecretKey: "BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc=",
				signedIdentityPublicKey: try Data(
					hexString: "65666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f8081828384"
				)
			)
		)
		var credentials = sampleCredentials()

		try result.apply(to: &credentials)

		let expectedIdentityKey = try Data(hexString:
			"0507a37cbc142093c8b755dc1b10e86cb426374ad16aa853ed0bdfc0b2b86d1c7c"
		)
		let expectedAccountDetails = try Data(hexString: "08011002180320002800")
		let expectedAccountSignatureKey = try Data(hexString:
			"07a37cbc142093c8b755dc1b10e86cb426374ad16aa853ed0bdfc0b2b86d1c7c"
		)
		#expect(credentials.me == WhatsAppUser(id: "123@s.whatsapp.net", name: "Acme", lid: "456@lid"))
		#expect(credentials.platform == "macOS")
		#expect(credentials.signalIdentities == [
			SignalIdentity(
				identifier: SignalProtocolAddress(name: "456@lid", deviceID: 0),
				identifierKey: expectedIdentityKey
			)
		])
		#expect(credentials.account?.details == expectedAccountDetails)
		#expect(credentials.account?.accountSignatureKey == expectedAccountSignatureKey)
		#expect(credentials.account?.deviceSignature == Data(repeating: 0xaa, count: 64))
	}

	private let pairSuccessHMACPayloadHex =
		"0a700a0a08011002180320002800122007a37cbc142093c8b755dc1b10e86cb426374ad16aa853ed0bdfc0b2b86d1c7c1a40cdbf3d5f104aa0dc19dd3963ec1171ab209398095585c3fb926145a88455c5b09288b06b514c0cffc0a72db1ca6d5effc346f43a141e370598a15dbfdd55b68b12201358ec89d4ea5cbcb584619f8f0c0b0d0d4f2e803b51d3d0be28c30c926654cc"

	private func sampleCredentials(
		advSecretKey: String = "adv-secret",
		signedIdentityPrivateKey: Data = Data([5]),
		signedIdentityPublicKey: Data = Data([6])
	) -> AuthenticationCredentials {
		AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(
				privateKey: signedIdentityPrivateKey,
				publicKey: signedIdentityPublicKey
			),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([8])),
				signature: Data([9]),
				keyID: 1
			),
			registrationID: 1,
			advSecretKey: advSecretKey,
			nextPreKeyID: 1,
			firstUnuploadedPreKeyID: 1,
			accountSyncCounter: 0,
			registered: false
		)
	}
}

private final class CapturingDeviceSignatureSigner: DeviceSignatureSigning, @unchecked Sendable {
	private let signature: Data
	private(set) var privateKey: Data?
	private(set) var message: Data?

	init(signature: Data) {
		self.signature = signature
	}

	func sign(privateKey: Data, message: Data) throws -> Data {
		self.privateKey = privateKey
		self.message = message
		return signature
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw PairSuccessProcessorTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum PairSuccessProcessorTestError: Error {
	case invalidHex
}
