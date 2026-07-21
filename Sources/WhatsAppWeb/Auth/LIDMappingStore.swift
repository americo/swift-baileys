import Foundation

public enum LIDMappingStore {
	public static func store(_ mappings: [LIDMapping], in keys: any SignalKeyStore) async throws {
		var updates: [String: Data?] = [:]
		for mapping in mappings {
			guard let pn = JID(mapping.pn)?.normalizedUser,
				  pn.isWhatsAppUserJID,
				  let lid = JID(mapping.lid)?.normalizedUser,
				  lid.isLIDUserJID else {
				continue
			}

			updates[pn] = Data(lid.utf8)
			updates[lid] = Data(pn.utf8)
		}

		if !updates.isEmpty {
			try await keys.set([.lidMapping: updates])
		}
	}

	public static func lid(for phoneNumberJID: String, in keys: any SignalKeyStore) async throws -> String? {
		guard let pn = JID(phoneNumberJID)?.normalizedUser else {
			return nil
		}

		guard let data = try await keys.get(.lidMapping, ids: [pn])[pn],
			  let lid = String(data: data, encoding: .utf8),
			  !lid.isEmpty else {
			return nil
		}

		return lid
	}

	public static func phoneNumber(for lidJID: String, in keys: any SignalKeyStore) async throws -> String? {
		guard let lid = JID(lidJID)?.normalizedUser,
			  lid.isLIDUserJID else {
			return nil
		}

		guard let data = try await keys.get(.lidMapping, ids: [lid])[lid],
			  let pn = String(data: data, encoding: .utf8),
			  !pn.isEmpty else {
			return nil
		}

		return pn
	}
}
