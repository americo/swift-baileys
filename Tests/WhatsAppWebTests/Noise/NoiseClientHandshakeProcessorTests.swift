import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Noise client handshake processor")
struct NoiseClientHandshakeProcessorTests {
	@Test("processes a Baileys server hello and prepares the client static ciphertext")
	func processesServerHello() throws {
		var processor = NoiseClientHandshakeProcessor(
			header: try Data(hexString: "57410603"),
			ephemeralKeyPair: NoiseKeyPair(
				privateKey: try Data(hexString: "082d3ce344577139a6cd72301b318e446c1e1d5d537ac98b82b2a84f1396c07e"),
				publicKey: try Data(hexString: "74474a355abf2fe7d8972708aed36c13eb855d27f193bf81298b7db5a41ce338")
			),
			staticKeyPair: NoiseKeyPair(
				privateKey: try Data(hexString: "98e9530dfdd718d517115a6971a17c9d727d71559d4c0cc60bca6ee3fbedde49"),
				publicKey: try Data(hexString: "a4eb3ec2f79d7fbab1817f5658b812a366beb4f81bf0323fed52b38a317beb5f")
			),
			certificateVerifier: RecordingCertificateVerifier(results: [true, true])
		)
		let handshake = try Proto_HandshakeMessage(
			serializedBytes: Data(hexString: "1abb020a206eb09d3bd437ebf94ff690153744a96d25931098cfb0576a1d25aae4a447ac771230a26a65aec674a002c74b55f7efb4e0ad179587eeb2df9ae6a747ec6e0f8da64db10abd84446318ecb4483b154b6654b61ae401b13606d14c6adf83b07d7b6bff5039ad76778d7662adafcc23e4501bc4c6505d8020ea2c9efa7b289b1917dd6be96ae89659f377c7619d7ba8558691b846158010ef69611cbf92032f653947e7b09f00e130e728bf7efef3efc7b5e4a38d8e622a652d59cfeb1166092d6f1940ed2c03cf64b0ca18399bd1da43b30eabd06d2cba0ce75dffeb22bce05ac300b5f2d1d080065e0d8f9e45d022b7ed64ad094e3a52af4f3b0fc58ee1db8525d12789c5f18c2308e763dcb4ed7dc10d8a4c9c7299e6bf4bcfd861cb1e47ae25fcb0bd43e52fd453c2980c6098e8b73aa46286e954a81b61d2")
		)

		let result = try processor.processServerHello(handshake)
		let certificateData = try result.certificateChain.serializedData()

		#expect(result.serverStaticPublicKey.hexString == "2edfaeca697488b12778ce74b8997fddd17964b45bb56c1ea88d7e7ad8d2bb0d")
		#expect(certificateData.hexString == "0a680a2410001a20112233445566778899001122334455667788990011223344556677889900112212404141414141414141414141414141414141414141414141414141414141414141414141414141414141414141414141414141414141414141414141414141414112680a2410001a201122334455667788990011223344556677889900112233445566778899001122124042424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242")
		#expect(result.clientStaticCiphertext.hexString == "93f47479f9f99a2fa1ab9735f542ea5c7c2a082d149c552e1ad388e79ad078718eae53c95f8693f6c3e6666f0012425a")
		#expect(processor.handshakeState.hash.hexString == "0e511baccba9be1e15b0cc691b8e9bbbd50b786e04b8bc64ed4bd5e549036cf0")
		#expect(processor.handshakeState.salt.hexString == "c30529645027ad0c88c888bd3d9ae9d92c9b2450ddbe7e78f50a6be2dbeffb2b")
		#expect(processor.handshakeState.encryptionKey.hexString == "ae618f3f284e1bc1fec1c7b4df5eb376fa2ee5938a4dfe88ed45d56000ffea0b")
	}

	@Test("transitions from client finish into Baileys transport encryption")
	func transitionsIntoTransportEncryption() throws {
		var processor = try makeProcessor(certificateVerifier: RecordingCertificateVerifier(results: [true, true]))
		_ = try processor.processServerHello(try fixtureHandshake())

		var transport = try processor.makeTransportState()
		let ciphertext = try transport.encrypt(Data("post-handshake-frame".utf8))

		#expect(ciphertext.hexString == "d9c9de42572a5025f3808ea2aa53c6126cedb93b44602dd471e810e0fa78f7ff55af5c86")
	}

	@Test("rejects a server hello when the leaf certificate signature is invalid")
	func rejectsInvalidLeafSignature() throws {
		var processor = try makeProcessor(certificateVerifier: RecordingCertificateVerifier(results: [false, true]))

		#expect(throws: NoiseClientHandshakeProcessorError.invalidLeafCertificateSignature) {
			try processor.processServerHello(try fixtureHandshake())
		}
	}

	@Test("rejects a server hello when the intermediate certificate signature is invalid")
	func rejectsInvalidIntermediateSignature() throws {
		var processor = try makeProcessor(certificateVerifier: RecordingCertificateVerifier(results: [true, false]))

		#expect(throws: NoiseClientHandshakeProcessorError.invalidIntermediateCertificateSignature) {
			try processor.processServerHello(try fixtureHandshake())
		}
	}

	private func makeProcessor(certificateVerifier: RecordingCertificateVerifier) throws -> NoiseClientHandshakeProcessor {
		NoiseClientHandshakeProcessor(
			header: try Data(hexString: "57410603"),
			ephemeralKeyPair: NoiseKeyPair(
				privateKey: try Data(hexString: "082d3ce344577139a6cd72301b318e446c1e1d5d537ac98b82b2a84f1396c07e"),
				publicKey: try Data(hexString: "74474a355abf2fe7d8972708aed36c13eb855d27f193bf81298b7db5a41ce338")
			),
			staticKeyPair: NoiseKeyPair(
				privateKey: try Data(hexString: "98e9530dfdd718d517115a6971a17c9d727d71559d4c0cc60bca6ee3fbedde49"),
				publicKey: try Data(hexString: "a4eb3ec2f79d7fbab1817f5658b812a366beb4f81bf0323fed52b38a317beb5f")
			),
			certificateVerifier: certificateVerifier
		)
	}

	private func fixtureHandshake() throws -> Proto_HandshakeMessage {
		try Proto_HandshakeMessage(
			serializedBytes: Data(hexString: "1abb020a206eb09d3bd437ebf94ff690153744a96d25931098cfb0576a1d25aae4a447ac771230a26a65aec674a002c74b55f7efb4e0ad179587eeb2df9ae6a747ec6e0f8da64db10abd84446318ecb4483b154b6654b61ae401b13606d14c6adf83b07d7b6bff5039ad76778d7662adafcc23e4501bc4c6505d8020ea2c9efa7b289b1917dd6be96ae89659f377c7619d7ba8558691b846158010ef69611cbf92032f653947e7b09f00e130e728bf7efef3efc7b5e4a38d8e622a652d59cfeb1166092d6f1940ed2c03cf64b0ca18399bd1da43b30eabd06d2cba0ce75dffeb22bce05ac300b5f2d1d080065e0d8f9e45d022b7ed64ad094e3a52af4f3b0fc58ee1db8525d12789c5f18c2308e763dcb4ed7dc10d8a4c9c7299e6bf4bcfd861cb1e47ae25fcb0bd43e52fd453c2980c6098e8b73aa46286e954a81b61d2")
		)
	}
}

private final class RecordingCertificateVerifier: NoiseCertificateVerifying, @unchecked Sendable {
	let results: [Bool]
	private var index = 0

	init(results: [Bool]) {
		self.results = results
	}

	func verify(publicKey: Data, message: Data, signature: Data) -> Bool {
		defer {
			index += 1
		}

		return results[index]
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw NoiseClientHandshakeProcessorTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}

	var hexString: String {
		map { String(format: "%02x", $0) }.joined()
	}
}

private enum NoiseClientHandshakeProcessorTestError: Error {
	case invalidHex
}
