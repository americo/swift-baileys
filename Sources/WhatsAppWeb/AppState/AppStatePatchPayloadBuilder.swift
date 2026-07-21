import Foundation

enum AppStatePatchPayloadBuilder {
	static func syncActionData(for patch: ChatModificationPatch) throws -> Proto_SyncActionData {
		var data = Proto_SyncActionData()
		data.index = try JSONSerialization.data(withJSONObject: patch.index, options: [])
		data.value = patch.syncAction
		data.padding = Data()
		data.version = Int32(patch.apiVersion)
		return data
	}
}
