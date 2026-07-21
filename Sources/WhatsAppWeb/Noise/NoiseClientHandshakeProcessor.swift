import Foundation

enum NoiseClientHandshakeProcessorError: Error {
	case missingServerHello
	case missingServerEphemeral
	case missingServerStatic
	case missingServerPayload
	case invalidCertificateChain
	case invalidLeafCertificateSignature
	case invalidIntermediateCertificateSignature
	case certificateIssuerMismatch
}

protocol NoiseCertificateVerifying: Sendable {
	func verify(publicKey: Data, message: Data, signature: Data) -> Bool
}

struct NoiseClientHandshakeResult: Sendable {
	let serverStaticPublicKey: Data
	let certificateChain: Proto_CertChain
	let clientStaticCiphertext: Data
}

struct NoiseClientHandshakeProcessor: Sendable {
	private static let trustedCertificatePublicKey = Data([
		0x14, 0x23, 0x75, 0x57, 0x4d, 0x0a, 0x58, 0x71,
		0x66, 0xaa, 0xe7, 0x1e, 0xbe, 0x51, 0x64, 0x37,
		0xc4, 0xa2, 0x8b, 0x73, 0xe3, 0x69, 0x5c, 0x6c,
		0xe1, 0xf7, 0xf9, 0x54, 0x5d, 0xa8, 0xee, 0x6b
	])
	private static let trustedIssuerSerial: UInt32 = 0

	private let ephemeralKeyPair: NoiseKeyPair
	private let staticKeyPair: NoiseKeyPair
	private let certificateVerifier: any NoiseCertificateVerifying
	private(set) var handshakeState: NoiseHandshakeState

	init(
		header: Data,
		ephemeralKeyPair: NoiseKeyPair,
		staticKeyPair: NoiseKeyPair,
		certificateVerifier: any NoiseCertificateVerifying = NoiseXEdDSAVerifier()
	) {
		self.ephemeralKeyPair = ephemeralKeyPair
		self.staticKeyPair = staticKeyPair
		self.certificateVerifier = certificateVerifier
		self.handshakeState = NoiseHandshakeState()
		handshakeState.authenticate(header)
		handshakeState.authenticate(ephemeralKeyPair.publicKey)
	}

	mutating func processServerHello(_ message: Proto_HandshakeMessage) throws -> NoiseClientHandshakeResult {
		guard message.hasServerHello else {
			throw NoiseClientHandshakeProcessorError.missingServerHello
		}

		let serverHello = message.serverHello
		guard serverHello.hasEphemeral else {
			throw NoiseClientHandshakeProcessorError.missingServerEphemeral
		}
		guard serverHello.hasStatic else {
			throw NoiseClientHandshakeProcessorError.missingServerStatic
		}
		guard serverHello.hasPayload else {
			throw NoiseClientHandshakeProcessorError.missingServerPayload
		}

		handshakeState.authenticate(serverHello.ephemeral)
		try handshakeState.mixIntoKey(
			NoiseCurve25519.sharedSecret(
				privateKey: ephemeralKeyPair.privateKey,
				publicKey: serverHello.ephemeral
			)
		)

		let serverStaticPublicKey = try handshakeState.decrypt(serverHello.static)
		try handshakeState.mixIntoKey(
			NoiseCurve25519.sharedSecret(
				privateKey: ephemeralKeyPair.privateKey,
				publicKey: serverStaticPublicKey
			)
		)

		let certificateData = try handshakeState.decrypt(serverHello.payload)
		let certificateChain = try Proto_CertChain(serializedBytes: certificateData)
		guard certificateChain.hasLeaf,
		      certificateChain.leaf.hasDetails,
		      certificateChain.leaf.hasSignature,
		      certificateChain.hasIntermediate,
		      certificateChain.intermediate.hasDetails,
		      certificateChain.intermediate.hasSignature else {
			throw NoiseClientHandshakeProcessorError.invalidCertificateChain
		}
		let intermediateDetails = try Proto_CertChain.NoiseCertificate.Details(
			serializedBytes: certificateChain.intermediate.details
		)
		guard intermediateDetails.issuerSerial == Self.trustedIssuerSerial else {
			throw NoiseClientHandshakeProcessorError.certificateIssuerMismatch
		}
		guard certificateVerifier.verify(
			publicKey: intermediateDetails.key,
			message: certificateChain.leaf.details,
			signature: certificateChain.leaf.signature
		) else {
			throw NoiseClientHandshakeProcessorError.invalidLeafCertificateSignature
		}
		guard certificateVerifier.verify(
			publicKey: Self.trustedCertificatePublicKey,
			message: certificateChain.intermediate.details,
			signature: certificateChain.intermediate.signature
		) else {
			throw NoiseClientHandshakeProcessorError.invalidIntermediateCertificateSignature
		}

		let clientStaticCiphertext = try handshakeState.encrypt(staticKeyPair.publicKey)
		try handshakeState.mixIntoKey(
			NoiseCurve25519.sharedSecret(
				privateKey: staticKeyPair.privateKey,
				publicKey: serverHello.ephemeral
			)
		)

		return NoiseClientHandshakeResult(
			serverStaticPublicKey: serverStaticPublicKey,
			certificateChain: certificateChain,
			clientStaticCiphertext: clientStaticCiphertext
		)
	}

	func makeTransportState() throws -> NoiseTransportState {
		try handshakeState.makeTransportState()
	}
}
