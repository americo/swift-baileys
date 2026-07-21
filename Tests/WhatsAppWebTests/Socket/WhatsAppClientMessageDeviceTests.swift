import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client message device compatibility")
struct WhatsAppClientMessageDeviceTests {
	@Test("Baileys getUSyncDevices alias resolves user device JIDs")
	func baileysGetUSyncDevicesAliasResolvesUserDeviceJIDs() async throws {
		let resolver = RecordingMessageDeviceResolver(results: [
			"123@s.whatsapp.net": ["123:0@s.whatsapp.net", "123:2@s.whatsapp.net"],
			"456@s.whatsapp.net": ["456:0@s.whatsapp.net"]
		])
		let client = WhatsAppClient(messageDependencies: WhatsAppClientMessageDependencies(
			messageEncryptor: StubMessageSendEncryptor(results: []),
			messageDeviceResolver: resolver,
			signalSessionPreparer: PublicSessionPreparer()
		))

		let devices = try await client.getUSyncDevices(
			["123@s.whatsapp.net", "456@c.us"],
			useCache: true,
			ignoreZeroDevices: false
		)

		#expect(devices == [
			BaileysMessageDevice(user: "123", device: 0, jid: "123:0@s.whatsapp.net"),
			BaileysMessageDevice(user: "123", device: 2, jid: "123:2@s.whatsapp.net"),
			BaileysMessageDevice(user: "456", device: 0, jid: "456:0@s.whatsapp.net")
		])
		#expect(await resolver.calls == ["123@s.whatsapp.net", "456@s.whatsapp.net"])
	}

	@Test("Baileys getUSyncDevices alias preserves explicit device JIDs")
	func baileysGetUSyncDevicesAliasPreservesExplicitDeviceJIDs() async throws {
		let resolver = RecordingMessageDeviceResolver(results: [:])
		let client = WhatsAppClient(messageDependencies: WhatsAppClientMessageDependencies(
			messageEncryptor: StubMessageSendEncryptor(results: []),
			messageDeviceResolver: resolver,
			signalSessionPreparer: PublicSessionPreparer()
		))

		let devices = try await client.getUSyncDevices(["123:4@s.whatsapp.net"])

		#expect(devices == [
			BaileysMessageDevice(user: "123", device: 4, jid: "123:4@s.whatsapp.net")
		])
		#expect(await resolver.calls.isEmpty)
	}

	@Test("Baileys getUSyncDevices alias can ignore zero devices")
	func baileysGetUSyncDevicesAliasCanIgnoreZeroDevices() async throws {
		let resolver = RecordingMessageDeviceResolver(results: [
			"123@s.whatsapp.net": ["123:0@s.whatsapp.net", "123:3@s.whatsapp.net"]
		])
		let client = WhatsAppClient(messageDependencies: WhatsAppClientMessageDependencies(
			messageEncryptor: StubMessageSendEncryptor(results: []),
			messageDeviceResolver: resolver,
			signalSessionPreparer: PublicSessionPreparer()
		))

		let devices = try await client.getUSyncDevices(
			["123:0@s.whatsapp.net", "123@s.whatsapp.net"],
			ignoreZeroDevices: true
		)

		#expect(devices == [
			BaileysMessageDevice(user: "123", device: 3, jid: "123:3@s.whatsapp.net")
		])
	}

	@Test("Baileys getUSyncDevices alias requires message device resolver")
	func baileysGetUSyncDevicesAliasRequiresMessageDeviceResolver() async {
		let client = WhatsAppClient()

		await #expect(throws: WhatsAppClientError.missingMessageDeviceResolver) {
			try await client.getUSyncDevices(["123@s.whatsapp.net"])
		}
	}
}

private actor RecordingMessageDeviceResolver: MessageDeviceResolving {
	private let results: [String: [String]]
	private(set) var calls: [String] = []

	init(results: [String: [String]]) {
		self.results = results
	}

	func deviceJIDs(for jid: String) async throws -> [String] {
		calls.append(jid)
		return results[jid] ?? []
	}
}
