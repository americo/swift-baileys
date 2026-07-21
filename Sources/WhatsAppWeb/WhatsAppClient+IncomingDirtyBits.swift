import Foundation

extension WhatsAppClient {
	func handleDirtyBitsNode(_ node: BinaryNode) async -> Bool {
		guard node.tag == "ib", let dirty = node.firstChild(named: "dirty") else {
			return false
		}

		switch dirty.attrs["type"] {
		case DirtyBitsType.accountSync.rawValue:
			guard let timestamp = dirty.attrs["timestamp"].flatMap(Int.init) else {
				return true
			}

			if let lastAccountSyncTimestamp = authenticationState?.credentials.lastAccountSyncTimestamp {
				try? await cleanDirtyBits(.accountSync, fromTimestamp: lastAccountSyncTimestamp)
			}

			try? await updateCredentials { credentials in
				credentials.lastAccountSyncTimestamp = timestamp
			}
			return true
		case DirtyBitsType.groups.rawValue:
			_ = try? await groupFetchAllParticipating()
			try? await cleanDirtyBits(.groups)
			return true
		case "communities":
			_ = try? await communityFetchAllParticipating()
			try? await cleanDirtyBits(.groups)
			return true
		default:
			return false
		}
	}
}
