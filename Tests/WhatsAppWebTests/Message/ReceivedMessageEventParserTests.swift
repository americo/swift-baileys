import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message event parser")
struct ReceivedMessageEventParserTests {
	@Test("parses event messages")
	func parsesEventMessages() throws {
		var location = Proto_Message.LocationMessage()
		location.degreesLatitude = -25.966213
		location.degreesLongitude = 32.56745
		location.name = "Maputo Central"
		location.address = "Av. 25 de Setembro"
		var event = Proto_Message.EventMessage()
		event.name = "Swift Baileys meetup"
		event.description_p = "Protocol parity session"
		event.startTime = 1_700_100_000
		event.endTime = 1_700_103_600
		event.joinLink = "https://call.whatsapp.com/video/example"
		event.isCanceled = false
		event.extraGuestsAllowed = true
		event.isScheduleCall = true
		event.location = location
		var message = Proto_Message()
		message.eventMessage = event

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .event(ReceivedEventContent(
			name: "Swift Baileys meetup",
			description: "Protocol parity session",
			startTime: 1_700_100_000,
			endTime: 1_700_103_600,
			joinLink: "https://call.whatsapp.com/video/example",
			isCanceled: false,
			extraGuestsAllowed: true,
			isScheduledCall: true,
			location: ReceivedLocationContent(
				latitude: -25.966213,
				longitude: 32.56745,
				name: "Maputo Central",
				address: "Av. 25 de Setembro",
				url: nil,
				accuracyInMeters: nil,
				comment: nil,
				jpegThumbnail: nil
			)
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}
}
