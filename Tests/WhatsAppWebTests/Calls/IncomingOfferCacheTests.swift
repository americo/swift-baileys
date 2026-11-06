import Foundation
import Testing
@testable import WhatsAppWeb

/// `prepareIncomingVoiceCall` reads the stored offer, so losing it makes the call unanswerable.
@Suite("Incoming offer cache")
struct IncomingOfferCacheTests {
	private func client() -> WhatsAppClient {
		WhatsAppClient(authenticationState: nil, transportFactory: { _ in MockMessageSendWebSocketTransport() })
	}

	private func stanza(_ action: String, sender: String? = nil, reason: String? = nil) -> BinaryNode {
		BinaryNode(
			tag: "call",
			attrs: BinaryNodeAttributes.trimmingUndefined([
				("from", "111:0@lid"), ("id", "s1"), ("t", "1"), ("participant", sender)
			]),
			content: .nodes([BinaryNode(
				tag: action,
				attrs: BinaryNodeAttributes.trimmingUndefined([
					("call-id", "CALL"), ("call-creator", "111:0@lid"), ("reason", reason)
				])
			)])
		)
	}

	@Test("a hosted device turning the offer down keeps it answerable")
	func hostedRejectKeepsOffer() async {
		let client = client()
		_ = await client.handleCallNode(stanza("offer"))
		_ = await client.handleCallNode(stanza("reject", sender: "222:99@hosted.lid", reason: "uncallable"))

		#expect(await client.callOfferNodes["CALL"] != nil)
	}

	@Test("per-device reasons keep the offer answerable", arguments: ["busy", "enc", "uncallable"])
	func perDeviceReasonsKeepOffer(reason: String) async {
		let client = client()
		_ = await client.handleCallNode(stanza("offer"))
		_ = await client.handleCallNode(stanza("reject", sender: "222:3@lid", reason: reason))

		#expect(await client.callOfferNodes["CALL"] != nil)
	}

	@Test("a real decline and a terminate clear the offer", arguments: ["reject", "terminate"])
	func decisionsClearOffer(action: String) async {
		let client = client()
		_ = await client.handleCallNode(stanza("offer"))
		_ = await client.handleCallNode(stanza(action, sender: "222:0@lid"))

		#expect(await client.callOfferNodes["CALL"] == nil)
	}

	@Test("only rejects can be device-only")
	func onlyRejectsAreDeviceOnly() {
		func event(_ status: WhatsAppCallUpdateType, sender: String?, reason: String?) -> WhatsAppCallEvent {
			WhatsAppCallEvent(chatID: "1@lid", from: "1@lid", id: "C", date: Date(), status: status, offline: false, senderJID: sender, reason: reason)
		}

		#expect(event(.reject, sender: "2:99@hosted.lid", reason: nil).isDeviceOnlyReject)
		#expect(event(.reject, sender: "2:3@lid", reason: "busy").isDeviceOnlyReject)
		#expect(!event(.reject, sender: "2:0@lid", reason: nil).isDeviceOnlyReject)
		#expect(!event(.reject, sender: "2:0@lid", reason: "declined").isDeviceOnlyReject)
		#expect(!event(.terminate, sender: "2:99@hosted.lid", reason: "busy").isDeviceOnlyReject)
	}
}
