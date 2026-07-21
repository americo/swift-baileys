import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message media download request")
struct ReceivedMessageMediaDownloadRequestTests {
	@Test("uses direct path when image URL is absent")
	func usesDirectPathWhenImageURLIsAbsent() throws {
		var image = Proto_Message.ImageMessage()
		image.directPath = "/v/t62.7118-24/direct-image.enc?ccb=11-4&oh=01"
		image.mediaKey = try hexData("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		image.fileEncSha256 = try hexData("00f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d03")
		image.fileSha256 = try hexData("fe07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")
		var message = Proto_Message()
		message.imageMessage = image

		let content = try #require(ReceivedMessageContentParser.parse(message))
		let request = try #require(try content.mediaDownloadRequest())

		#expect(request.url.absoluteString == "https://mmg.whatsapp.net/v/t62.7118-24/direct-image.enc?ccb=11-4&oh=01")
		#expect(request.mediaType == .image)
	}

	@Test("preserves image URL host when resolving direct path")
	func preservesImageURLHostWhenResolvingDirectPath() throws {
		var image = Proto_Message.ImageMessage()
		image.url = "https://media-custom.whatsapp.net/old-image.enc"
		image.directPath = "/v/t62.7118-24/direct-image.enc?ccb=11-4&oh=01"
		image.mediaKey = try hexData("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		image.fileEncSha256 = try hexData("00f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d03")
		image.fileSha256 = try hexData("fe07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")
		var message = Proto_Message()
		message.imageMessage = image

		let content = try #require(ReceivedMessageContentParser.parse(message))
		let request = try #require(try content.mediaDownloadRequest())

		#expect(request.url.absoluteString == "https://media-custom.whatsapp.net/v/t62.7118-24/direct-image.enc?ccb=11-4&oh=01")
	}

	@Test("uses direct path resolver for history sync notifications")
	func usesDirectPathResolverForHistorySyncNotifications() throws {
		var notification = Proto_Message.HistorySyncNotification()
		notification.directPath = "/v/t62.7118-24/history.enc"
		notification.mediaKey = try hexData("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		notification.fileEncSha256 = try hexData("00f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d03")
		notification.fileSha256 = try hexData("fe07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")
		var message = Proto_Message()
		message.protocolMessage.historySyncNotification = notification
		message.protocolMessage.type = .historySyncNotification

		let content = try #require(ReceivedMessageContentParser.parse(message))
		let request = try #require(try content.mediaDownloadRequest())

		#expect(request.url.absoluteString == "https://mmg.whatsapp.net/v/t62.7118-24/history.enc")
		#expect(request.mediaType == .mdMessageHistory)
	}
}
