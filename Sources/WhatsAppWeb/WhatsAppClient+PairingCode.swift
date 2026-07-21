import Foundation

extension WhatsAppClient {
	public func requestPairingCode(
		forPhoneNumber phoneNumber: String,
		customPairingCode: String? = nil,
		requestID: String? = nil
	) async throws -> String {
		try await requestPairingCode(
			forPhoneNumber: phoneNumber,
			customPairingCode: customPairingCode,
			requestID: requestID,
			salt: MessageIDGenerator.secureRandomBytes(count: 32),
			iv: MessageIDGenerator.secureRandomBytes(count: 16)
		)
	}

	func requestPairingCode(
		forPhoneNumber phoneNumber: String,
		customPairingCode: String?,
		requestID: String?,
		salt: Data,
		iv: Data
	) async throws -> String {
		if let customPairingCode, customPairingCode.count != 8 {
			throw PairingCodeError.invalidCustomCodeLength
		}

		let pairingCode = try customPairingCode ?? generatedPairingCode()
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		guard authenticationState != nil else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		let jid = JID.encode(user: phoneNumber, server: JIDServer.user.rawValue)
		try await updateCredentials { credentials in
			credentials.pairingCode = pairingCode
			credentials.me = WhatsAppUser(id: jid, name: "~")
		}
		guard let credentials = authenticationState?.credentials else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		let wrappedPairingKey = try PairingCode.wrapCompanionEphemeralPublicKey(
			credentials.pairingEphemeralKeyPair.publicKey,
			pairingCode: pairingCode,
			salt: salt,
			iv: iv
		)

		try await sendNode(BinaryNode(
			tag: "iq",
			attrs: ["to": "@s.whatsapp.net", "type": "set", "id": id, "xmlns": "md"],
			content: .nodes([
				BinaryNode(
					tag: "link_code_companion_reg",
					attrs: [
						"jid": jid,
						"stage": "companion_hello",
						"should_show_push_notification": "true"
					],
					content: .nodes([
						BinaryNode(tag: "link_code_pairing_wrapped_companion_ephemeral_pub", content: .data(wrappedPairingKey)),
						BinaryNode(tag: "companion_server_auth_key_pub", content: .data(credentials.noiseKey.publicKey)),
						BinaryNode(tag: "companion_platform_id", content: .data(Data(configuration.companionPlatformID.utf8))),
						BinaryNode(tag: "companion_platform_display", content: .data(Data("SwiftBaileys (macOS)".utf8))),
						BinaryNode(tag: "link_code_pairing_nonce", content: .data(Data("0".utf8)))
					])
				)
			])
		))

		return pairingCode
	}

	private func generatedPairingCode() throws -> String {
		let bytes = try MessageIDGenerator.secureRandomBytes(count: 5)
		guard bytes.count == 5 else {
			throw PairingCodeError.invalidRandomByteCount
		}

		return PairingCode.crockfordString(from: bytes)
	}
}
