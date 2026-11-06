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

		#expect(WhatsAppClient.offerEncNode(in: offer, localJIDs: ["222"]) == mine)
	}

	@Test("falls back to a direct enc child")
	func fallsBackToDirectEncChild() {
		let enc = BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([3])))
		let offer = BinaryNode(tag: "offer", content: .nodes([enc]))

		#expect(WhatsAppClient.offerEncNode(in: offer, localJIDs: ["999"]) == enc)
		#expect(WhatsAppClient.offerEncNode(in: BinaryNode(tag: "offer"), localJIDs: ["999"]) == nil)
	}

	@Test("extracts the user part of a device jid")
	func extractsUserPart() {
		#expect(WhatsAppClient.userPart(of: "5511:3@s.whatsapp.net") == "5511")
		#expect(WhatsAppClient.userPart(of: "123@lid") == "123")
	}
}
