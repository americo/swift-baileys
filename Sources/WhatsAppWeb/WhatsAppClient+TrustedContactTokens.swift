import Foundation

extension WhatsAppClient {
	func pruneExpiredTrustedContactTokens(now: Date = Date()) async {
		guard let keys = authenticationState?.keys else {
			return
		}

		try? await TrustedContactTokenCoding.pruneExpiredTokens(in: keys, now: now)
	}

	func reissueTrustedContactTokenAfterIdentityChange(from jid: String) async {
		guard let keys = authenticationState?.keys,
			  let storageJID = JID(jid)?.normalizedUser,
			  TrustedContactTokenCoding.isRegularUserJID(storageJID),
			  !inFlightTrustedContactTokenIssues.contains(storageJID) else {
			return
		}

		let currentData = try? await keys.get(.tcToken, ids: [storageJID])[storageJID]
		guard let current = currentData.flatMap({ try? TrustedContactTokenCoding.decode($0) }),
			  let senderTimestamp = current.senderTimestamp,
			  !TrustedContactTokenCoding.isExpired(senderTimestamp),
			  let timestamp = Int(senderTimestamp) else {
			return
		}

		inFlightTrustedContactTokenIssues.insert(storageJID)
		Task {
			do {
				_ = try await self.issuePrivacyTokens(
					for: [storageJID],
					timestamp: timestamp,
					timeout: .seconds(15)
				)
			} catch {}

			self.finishTrustedContactTokenIssue(storageJID: storageJID)
		}
	}

	func recoverTrustedContactTokenAfterAccountRestriction(from jid: String?) async {
		guard let jid,
			  let storageJID = JID(jid)?.normalizedUser,
			  TrustedContactTokenCoding.isRegularUserJID(storageJID),
			  !inFlightTrustedContactTokenIssues.contains(storageJID) else {
			return
		}

		inFlightTrustedContactTokenIssues.insert(storageJID)
		let timestamp = Int(UnixTimestamp.seconds())
		Task {
			do {
				_ = try await self.issuePrivacyTokens(
					for: [storageJID],
					timestamp: timestamp,
					timeout: .seconds(15)
				)
			} catch {}

			self.finishTrustedContactTokenIssue(storageJID: storageJID)
		}
	}
}
