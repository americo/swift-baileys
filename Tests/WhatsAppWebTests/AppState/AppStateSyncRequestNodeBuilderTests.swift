import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("App-state sync request node builder")
struct AppStateSyncRequestNodeBuilderTests {
	@Test("builds Baileys-compatible app-state sync request IQ")
	func buildsBaileysCompatibleAppStateSyncRequestIQ() throws {
		let node = try AppStateSyncRequestNodeBuilder.syncIQ(
			collections: [
				AppStateSyncCollectionRequest(name: .regularLow, version: 3, returnSnapshot: false),
				AppStateSyncCollectionRequest(name: .criticalUnblockLow, version: 0, returnSnapshot: true)
			],
			requestID: "sync-1"
		)

		#expect(node.attrs["id"] == "sync-1")
		let sync = try #require(node.firstChild(named: "sync"))
		let collections = sync.children(named: "collection")
		#expect(collections.map { $0.attrs["name"] } == ["regular_low", "critical_unblock_low"])
		#expect(collections.map { $0.attrs["version"] } == ["3", "0"])
		#expect(collections.map { $0.attrs["return_snapshot"] } == ["false", "true"])
	}

	@Test("rejects invalid app-state sync request inputs")
	func rejectsInvalidAppStateSyncRequestInputs() throws {
		#expect(throws: AppStateSyncRequestNodeBuilderError.emptyRequestID) {
			try AppStateSyncRequestNodeBuilder.syncIQ(
				collections: [AppStateSyncCollectionRequest(name: .regularLow, version: 1, returnSnapshot: false)],
				requestID: ""
			)
		}
		#expect(throws: AppStateSyncRequestNodeBuilderError.emptyCollections) {
			try AppStateSyncRequestNodeBuilder.syncIQ(collections: [], requestID: "sync-2")
		}
	}
}
