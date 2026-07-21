import Testing
@testable import WhatsAppWeb

@Suite("Event response aggregation")
struct EventResponseAggregationTests {
	@Test("aggregates event responders with Baileys-compatible buckets")
	func aggregatesEventRespondersWithBaileysCompatibleBuckets() {
		let updates = [
			update(response: .going, remoteJID: "111@s.whatsapp.net"),
			update(response: .going, remoteJID: "777@s.whatsapp.net", remoteJIDAlt: "777@lid"),
			update(response: .notGoing, remoteJID: "group@g.us", participant: "222@s.whatsapp.net"),
			update(response: .notGoing, remoteJID: "group@g.us", participant: "888@s.whatsapp.net", participantAlt: "888@lid"),
			update(response: .maybe, remoteJID: "333@s.whatsapp.net", fromMe: true),
			update(response: .unknown, remoteJID: "444@s.whatsapp.net"),
			update(response: nil, remoteJID: "555@s.whatsapp.net")
		]

		let result = EventResponseAggregator.aggregateResponses(updates, meID: "999@s.whatsapp.net")

		#expect(result == [
			EventResponseAggregation(response: .going, responders: ["111@s.whatsapp.net", "777@lid"]),
			EventResponseAggregation(response: .notGoing, responders: ["222@s.whatsapp.net", "888@lid"]),
			EventResponseAggregation(response: .maybe, responders: ["999@s.whatsapp.net"])
		])
	}

	private func update(
		response: ReceivedEventResponseType?,
		remoteJID: String,
		participant: String? = nil,
		remoteJIDAlt: String? = nil,
		participantAlt: String? = nil,
		fromMe: Bool = false
	) -> ReceivedMessageEventResponseUpdate {
		ReceivedMessageEventResponseUpdate(
			key: WhatsAppMessageKey(remoteJID: "event@g.us", fromMe: false, id: "event-id"),
			eventResponseMessageKey: WhatsAppMessageKey(
				remoteJID: remoteJID,
				fromMe: fromMe,
				id: "response-id",
				participant: participant,
				remoteJIDAlt: remoteJIDAlt,
				participantAlt: participantAlt
			),
			encryptedPayload: nil,
			encryptedIV: nil,
			response: response.map {
				ReceivedEventResponseContent(response: $0, timestampMilliseconds: 1)
			}
		)
	}
}
