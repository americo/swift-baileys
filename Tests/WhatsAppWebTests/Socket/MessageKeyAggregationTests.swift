import Testing
@testable import WhatsAppWeb

@Suite("Message key aggregation")
struct MessageKeyAggregationTests {
	@Test("aggregates message keys that are not from me by chat and participant")
	func aggregatesMessageKeysNotFromMeByChatAndParticipant() {
		let result = MessageKeyAggregator.aggregateMessageKeysNotFromMe([
			WhatsAppMessageKey(remoteJID: "chat@s.whatsapp.net", fromMe: false, id: "a"),
			WhatsAppMessageKey(remoteJID: "chat@s.whatsapp.net", fromMe: true, id: "ignored"),
			WhatsAppMessageKey(remoteJID: "group@g.us", fromMe: false, id: "b", participant: "111@s.whatsapp.net"),
			WhatsAppMessageKey(remoteJID: "chat@s.whatsapp.net", fromMe: false, id: "c"),
			WhatsAppMessageKey(remoteJID: "group@g.us", fromMe: false, id: "d", participant: "111@s.whatsapp.net"),
			WhatsAppMessageKey(remoteJID: "group@g.us", fromMe: false, id: "e", participant: "222@s.whatsapp.net"),
			WhatsAppMessageKey(remoteJID: nil, fromMe: false, id: "missing-jid"),
			WhatsAppMessageKey(remoteJID: "chat@s.whatsapp.net", fromMe: false, id: nil)
		])

		#expect(result == [
			MessageKeyAggregation(jid: "chat@s.whatsapp.net", participant: nil, messageIDs: ["a", "c"]),
			MessageKeyAggregation(jid: "group@g.us", participant: "111@s.whatsapp.net", messageIDs: ["b", "d"]),
			MessageKeyAggregation(jid: "group@g.us", participant: "222@s.whatsapp.net", messageIDs: ["e"])
		])
	}
}
