import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Call key message")
struct CallKeyMessageTests {
	@Test("generates 32 random bytes")
	func generatesRandomKeys() throws {
		let first = try CallKeyMessage.generateCallKey()
		let second = try CallKeyMessage.generateCallKey()

		#expect(first.count == 32)
		#expect(first != second)
	}

	@Test("roundtrips through the padded message encoding")
	func roundtripsThroughPaddedEncoding() throws {
		let key = Data((0..<32).map(UInt8.init))
		let encoded = try CallKeyMessage.encode(callKey: key)
		let message = try Proto_Message(serializedBytes: MessagePadding.unpadded(encoded))

		#expect(CallKeyMessage.callKey(from: message) == key)
	}

	@Test("rejects messages without a usable key")
	func rejectsMessagesWithoutUsableKey() {
		#expect(CallKeyMessage.callKey(from: Proto_Message()) == nil)

		var short = Proto_Message()
		short.call.callKey = Data(count: 8)
		#expect(CallKeyMessage.callKey(from: short) == nil)
	}

	@Test("picks the enc addressed to this account")
	func picksEncAddressedToThisAccount() {
		let other = BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([1])))
		let mine = BinaryNode(tag: "enc", attrs: ["type": "pkmsg"], content: .data(Data([2])))
		let offer = BinaryNode(tag: "offer", content: .nodes([
			BinaryNode(tag: "destination", content: .nodes([
				BinaryNode(tag: "to", attrs: ["jid": "111:2@lid"], content: .nodes([other])),
				BinaryNode(tag: "to", attrs: ["jid": "222:1@lid"], content: .nodes([mine]))
			]))
		]))

		#expect(WhatsAppClient.offerEncNode(in: offer, ownDevices: ["222:1@lid"]) == mine)
	}

	@Test("never falls back to the key of another device")
	func neverUsesAnotherDevicesKey() {
		let other = BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([1])))
		let mine = BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([2])))
		let offer = BinaryNode(tag: "offer", content: .nodes([
			BinaryNode(tag: "destination", content: .nodes([
				BinaryNode(tag: "to", attrs: ["jid": "222:0@lid"], content: .nodes([other])),
				BinaryNode(tag: "to", attrs: ["jid": "222:5@lid"], content: .nodes([mine]))
			]))
		]))

		#expect(WhatsAppClient.offerEncNode(in: offer, ownDevices: ["222:5@lid"]) == mine)
		#expect(WhatsAppClient.offerEncNode(in: offer, ownDevices: ["222:9@lid"]) == nil)
	}

	@Test("qualifies our LID with the device of our id")
	func qualifiesOwnLID() {
		#expect(WhatsAppClient.deviceQualifiedLID("123@lid", deviceFrom: "5511:7@s.whatsapp.net") == "123:7@lid")
		#expect(WhatsAppClient.deviceQualifiedLID("123:9@lid", deviceFrom: "5511:7@s.whatsapp.net") == "123:9@lid")
		#expect(WhatsAppClient.deviceQualifiedLID("123@lid", deviceFrom: "5511@s.whatsapp.net") == "123@lid")
	}

	@Test("falls back to a direct enc child")
	func fallsBackToDirectEncChild() {
		let enc = BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([3])))
		let offer = BinaryNode(tag: "offer", content: .nodes([enc]))

		#expect(WhatsAppClient.offerEncNode(in: offer, ownDevices: ["999@lid"]) == enc)
		#expect(WhatsAppClient.offerEncNode(in: BinaryNode(tag: "offer"), ownDevices: ["999@lid"]) == nil)
	}

	@Test("keys receive audio to the device that answered")
	func keysToAnsweringDevice() {
		#expect(WhatsAppClient.answeringParticipantID(peer: "123@lid", sender: "123:7@lid") == "123:7@lid")
		#expect(WhatsAppClient.answeringParticipantID(peer: "123@lid", sender: "5511:3@s.whatsapp.net") == "123:3@lid")
		#expect(WhatsAppClient.answeringParticipantID(peer: "123@lid", sender: "5511@s.whatsapp.net") == "123:0@lid")
	}

	@Test("compares devices by user and device number")
	func comparesDevices() {
		#expect(WhatsAppClient.isSameDevice("1:2@lid", "1:2@lid"))
		#expect(WhatsAppClient.isSameDevice("1@lid", "1:0@lid"))
		#expect(!WhatsAppClient.isSameDevice("1:2@lid", "1:3@lid"))
	}

	@Test("reads devices from an ack without entering the relay block")
	func readsAckDevices() {
		let ack = BinaryNode(tag: "ack", content: .nodes([
			BinaryNode(tag: "relay", content: .nodes([BinaryNode(tag: "device", attrs: ["jid": "no@lid"])])),
			BinaryNode(tag: "devices", content: .nodes([
				BinaryNode(tag: "device", attrs: ["jid": "1:2@lid"]),
				BinaryNode(tag: "device", attrs: ["jid": "1:2@lid"]),
				BinaryNode(tag: "device", attrs: ["jid": "1:3@lid"])
			]))
		]))

		#expect(WhatsAppClient.ackDevices(in: ack) == ["1:2@lid", "1:3@lid"])
	}

	@Test("extracts the user part of a device jid")
	func extractsUserPart() {
		#expect(WhatsAppClient.userPart(of: "5511:3@s.whatsapp.net") == "5511")
		#expect(WhatsAppClient.userPart(of: "123@lid") == "123")
	}
}
