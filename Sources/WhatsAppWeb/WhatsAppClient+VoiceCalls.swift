import Foundation

public enum WhatsAppVoiceCallError: Error, Equatable, Sendable {
	case noDevices
	case unknownCall(String)
	case missingOfferKey
	case undecryptableOffer
	case missingCallKey
}

/// An outgoing voice call whose `<offer>` was accepted by the server.
public struct WhatsAppOutgoingVoiceCall: Equatable, Sendable {
	public let callID: String
	public let peer: String
	public let callCreator: String
	public let callKey: Data
	/// The server's `<ack class="call" type="offer">`; it carries the relay allocation.
	public let offerAck: BinaryNode

	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.callID == rhs.callID && lhs.peer == rhs.peer && lhs.callCreator == rhs.callCreator
			&& lhs.callKey == rhs.callKey && lhs.offerAck == rhs.offerAck
	}
}

/// An incoming voice call whose call key was decrypted from the offer.
public struct WhatsAppIncomingVoiceCall: Equatable, Sendable {
	public let callID: String
	public let callCreator: String
	public let chatID: String
	public let callKey: Data
	public let offer: BinaryNode

	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.callID == rhs.callID && lhs.callCreator == rhs.callCreator && lhs.chatID == rhs.chatID
			&& lhs.callKey == rhs.callKey && lhs.offer == rhs.offer
	}
}

extension WhatsAppClient {
	// MARK: Outgoing

	/// Places a 1:1 voice call: generates the call key, encrypts it for every device of `peer` and
	/// sends the `<offer>`, waiting for the server's ack.
	///
	/// This only performs the signaling half of a call. Media (relay, SRTP, audio) is separate.
	public func startVoiceCall(to peer: String) async throws -> WhatsAppOutgoingVoiceCall {
		guard let me = authenticationState?.credentials.me else {
			throw WhatsAppClientError.missingAuthenticatedUser
		}
		guard let messageEncryptor else {
			throw WhatsAppClientError.missingMessageEncryptor
		}

		let callCreator = me.lid ?? me.id
		let devices = try await getUSyncDevices([peer], useCache: false, ignoreZeroDevices: false).map(\.jid)
		guard !devices.isEmpty else {
			throw WhatsAppVoiceCallError.noDevices
		}

		_ = try await assertSessions(for: devices, force: false)

		let callKey = try CallKeyMessage.generateCallKey()
		let plaintext = try CallKeyMessage.encode(callKey: callKey, encoder: messageEncoder)
		var deviceKeys = [CallOfferDeviceKey]()
		for device in devices {
			let encrypted = try await messageEncryptor.encryptMessage(jid: device, data: plaintext)
			deviceKeys.append(CallOfferDeviceKey(
				deviceJID: device,
				ciphertext: encrypted.ciphertext,
				encryptionType: encrypted.type
			))
		}

		let deviceIdentity = try deviceIdentityIfNeeded(for: deviceKeys)
		let callID = try Self.generateCallID()
		let stanzaID = try messageIDGenerator.generate()
		let offer = CallStanzaBuilder.offer(
			callID: callID,
			to: peer,
			callCreator: callCreator,
			stanzaID: stanzaID,
			deviceKeys: deviceKeys,
			deviceIdentity: deviceIdentity,
			multiDevice: devices.count > 1
		)

		let ack = try await query(offer, timeout: .seconds(20))
		return WhatsAppOutgoingVoiceCall(
			callID: callID,
			peer: peer,
			callCreator: callCreator,
			callKey: callKey,
			offerAck: ack
		)
	}

	// MARK: Incoming

	/// Decrypts the call key of a pending incoming offer. The offer must have been delivered through
	/// the `.call` event with status `.offer`.
	public func prepareIncomingVoiceCall(id callID: String) async throws -> WhatsAppIncomingVoiceCall {
		guard let offerStanza = callOfferNodes[callID],
			  let offer = offerStanza.firstChild(named: "offer") ?? offerStanza.firstChild(named: "offer_notice") else {
			throw WhatsAppVoiceCallError.unknownCall(callID)
		}
		guard let messageDecryptor else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		let creator = offer.attrs["call-creator"] ?? offer.attrs["from"] ?? offerStanza.attrs["from"] ?? ""
		let chatID = offerStanza.attrs["from"] ?? creator
		guard let enc = Self.offerEncNode(in: offer, localJIDs: localJIDs) else {
			throw WhatsAppVoiceCallError.missingOfferKey
		}

		let carrier = BinaryNode(tag: "message", attrs: ["from": creator], content: .nodes([enc]))
		guard let message = try await messageDecryptor.decryptIncomingMessage(from: carrier) else {
			throw WhatsAppVoiceCallError.undecryptableOffer
		}
		guard let callKey = CallKeyMessage.callKey(from: message) else {
			throw WhatsAppVoiceCallError.missingCallKey
		}

		return WhatsAppIncomingVoiceCall(
			callID: callID,
			callCreator: creator,
			chatID: chatID,
			callKey: callKey,
			offer: offer
		)
	}

	/// Sends `<preaccept>` so the caller hears ringing while the user decides.
	public func preacceptVoiceCall(_ call: WhatsAppIncomingVoiceCall) async throws {
		try await sendNode(CallStanzaBuilder.preaccept(
			callID: call.callID,
			to: call.callCreator,
			callCreator: call.callCreator,
			stanzaID: messageIDGenerator.generate()
		))
	}

	/// Sends `<accept>` for an incoming call. `relayTransportEndpoint` and `routingToken` come from
	/// the relay selected for the call; pass `nil` until the media layer provides them.
	public func acceptVoiceCall(
		_ call: WhatsAppIncomingVoiceCall,
		relayTransportEndpoint: Data? = nil,
		routingToken: Data? = nil
	) async throws {
		try await sendNode(CallStanzaBuilder.accept(
			callID: call.callID,
			to: call.callCreator,
			callCreator: call.callCreator,
			stanzaID: messageIDGenerator.generate(),
			relayTransportEndpoint: relayTransportEndpoint,
			routingToken: routingToken
		))
	}

	/// Rejects an incoming call with an optional reason such as `busy`.
	public func rejectVoiceCall(_ call: WhatsAppIncomingVoiceCall, reason: String? = nil) async throws {
		try await sendNode(CallStanzaBuilder.reject(
			callID: call.callID,
			to: call.callCreator,
			callCreator: call.callCreator,
			stanzaID: messageIDGenerator.generate(),
			reason: reason
		))
		callOfferNodes.removeValue(forKey: call.callID)
	}

	/// Ends a call in progress, or cancels an outgoing call that has not been answered.
	public func endVoiceCall(id callID: String, peer: String, callCreator: String, reason: String? = nil) async throws {
		try await sendNode(CallStanzaBuilder.terminate(
			callID: callID,
			to: peer,
			callCreator: callCreator,
			stanzaID: messageIDGenerator.generate(),
			reason: reason
		))
		callOfferNodes.removeValue(forKey: callID)
	}

	// MARK: Helpers

	private var localJIDs: Set<String> {
		guard let me = authenticationState?.credentials.me else {
			return []
		}

		return Set([me.id, me.lid].compactMap { $0 }.map { Self.userPart(of: $0) })
	}

	/// Finds the `<enc>` addressed to this account: either a direct child, or the one under the
	/// `<destination><to jid=…>` entry that matches one of our identities.
	static func offerEncNode(in offer: BinaryNode, localJIDs: Set<String>) -> BinaryNode? {
		if let direct = offer.firstChild(named: "enc") {
			return direct
		}

		let destinations = offer.firstChild(named: "destination")?.children(named: "to") ?? []
		let own = destinations.first { to in
			to.attrs["jid"].map { localJIDs.contains(userPart(of: $0)) } ?? false
		}
		return (own ?? destinations.first)?.firstChild(named: "enc")
	}

	static func userPart(of jid: String) -> String {
		let beforeAt = jid.split(separator: "@", maxSplits: 1).first.map(String.init) ?? jid
		return beforeAt.split(separator: ":", maxSplits: 1).first.map(String.init) ?? beforeAt
	}

	private func deviceIdentityIfNeeded(for keys: [CallOfferDeviceKey]) throws -> Data? {
		guard keys.contains(where: { $0.encryptionType == "pkmsg" }),
			  let account = authenticationState?.credentials.account else {
			return nil
		}

		return try Self.encodedSignedDeviceIdentity(account)
	}

	static func generateCallID() throws -> String {
		var bytes = [UInt8](repeating: 0, count: 16)
		let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		guard status == errSecSuccess else {
			throw CallKeyMessageError.randomGenerationFailed(status)
		}

		return bytes.map { String(format: "%02X", $0) }.joined()
	}
}
