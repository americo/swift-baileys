import Foundation

public struct EventResponseAggregation: Equatable, Sendable {
	public let response: ReceivedEventResponseType
	public let responders: [String]

	public init(response: ReceivedEventResponseType, responders: [String]) {
		self.response = response
		self.responders = responders
	}
}

public enum EventResponseAggregator {
	public static func aggregateResponses(
		_ updates: [ReceivedMessageEventResponseUpdate],
		meID: String = "me"
	) -> [EventResponseAggregation] {
		var going: [String] = []
		var notGoing: [String] = []
		var maybe: [String] = []

		for update in updates {
			guard let response = update.response?.response else {
				continue
			}

			let responder = MessageKeyAuthor.author(for: update.eventResponseMessageKey, meID: meID)

			switch response {
			case .going:
				going.append(responder)
			case .notGoing:
				notGoing.append(responder)
			case .maybe:
				maybe.append(responder)
			case .unknown, .unrecognized:
				continue
			}
		}

		return [
			EventResponseAggregation(response: .going, responders: going),
			EventResponseAggregation(response: .notGoing, responders: notGoing),
			EventResponseAggregation(response: .maybe, responders: maybe)
		]
	}
}
