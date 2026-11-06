import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Call stanza builder")
struct CallStanzaBuilderTests {
	@Test("standard Opus capability clears only the MLow bit")
	func standardOpusCapabilityClearsOnlyTheMLowBit() {
		#expect(CallCapability.standardOpusOffer != CallCapability.offer)
		#expect(CallCapability.standardOpusOffer[5] == CallCapability.offer[5] & 0x7f)
		#expect(CallCapability.standardOpusOffer.enumerated().allSatisfy { index, byte in
			index == 5 || byte == CallCapability.offer[index]
		})
		#expect(CallCapability.standardOpusPreaccept[5] == CallCapability.preaccept[5] & 0x7f)
	}

	@Test("offer keeps the mandatory child order for a single device")
	func offerKeepsChildOrderForSingleDevice() throws {
		let node = CallStanzaBuilder.offer(
			callID: "ABC",
			to: "5511@s.whatsapp.net",
			callCreator: "5599:1@s.whatsapp.net",
			stanzaID: "stanza1",
			deviceKeys: [CallOfferDeviceKey(deviceJID: "5511:2@s.whatsapp.net", ciphertext: Data([1, 2]), encryptionType: "msg")],
			privacyToken: Data([9]),
			deviceIdentity: Data([7])
		)

		#expect(node.tag == "call")
		#expect(node.attrs["to"] == "5511@s.whatsapp.net")
		#expect(node.attrs["id"] == "stanza1")
		let offer = try #require(node.children(named: "offer").first)
		#expect(offer.attrs["call-id"] == "ABC")
		#expect(offer.attrs["call-creator"] == "5599:1@s.whatsapp.net")
		guard case let .nodes(children) = offer.content else {
			Issue.record("offer has no children")
			return
		}

		#expect(children.map(\.tag) == [
			"privacy", "audio", "net", "capability", "enc", "encopt", "device-identity"
		])
		#expect(children[1].attrs["rate"] == "16000")
		#expect(children[4].attrs["type"] == "msg")
		#expect(children[4].content == .data(Data([1, 2])))
	}

	@Test("offer addresses several devices through destination")
	func offerAddressesSeveralDevices() throws {
		let keys = [
			CallOfferDeviceKey(deviceJID: "5511:2@s.whatsapp.net", ciphertext: Data([1]), encryptionType: "pkmsg"),
			CallOfferDeviceKey(deviceJID: "5511:3@s.whatsapp.net", ciphertext: Data([2]), encryptionType: "msg")
		]
		let node = CallStanzaBuilder.offer(
			callID: "ABC",
			to: "5511@s.whatsapp.net",
			callCreator: "5599@s.whatsapp.net",
			stanzaID: "s",
			deviceKeys: keys
		)
		let offer = try #require(node.children(named: "offer").first)
		let destination = try #require(offer.children(named: "destination").first)

		#expect(destination.children(named: "to").map { $0.attrs["jid"] } == ["5511:2@s.whatsapp.net", "5511:3@s.whatsapp.net"])
		#expect(offer.children(named: "enc").isEmpty)
		#expect(offer.children(named: "privacy").isEmpty)
	}

	@Test("accept advertises standard Opus settings")
	func acceptAdvertisesStandardOpusSettings() throws {
		let node = CallStanzaBuilder.accept(
			callID: "ABC",
			to: "5511@s.whatsapp.net",
			callCreator: "5511@s.whatsapp.net",
			stanzaID: "s",
			relayTransportEndpoint: Data([5]),
			routingToken: Data([6])
		)
		let accept = try #require(node.children(named: "accept").first)
		guard case let .nodes(children) = accept.content else {
			Issue.record("accept has no children")
			return
		}

		#expect(children.map(\.tag) == ["audio", "te", "net", "encopt", "capability", "rte", "voip_settings"])
		#expect(children[2].attrs["medium"] == "2")
		#expect(children.last?.content == .data(CallVoIPSettings.standardOpus16kHzClock))
	}

	@Test("preaccept carries audio, encopt and capability")
	func preacceptCarriesAudioEncoptAndCapability() throws {
		let node = CallStanzaBuilder.preaccept(
			callID: "ABC",
			to: "5511@s.whatsapp.net",
			callCreator: "5511@s.whatsapp.net",
			stanzaID: "s"
		)
		let preaccept = try #require(node.children(named: "preaccept").first)
		guard case let .nodes(children) = preaccept.content else {
			Issue.record("preaccept has no children")
			return
		}

		#expect(children.map(\.tag) == ["audio", "encopt", "capability"])
	}

	@Test("transport carries the round and message type the caller answers with")
	func transportCarriesRoundAndType() throws {
		let node = CallStanzaBuilder.transport(callID: "ABC", to: "1:2@lid", callCreator: "9@lid", stanzaID: "s")
		let transport = try #require(node.children(named: "transport").first)

		#expect(node.attrs["to"] == "1:2@lid")
		#expect(transport.attrs["p2p-cand-round"] == "1")
		#expect(transport.attrs["transport-message-type"] == "1")
		#expect(transport.children(named: "net").first?.attrs["protocol"] == "0")
	}

	@Test("relay latency encodes the offset and lists the devices")
	func relayLatencyEncodesOffset() throws {
		let node = CallStanzaBuilder.relayLatency(
			callID: "ABC",
			to: "1@lid",
			callCreator: "9@lid",
			stanzaID: "s",
			latencyMs: 40,
			relayName: "gru1",
			relayAddress: Data([1, 2, 3, 4, 5, 6]),
			devices: ["1:2@lid"]
		)
		let action = try #require(node.children(named: "relaylatency").first)

		#expect(action.children(named: "te").first?.attrs["latency"] == "33554472")
		#expect(action.children(named: "te").first?.attrs["relay_name"] == "gru1")
		#expect(action.children(named: "destination").first?.children(named: "to").first?.attrs["jid"] == "1:2@lid")
	}

	@Test("offer receipt echoes the stanza id")
	func offerReceiptEchoesStanzaID() throws {
		let node = CallStanzaBuilder.offerReceipt(callID: "ABC", to: "1:2@lid", callCreator: "1:2@lid", stanzaID: "st", from: nil)

		#expect(node.tag == "receipt")
		#expect(node.attrs["id"] == "st")
		#expect(node.attrs["from"] == nil)
		#expect(node.children(named: "offer").first?.attrs["call-id"] == "ABC")
	}

	@Test("reject and terminate include optional reasons")
	func rejectAndTerminateIncludeReasons() throws {
		let reject = CallStanzaBuilder.reject(
			callID: "ABC",
			to: "5511@s.whatsapp.net",
			callCreator: "5511@s.whatsapp.net",
			stanzaID: "s",
			reason: CallStanzaBuilder.rejectReasonBusy
		)
		let terminate = CallStanzaBuilder.terminate(
			callID: "ABC",
			to: "5511@s.whatsapp.net",
			callCreator: "5599@s.whatsapp.net",
			stanzaID: "s"
		)

		#expect(try #require(reject.children(named: "reject").first).attrs["reason"] == "busy")
		#expect(try #require(terminate.children(named: "terminate").first).attrs["reason"] == nil)
	}
}
