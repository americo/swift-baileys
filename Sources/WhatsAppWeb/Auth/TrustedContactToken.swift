import Foundation

public struct TrustedContactToken: Codable, Equatable, Sendable {
	public var token: Data
	public var timestamp: String
	public var senderTimestamp: String?

	public init(token: Data, timestamp: String, senderTimestamp: String? = nil) {
		self.token = token
		self.timestamp = timestamp
		self.senderTimestamp = senderTimestamp
	}
}

public enum TrustedContactTokenCoding {
	static let indexKey = "__index"

	public static func encode(_ token: TrustedContactToken) throws -> Data {
		try JSONEncoder().encode(token)
	}

	public static func decode(_ data: Data) throws -> TrustedContactToken {
		try JSONDecoder().decode(TrustedContactToken.self, from: data)
	}

	static func encodeIndex(_ jids: [String]) throws -> Data {
		try JSONEncoder().encode(jids)
	}

	static func decodeIndex(_ data: Data?) throws -> [String] {
		guard let data,
			  let jids = try? JSONDecoder().decode([String].self, from: data) else {
			return []
		}

		return jids.filter { !$0.isEmpty && $0 != indexKey }
	}

	static func mergedIndexData(in keys: any SignalKeyStore, adding jids: [String]) async throws -> Data {
		let existing = try await keys.get(.tcToken, ids: [indexKey])[indexKey]
		var merged = try decodeIndex(existing)
		for jid in jids where !jid.isEmpty && jid != indexKey && !merged.contains(jid) {
			merged.append(jid)
		}
		return try encodeIndex(merged)
	}

	static func pruneExpiredTokens(in keys: any SignalKeyStore, now: Date = Date()) async throws {
		let indexData = try await keys.get(.tcToken, ids: [indexKey])[indexKey]
		let indexedJIDs = try decodeIndex(indexData)
		guard !indexedJIDs.isEmpty else {
			return
		}

		let stored = try await keys.get(.tcToken, ids: indexedJIDs)
		var updates: [String: Data?] = [:]
		var survivors: [String] = []

		for jid in indexedJIDs {
			guard let data = stored[jid],
				  let token = try? decode(data) else {
				updates.updateValue(nil, forKey: jid)
				continue
			}

			let peerTokenExpired = !token.token.isEmpty && isExpired(token.timestamp, now: now)
			let senderTimestampExpired = token.senderTimestamp.map { isExpired($0, now: now) } ?? false
			let keepPeerToken = !token.token.isEmpty && !peerTokenExpired
			let keepSenderTimestamp = token.senderTimestamp != nil && !senderTimestampExpired

			if !keepPeerToken && !keepSenderTimestamp {
				updates.updateValue(nil, forKey: jid)
			} else if peerTokenExpired && keepSenderTimestamp {
				updates[jid] = try encode(TrustedContactToken(
					token: Data(),
					timestamp: token.timestamp,
					senderTimestamp: token.senderTimestamp
				))
				survivors.append(jid)
			} else {
				survivors.append(jid)
			}
		}

		guard !updates.isEmpty || survivors != indexedJIDs else {
			return
		}

		updates[indexKey] = try encodeIndex(survivors)
		try await keys.set([.tcToken: updates])
	}

	static func storeHistorySyncTokens(
		from chats: [Proto_Conversation],
		in keys: any SignalKeyStore,
		resolveLIDForPN: (@Sendable (String) async throws -> String?)? = nil
	) async throws {
		let rawCandidates = chats.compactMap { chat -> (jid: String, token: Data, timestamp: String, senderTimestamp: String?)? in
			guard chat.hasTcToken,
				  !chat.tcToken.isEmpty,
				  chat.hasTcTokenTimestamp,
				  chat.tcTokenTimestamp > 0,
				  let jid = JID(chat.id)?.normalizedUser else {
				return nil
			}

			return (
				jid,
				chat.tcToken,
				String(chat.tcTokenTimestamp),
				chat.hasTcTokenSenderTimestamp ? String(chat.tcTokenSenderTimestamp) : nil
			)
		}
		var candidates: [(jid: String, token: Data, timestamp: String, senderTimestamp: String?)] = []
		candidates.reserveCapacity(rawCandidates.count)
		for candidate in rawCandidates {
			guard let storageJID = try await storageJID(for: candidate.jid, resolveLIDForPN: resolveLIDForPN) else {
				continue
			}

			candidates.append((
				storageJID,
				candidate.token,
				candidate.timestamp,
				candidate.senderTimestamp
			))
		}
		guard !candidates.isEmpty else {
			return
		}

		let existing = try await keys.get(.tcToken, ids: candidates.map(\.jid))
		var updates: [String: Data?] = [:]
		var storedJIDs: [String] = []

		for candidate in candidates {
			let current = existing[candidate.jid].flatMap { try? decode($0) }
			let currentTimestamp = current.flatMap { Int($0.timestamp) } ?? 0
			guard currentTimestamp < (Int(candidate.timestamp) ?? 0) else {
				continue
			}

			updates[candidate.jid] = try encode(TrustedContactToken(
				token: candidate.token,
				timestamp: candidate.timestamp,
				senderTimestamp: candidate.senderTimestamp ?? current?.senderTimestamp
			))
			storedJIDs.append(candidate.jid)
		}

		guard !updates.isEmpty else {
			return
		}

		updates[indexKey] = try await mergedIndexData(in: keys, adding: storedJIDs)
		try await keys.set([.tcToken: updates])
	}

	public static func isExpired(_ timestamp: String, now: Date = Date()) -> Bool {
		guard let value = Int(timestamp) else {
			return true
		}

		let bucketDuration = 604_800
		let currentBucket = Int(now.timeIntervalSince1970) / bucketDuration
		let cutoffBucket = currentBucket - 3
		return value < cutoffBucket * bucketDuration
	}

	static func shouldSendNewToken(senderTimestamp: String?, now: Date = Date()) -> Bool {
		guard let senderTimestamp, let value = Int(senderTimestamp) else {
			return true
		}

		let bucketDuration = 604_800
		let currentBucket = Int(now.timeIntervalSince1970) / bucketDuration
		let senderBucket = value / bucketDuration
		return currentBucket > senderBucket
	}

	static func isRegularUserJID(_ jid: String?) -> Bool {
		guard let parsed = JID(jid) else {
			return false
		}

		if parsed.user == "0" {
			return false
		}

		if parsed.user.range(of: #"^1313555\d{4}$|^131655500\d{2}$"#, options: .regularExpression) != nil {
			return false
		}

		return parsed.normalizedUser.isWhatsAppUserJID || parsed.normalizedUser.isLIDUserJID
	}

	static func storageJID(
		for jid: String,
		resolveLIDForPN: (@Sendable (String) async throws -> String?)? = nil
	) async throws -> String? {
		guard isRegularUserJID(jid) else {
			return nil
		}

		if jid.isLIDUserJID {
			return jid
		}

		return try await resolveLIDForPN?(jid) ?? jid
	}
}

enum TrustedContactTokenNodeBuilder {
	static func build(
		for jid: String,
		keys: (any SignalKeyStore)?,
		resolveLIDForPN: (@Sendable (String) async throws -> String?)? = nil
	) async -> BinaryNode? {
		guard let keys,
			  let normalizedJID = JID(jid)?.normalizedUser else {
			return nil
		}

		do {
			guard let storageJID = try await TrustedContactTokenCoding.storageJID(
				for: normalizedJID,
				resolveLIDForPN: resolveLIDForPN
			) else {
				return nil
			}

			guard let data = try await keys.get(.tcToken, ids: [storageJID])[storageJID] else {
				return nil
			}

			let token = try TrustedContactTokenCoding.decode(data)
			if TrustedContactTokenCoding.isExpired(token.timestamp) || token.token.isEmpty {
				let cleared: Data?
				if let senderTimestamp = token.senderTimestamp {
					cleared = try TrustedContactTokenCoding.encode(TrustedContactToken(
						token: Data(),
						timestamp: token.timestamp,
						senderTimestamp: senderTimestamp
					))
				} else {
					cleared = nil
				}
				try await keys.set([.tcToken: [storageJID: cleared]])
				return nil
			}

			return BinaryNode(tag: "tctoken", content: .data(token.token))
		} catch {
			return nil
		}
	}
}
