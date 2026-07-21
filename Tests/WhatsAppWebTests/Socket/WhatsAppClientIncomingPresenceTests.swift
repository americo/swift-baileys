import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client incoming presence")
struct WhatsAppClientIncomingPresenceTests {
	@Test("emits presence updates from presence stanzas")
	func emitsPresenceUpdatesFromPresenceStanzas() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "presence",
			attrs: [
				"from": "123@s.whatsapp.net",
				"type": "unavailable",
				"last": "1700000000",
				"count": "4"
			]
		))

		#expect(await events.next() == .presenceUpdated(WhatsAppPresenceUpdate(
			id: "123@s.whatsapp.net",
			presences: [
				"123@s.whatsapp.net": WhatsAppPresenceData(
					lastKnownPresence: .unavailable,
					lastSeen: 1_700_000_000,
					groupOnlineCount: 4
				)
			]
		)))
	}

	@Test("emits recording presence from audio chatstate")
	func emitsRecordingPresenceFromAudioChatstate() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "chatstate",
			attrs: ["from": "123@g.us", "participant": "456@s.whatsapp.net"],
			content: .nodes([
				BinaryNode(tag: "composing", attrs: ["media": "audio"])
			])
		))

		#expect(await events.next() == .presenceUpdated(WhatsAppPresenceUpdate(
			id: "123@g.us",
			presences: [
				"456@s.whatsapp.net": WhatsAppPresenceData(lastKnownPresence: .recording)
			]
		)))
	}

	@Test("maps paused chatstate to available presence")
	func mapsPausedChatstateToAvailablePresence() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "chatstate",
			attrs: ["from": "123@s.whatsapp.net"],
			content: .nodes([
				BinaryNode(tag: "paused")
			])
		))

		#expect(await events.next() == .presenceUpdated(WhatsAppPresenceUpdate(
			id: "123@s.whatsapp.net",
			presences: [
				"123@s.whatsapp.net": WhatsAppPresenceData(lastKnownPresence: .available)
			]
		)))
	}

	@Test("ignores presence updates when configuration filters the jid")
	func ignoresPresenceUpdatesWhenConfigurationFiltersJID() async {
		let client = WhatsAppClient(configuration: WhatsAppClientConfiguration(
			shouldIgnoreJID: { $0 == "123@s.whatsapp.net" }
		))

		let handled = await client.handlePresenceNode(BinaryNode(
			tag: "presence",
			attrs: ["from": "123@s.whatsapp.net", "type": "available"]
		))

		#expect(!handled)
	}

	@Test("does not ignore WhatsApp server presence updates")
	func doesNotIgnoreWhatsAppServerPresenceUpdates() async {
		let client = WhatsAppClient(configuration: WhatsAppClientConfiguration(
			shouldIgnoreJID: { _ in true }
		))
		var events = client.events.makeAsyncIterator()

		let handled = await client.handlePresenceNode(BinaryNode(
			tag: "presence",
			attrs: ["from": "@s.whatsapp.net", "type": "available"]
		))

		#expect(handled)
		#expect(await events.next() == .presenceUpdated(WhatsAppPresenceUpdate(
			id: "@s.whatsapp.net",
			presences: [
				"@s.whatsapp.net": WhatsAppPresenceData(lastKnownPresence: .available)
			]
		)))
	}
}
