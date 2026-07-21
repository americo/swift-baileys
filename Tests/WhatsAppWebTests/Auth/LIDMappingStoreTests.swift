import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("LID mapping store")
struct LIDMappingStoreTests {
	@Test("stores and resolves phone-number mappings by normalized user JID")
	func storesAndResolvesPhoneNumberMappingsByNormalizedUserJID() async throws {
		let keys = InMemorySignalKeyStore()

		try await LIDMappingStore.store([
			LIDMapping(pn: "123@c.us", lid: "123@lid")
		], in: keys)

		#expect(try await LIDMappingStore.lid(for: "123@s.whatsapp.net", in: keys) == "123@lid")
		#expect(try await LIDMappingStore.phoneNumber(for: "123@lid", in: keys) == "123@s.whatsapp.net")
	}

	@Test("ignores invalid mappings and missing entries")
	func ignoresInvalidMappingsAndMissingEntries() async throws {
		let keys = InMemorySignalKeyStore()

		try await LIDMappingStore.store([
			LIDMapping(pn: "not-a-jid", lid: "123@lid"),
			LIDMapping(pn: "123@s.whatsapp.net", lid: "")
		], in: keys)

		#expect(try await LIDMappingStore.lid(for: "not-a-jid", in: keys) == nil)
		#expect(try await LIDMappingStore.lid(for: "123@s.whatsapp.net", in: keys) == nil)
		#expect(try await LIDMappingStore.phoneNumber(for: "123@lid", in: keys) == nil)
	}
}
