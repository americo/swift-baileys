import Foundation
import CryptoKit

public struct PairSuccessProcessingResult: Sendable {
	public var reply: BinaryNode
	private let credentialsUpdate: @Sendable (inout AuthenticationCredentials) throws -> Void

	public init(
		reply: BinaryNode,
		credentialsUpdate: @escaping @Sendable (inout AuthenticationCredentials) throws -> Void
	) {
		self.reply = reply
		self.credentialsUpdate = credentialsUpdate
	}

	func apply(to credentials: inout AuthenticationCredentials) throws {
		try credentialsUpdate(&credentials)
	}
}

public protocol PairSuccessProcessing: Sendable {
	func processPairSuccess(
		stanza: BinaryNode,
		credentials: AuthenticationCredentials
	) throws -> PairSuccessProcessingResult
}

public protocol DeviceSignatureSigning: Sendable {
	func sign(privateKey: Data, message: Data) throws -> Data
}

public struct UnsupportedDeviceSignatureSigner: DeviceSignatureSigning {
	public init() {}

	public func sign(privateKey: Data, message: Data) throws -> Data {
		throw PairSuccessProcessingError.cryptographicValidationNotImplemented
	}
}

public struct DefaultPairSuccessProcessor: PairSuccessProcessing {
	private static let accountSignaturePrefix = Data([6, 0])
	private static let deviceSignaturePrefix = Data([6, 1])
	private static let hostedAccountSignaturePrefix = Data([6, 5])
	private let deviceSignatureSigner: any DeviceSignatureSigning

	public init(deviceSignatureSigner: any DeviceSignatureSigning = LibSignalDeviceSignatureSigner()) {
		self.deviceSignatureSigner = deviceSignatureSigner
	}

	public func processPairSuccess(
		stanza: BinaryNode,
		credentials: AuthenticationCredentials
	) throws -> PairSuccessProcessingResult {
		guard let pairSuccess = stanza.firstChild(named: "pair-success"),
			  let deviceIdentityNode = pairSuccess.firstChild(named: "device-identity"),
			  let deviceNode = pairSuccess.firstChild(named: "device") else {
			throw PairSuccessProcessingError.missingDeviceIdentityOrDevice
		}

		guard case let .data(deviceIdentityData) = deviceIdentityNode.content else {
			throw PairSuccessProcessingError.invalidDeviceIdentityHMAC
		}

		let signedDeviceIdentityHMAC: Proto_ADVSignedDeviceIdentityHMAC
		do {
			signedDeviceIdentityHMAC = try Proto_ADVSignedDeviceIdentityHMAC(serializedBytes: deviceIdentityData)
		} catch {
			throw PairSuccessProcessingError.invalidDeviceIdentityHMAC
		}

		guard signedDeviceIdentityHMAC.hasDetails, signedDeviceIdentityHMAC.hasHmac else {
			throw PairSuccessProcessingError.missingDeviceIdentityHMACFields
		}

		guard let advSecretKey = Data(base64Encoded: credentials.advSecretKey) else {
			throw PairSuccessProcessingError.invalidAdvSecretKey
		}

		let message =
			signedDeviceIdentityHMAC.hasAccountType && signedDeviceIdentityHMAC.accountType == .hosted
			? Self.hostedAccountSignaturePrefix + signedDeviceIdentityHMAC.details
			: signedDeviceIdentityHMAC.details
		let authenticationCode = HMAC<SHA256>.authenticationCode(
			for: message,
			using: SymmetricKey(data: advSecretKey)
		)
		guard Data(authenticationCode) == signedDeviceIdentityHMAC.hmac else {
			throw PairSuccessProcessingError.invalidAccountSignature
		}

		let signedDeviceIdentity: Proto_ADVSignedDeviceIdentity
		do {
			signedDeviceIdentity = try Proto_ADVSignedDeviceIdentity(serializedBytes: signedDeviceIdentityHMAC.details)
		} catch {
			throw PairSuccessProcessingError.invalidSignedDeviceIdentity
		}

		guard signedDeviceIdentity.hasDetails,
			  signedDeviceIdentity.hasAccountSignatureKey,
			  signedDeviceIdentity.hasAccountSignature else {
			throw PairSuccessProcessingError.missingSignedDeviceIdentityFields
		}

		let accountDeviceIdentity: Proto_ADVDeviceIdentity
		do {
			accountDeviceIdentity = try Proto_ADVDeviceIdentity(serializedBytes: signedDeviceIdentity.details)
		} catch {
			throw PairSuccessProcessingError.invalidDeviceIdentity
		}

		let accountSignaturePrefix =
			accountDeviceIdentity.hasDeviceType && accountDeviceIdentity.deviceType == .hosted
			? Self.hostedAccountSignaturePrefix
			: Self.accountSignaturePrefix
		let accountMessage = accountSignaturePrefix
			+ signedDeviceIdentity.details
			+ credentials.signedIdentityKey.publicKey
		guard NoiseXEdDSAVerifier().verify(
			publicKey: signedDeviceIdentity.accountSignatureKey,
			message: accountMessage,
			signature: signedDeviceIdentity.accountSignature
		) else {
			throw PairSuccessProcessingError.failedAccountSignatureVerification
		}

		let deviceMessage = Self.deviceSignaturePrefix
			+ signedDeviceIdentity.details
			+ credentials.signedIdentityKey.publicKey
			+ signedDeviceIdentity.accountSignatureKey
		let deviceSignature = try deviceSignatureSigner.sign(
			privateKey: credentials.signedIdentityKey.privateKey,
			message: deviceMessage
		)
		var replyIdentity = signedDeviceIdentity
		replyIdentity.deviceSignature = deviceSignature
		replyIdentity.clearAccountSignatureKey()
		let encodedReplyIdentity = try replyIdentity.serializedData()
		let jid = deviceNode.attrs["jid"]
		let lid = deviceNode.attrs["lid"]
		let bizName = pairSuccess.firstChild(named: "biz")?.attrs["name"]
		let platform = pairSuccess.firstChild(named: "platform")?.attrs["name"]
		let account = SignedDeviceIdentityAccount(
			details: signedDeviceIdentity.details,
			accountSignatureKey: signedDeviceIdentity.accountSignatureKey,
			accountSignature: signedDeviceIdentity.accountSignature,
			deviceSignature: deviceSignature
		)
		let signalIdentity = lid.map {
			SignalIdentity(
				identifier: SignalProtocolAddress(name: $0, deviceID: 0),
				identifierKey: (try? SignalPublicKey.format(signedDeviceIdentity.accountSignatureKey)) ?? signedDeviceIdentity.accountSignatureKey
			)
		}

		return PairSuccessProcessingResult(
			reply: BinaryNode(
				tag: "iq",
				attrs: [
					"to": "@s.whatsapp.net",
					"type": "result",
					"id": stanza.attrs["id"] ?? ""
				],
				content: .nodes([
					BinaryNode(
						tag: "pair-device-sign",
						content: .nodes([
							BinaryNode(
								tag: "device-identity",
								attrs: ["key-index": String(accountDeviceIdentity.keyIndex)],
								content: .data(encodedReplyIdentity)
							)
						])
					)
				])
			),
			credentialsUpdate: { credentials in
				if let jid {
					credentials.me = WhatsAppUser(id: jid, name: bizName, lid: lid)
				}

				credentials.account = account
				if let signalIdentity {
					credentials.signalIdentities.append(signalIdentity)
				}

				credentials.platform = platform
			}
		)
	}
}

public enum PairSuccessProcessingError: Error, Equatable, Sendable {
	case missingDeviceIdentityOrDevice
	case invalidDeviceIdentityHMAC
	case missingDeviceIdentityHMACFields
	case invalidAdvSecretKey
	case invalidAccountSignature
	case invalidSignedDeviceIdentity
	case missingSignedDeviceIdentityFields
	case invalidDeviceIdentity
	case failedAccountSignatureVerification
	case cryptographicValidationNotImplemented
}
