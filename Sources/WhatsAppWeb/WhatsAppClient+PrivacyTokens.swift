import Foundation

extension WhatsAppClient {
	@discardableResult
	public func issuePrivacyTokens(
		for jids: [String],
		timestamp: Int? = nil,
		requestID: String? = nil,
		timeout: Duration = .seconds(60)
	) async throws -> BinaryNode {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let issuedTimestamp = String(timestamp ?? Int(UnixTimestamp.seconds()))
		var issueJIDs: [String] = []
		issueJIDs.reserveCapacity(jids.count)
		for jid in jids {
			let normalized = JID(jid)?.normalizedUser ?? jid
			if let keys = authenticationState?.keys {
				if serverProps.lidTrustedTokenIssueToLID, !normalized.isLIDUserJID {
					issueJIDs.append(try await LIDMappingStore.lid(for: normalized, in: keys) ?? normalized)
				} else if !serverProps.lidTrustedTokenIssueToLID, normalized.isLIDUserJID {
					issueJIDs.append(try await LIDMappingStore.phoneNumber(for: normalized, in: keys) ?? normalized)
				} else {
					issueJIDs.append(normalized)
				}
			} else {
				issueJIDs.append(normalized)
			}
		}
		let tokenNodes = issueJIDs.map { jid in
			BinaryNode(
				tag: "token",
				attrs: [
					"jid": jid,
					"t": issuedTimestamp,
					"type": "trusted_contact"
				]
			)
		}

		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"to": "@s.whatsapp.net",
				"type": "set",
				"xmlns": "privacy"
			],
			content: .nodes([
				BinaryNode(tag: "tokens", content: .nodes(tokenNodes))
			])
		), timeout: timeout)
		await storeTrustedContactTokens(from: result, fallbackJIDs: issueJIDs)
		return result
	}

	func scheduleTrustedContactTokenIssueAfterSend(
		to destinationJID: String,
		message: Proto_Message,
		additionalAttributes: [String: String]
	) async {
		guard let keys = authenticationState?.keys,
			  additionalAttributes["category"] != "peer",
			  !message.hasProtocolMessage,
			  let storageJID = JID(destinationJID)?.normalizedUser,
			  TrustedContactTokenCoding.isRegularUserJID(storageJID),
			  !inFlightTrustedContactTokenIssues.contains(storageJID) else {
			return
		}

		let existing = try? await keys.get(.tcToken, ids: [storageJID])[storageJID]
			.flatMap { try? TrustedContactTokenCoding.decode($0) }
		guard TrustedContactTokenCoding.shouldSendNewToken(senderTimestamp: existing?.senderTimestamp) else {
			return
		}

		inFlightTrustedContactTokenIssues.insert(storageJID)
		let senderTimestamp = Int(UnixTimestamp.seconds())
		Task {
			do {
				_ = try await self.issuePrivacyTokens(
					for: [storageJID],
					timestamp: senderTimestamp,
					timeout: .seconds(15)
				)
				await self.persistTrustedContactTokenIssue(
					storageJID: storageJID,
					senderTimestamp: String(senderTimestamp)
				)
			} catch {}

			self.finishTrustedContactTokenIssue(storageJID: storageJID)
		}
	}

	private func persistTrustedContactTokenIssue(storageJID: String, senderTimestamp: String) async {
		guard let keys = authenticationState?.keys else {
			return
		}

		do {
			let currentData = try await keys.get(.tcToken, ids: [storageJID])[storageJID]
			let current = currentData.flatMap { try? TrustedContactTokenCoding.decode($0) }
			let token = TrustedContactToken(
				token: current?.token ?? Data(),
				timestamp: current?.timestamp ?? senderTimestamp,
				senderTimestamp: senderTimestamp
			)
			let index = try await TrustedContactTokenCoding.mergedIndexData(in: keys, adding: [storageJID])
			try await keys.set([.tcToken: [
				storageJID: TrustedContactTokenCoding.encode(token),
				TrustedContactTokenCoding.indexKey: index
			]])
		} catch {}
	}

	func finishTrustedContactTokenIssue(storageJID: String) {
		inFlightTrustedContactTokenIssues.remove(storageJID)
	}

	private func storeTrustedContactTokens(from result: BinaryNode, fallbackJIDs: [String]) async {
		guard let keys = authenticationState?.keys,
			  let tokensNode = result.firstChild(named: "tokens") else {
			return
		}

		let normalizedFallbacks = fallbackJIDs.compactMap { JID($0)?.normalizedUser }
		for (index, tokenNode) in tokensNode.children(named: "token").enumerated() {
			guard tokenNode.attrs["type"] == "trusted_contact",
				  let timestamp = tokenNode.attrs["t"],
				  Int(timestamp) != nil,
				  case let .data(tokenData) = tokenNode.content else {
				continue
			}

			let rawJID = normalizedFallbacks.indices.contains(index)
				? normalizedFallbacks[index]
				: tokenNode.attrs["jid"].flatMap { JID($0)?.normalizedUser }
			guard let storageJID = rawJID,
				  TrustedContactTokenCoding.isRegularUserJID(storageJID) else {
				continue
			}

			do {
				let existingData = try await keys.get(.tcToken, ids: [storageJID])[storageJID]
				let existing = existingData.flatMap { try? TrustedContactTokenCoding.decode($0) }
				let existingTimestamp = existing.flatMap { Int($0.timestamp) } ?? 0
				let incomingTimestamp = Int(timestamp) ?? 0
				guard existingTimestamp <= incomingTimestamp else {
					continue
				}

				let token = TrustedContactToken(
					token: tokenData,
					timestamp: timestamp,
					senderTimestamp: existing?.senderTimestamp
				)
				let index = try await TrustedContactTokenCoding.mergedIndexData(in: keys, adding: [storageJID])
				try await keys.set([.tcToken: [
					storageJID: TrustedContactTokenCoding.encode(token),
					TrustedContactTokenCoding.indexKey: index
				]])
			} catch {
				continue
			}
		}
	}
}
