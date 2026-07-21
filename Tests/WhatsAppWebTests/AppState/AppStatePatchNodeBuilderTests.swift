import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("App-state patch node builder")
struct AppStatePatchNodeBuilderTests {
	@Test("builds Baileys-compatible app-state sync IQ")
	func buildsBaileysCompatibleAppStateSyncIQ() throws {
		var patch = Proto_SyncdPatch()
		patch.patchMac = Data([1, 2, 3])
		patch.snapshotMac = Data([4, 5, 6])
		var state = AppStatePatchState()
		state.version = 3

		let node = try AppStatePatchNodeBuilder.syncIQ(
			for: .regularLow,
			encodingResult: AppStatePatchEncodingResult(patch: patch, state: state),
			requestID: "app-state-1"
		)

		#expect(node.tag == "iq")
		#expect(node.attrs["id"] == "app-state-1")
		#expect(node.attrs["to"] == "@s.whatsapp.net")
		#expect(node.attrs["type"] == "set")
		#expect(node.attrs["xmlns"] == "w:sync:app:state")
		let sync = try #require(node.firstChild(named: "sync"))
		let collection = try #require(sync.firstChild(named: "collection"))
		#expect(collection.attrs["name"] == "regular_low")
		#expect(collection.attrs["version"] == "2")
		#expect(collection.attrs["return_snapshot"] == "false")
		#expect(collection.firstChild(named: "patch")?.content == .data(try patch.serializedData()))
	}

	@Test("rejects empty app-state patch request id")
	func rejectsEmptyAppStatePatchRequestID() throws {
		let patch = Proto_SyncdPatch()
		var state = AppStatePatchState()
		state.version = 1

		#expect(throws: AppStatePatchNodeBuilderError.emptyRequestID) {
			try AppStatePatchNodeBuilder.syncIQ(
				for: .regularLow,
				encodingResult: AppStatePatchEncodingResult(patch: patch, state: state),
				requestID: ""
			)
		}
	}
}
