import Foundation

extension WhatsAppClient {
	func handleReceiptNode(_ node: BinaryNode) async -> Bool {
		guard node.tag == "receipt", let firstID = node.attrs["id"], let from = node.attrs["from"] else {
			return false
		}

		let ids = [firstID] + node.children(named: "list").flatMap { list in
			list.children(named: "item").compactMap { $0.attrs["id"] }
		}
		let participant = node.attrs["participant"]
		let isNodeFromMe = JID.areSameUser(participant ?? from, receiptLocalUser(for: from))
		let remoteJID = (!isNodeFromMe || from.isGroupJID) ? from : node.attrs["recipient"]
		let fromMe = node.attrs["recipient"] == nil ||
			((node.attrs["type"] == "retry" || node.attrs["type"] == "sender") && isNodeFromMe)
		let timestamp = node.attrs["t"].flatMap(UInt64.init)
		if let remoteJID,
		   remoteJID != "@s.whatsapp.net",
		   configuration.shouldIgnoreJID(remoteJID) == true {
			if let ack = StanzaAck.build(for: node, meID: authenticationState?.credentials.me?.id) {
				try? await sendNode(ack)
			}
			return true
		}

		if node.attrs["type"] == "retry" {
			let requesterJID = participant ?? from
			let requesterRegistrationID = node.unsignedIntegerChild(named: "registration", length: 4)
			let request = MessageRetryRequest(
				key: WhatsAppMessageKey(remoteJID: remoteJID, fromMe: fromMe, id: firstID, participant: participant),
				messageIDs: ids,
				requesterJID: requesterJID,
				retryCount: retryCount(from: node),
				timestamp: timestamp,
				requesterRegistrationID: requesterRegistrationID,
				sessionBundle: retrySessionBundle(from: node, registrationID: requesterRegistrationID)
			)
			eventContinuation.yield(.messageRetryRequested(request))
			if let ack = StanzaAck.build(for: node, meID: authenticationState?.credentials.me?.id) {
				try? await sendNode(ack)
			}

			do {
				_ = try await resendCachedMessages(for: request)
			} catch {
				eventContinuation.yield(.messageRetryResendFailed(MessageRetryResendFailure(
					request: request,
					reason: retryResendFailureReason(from: error)
				)))
			}
			return true
		}

		guard let status = IncomingReceiptStatusMapper.status(fromReceiptType: node.attrs["type"]) else {
			return true
		}

		if (from.isGroupJID || from.isStatusBroadcastJID), let participant {
			let receipt = ReceivedMessageUserReceipt(
				userJID: JID(participant)?.normalizedUser ?? participant,
				receiptTimestamp: status == .deliveryAck ? timestamp : nil,
				readTimestamp: status == .deliveryAck ? nil : timestamp
			)
			eventContinuation.yield(.messageReceiptsUpdated(ids.map {
				ReceivedMessageReceiptUpdate(
					key: WhatsAppMessageKey(remoteJID: remoteJID, fromMe: fromMe, id: $0, participant: participant),
					receipt: receipt
				)
			}))
		} else {
			eventContinuation.yield(.messagesUpdated(ids.map {
				ReceivedMessageUpdate(
					key: WhatsAppMessageKey(remoteJID: remoteJID, fromMe: fromMe, id: $0, participant: participant),
					status: status,
					timestamp: timestamp
				)
			}))
		}

		if let ack = StanzaAck.build(for: node, meID: authenticationState?.credentials.me?.id) {
			try? await sendNode(ack)
		}

		return true
	}

	private func receiptLocalUser(for jid: String) -> String? {
		jid.contains("@\(JIDServer.lid.rawValue)")
			? authenticationState?.credentials.me?.lid
			: authenticationState?.credentials.me?.id
	}

	private func retryCount(from node: BinaryNode) -> Int {
		node.firstChild(named: "retry")?.attrs["count"].flatMap(Int.init) ?? 1
	}

	private func retrySessionBundle(from node: BinaryNode, registrationID: Int?) -> MessageRetrySessionBundle? {
		guard let registrationID,
			  let keys = node.firstChild(named: "keys"),
			  keys.childData(named: "type") == Data([0x05]),
			  let identity = keys.childData(named: "identity"),
			  identity.count == 32,
			  let signedPreKeyNode = keys.firstChild(named: "skey"),
			  let signedPreKey = retryPreKey(from: signedPreKeyNode, requiresSignature: true) else {
			return nil
		}

		return MessageRetrySessionBundle(
			registrationID: registrationID,
			identityKey: signalPublicKey(identity),
			signedPreKey: signedPreKey,
			preKey: keys.firstChild(named: "key").flatMap {
				retryPreKey(from: $0, requiresSignature: false)
			}
		)
	}

	private func retryPreKey(from node: BinaryNode, requiresSignature: Bool) -> SignalPreKey? {
		guard let keyID = node.unsignedIntegerChild(named: "id", length: 3),
			  let value = node.childData(named: "value"),
			  value.count == 32 else {
			return nil
		}

		let signature = node.childData(named: "signature")
		if requiresSignature && signature == nil {
			return nil
		}
		if requiresSignature && signature?.count != 64 {
			return nil
		}

		return SignalPreKey(keyID: keyID, publicKey: signalPublicKey(value), signature: signature)
	}

	private func signalPublicKey(_ value: Data) -> Data {
		value.count == 33 ? value : Data([0x05]) + value
	}

	private func retryResendFailureReason(from error: any Error) -> MessageRetryResendFailureReason {
		switch error as? WhatsAppClientError {
		case .missingMessageEncryptor:
			return .missingDependency(.messageEncryptor)
		case .missingMessageDeviceResolver:
			return .missingDependency(.messageDeviceResolver)
		case .missingSignalSessionPreparer:
			return .missingDependency(.signalSessionPreparer)
		case .missingMessageDestination:
			return .missingMessageDestination
		case .missingReceiptMessageIDs:
			return .missingReceiptMessageIDs
		default:
			return .resendError(String(describing: error))
		}
	}
}
