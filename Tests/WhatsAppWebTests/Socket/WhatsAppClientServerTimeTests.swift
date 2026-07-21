import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client server time")
struct WhatsAppClientServerTimeTests {
	@Test("Baileys updateServerTimeOffset alias stores server clock difference")
	func baileysUpdateServerTimeOffsetAliasStoresServerClockDifference() async {
		let client = WhatsAppClient()

		await client.updateServerTimeOffset(
			BinaryNode(tag: "ib", attrs: ["t": "1700000100"]),
			localDate: Date(timeIntervalSince1970: 1_700_000_000)
		)

		#expect(await client.serverTimeOffsetMilliseconds == 100_000)
		#expect(await client.unixTimestampSeconds(from: Date(timeIntervalSince1970: 1_700_000_001)) == 1_700_000_101)
	}

	@Test("Baileys updateServerTimeOffset alias ignores missing invalid and nonpositive timestamps")
	func baileysUpdateServerTimeOffsetAliasIgnoresInvalidTimestamps() async {
		let client = WhatsAppClient()
		await client.updateServerTimeOffset(
			BinaryNode(tag: "ib", attrs: ["t": "1700000100"]),
			localDate: Date(timeIntervalSince1970: 1_700_000_000)
		)

		await client.updateServerTimeOffset(BinaryNode(tag: "ib"), localDate: Date(timeIntervalSince1970: 1))
		await client.updateServerTimeOffset(BinaryNode(tag: "ib", attrs: ["t": "abc"]), localDate: Date(timeIntervalSince1970: 1))
		await client.updateServerTimeOffset(BinaryNode(tag: "ib", attrs: ["t": "0"]), localDate: Date(timeIntervalSince1970: 1))

		#expect(await client.serverTimeOffsetMilliseconds == 100_000)
	}
}
