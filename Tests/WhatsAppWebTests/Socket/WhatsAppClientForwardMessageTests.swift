import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward messages")
struct WhatsAppClientForwardMessageTests {
	@Test("forwards received text messages through the encrypted send path")
	func forwardsReceivedTextMessagesThroughEncryptedSendPath() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x13]))],
			callOrder: callOrder
		)
		let deviceResolver = StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"])
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		let messageID = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "INBOUND1",
				from: "456@s.whatsapp.net",
				timestamp: 1_700_000_000,
				content: .text("forward me"),
				fromMe: false
			),
			messageID: "3EB0FORWARDED"
		)

		#expect(messageID == "3EB0FORWARDED")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await callOrder.values == ["sessions", "encrypt:123.0@s.whatsapp.net"])
		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.extendedTextMessage.text == "forward me")
		#expect(message.extendedTextMessage.contextInfo.isForwarded)
		#expect(message.extendedTextMessage.contextInfo.forwardingScore == 1)
	}

	@Test("rejects unsupported forwarded content with a typed error")
	func rejectsUnsupportedForwardedContentWithTypedError() async throws {
		let callOrder = MessageSendCallOrder()
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: StubMessageSendEncryptor(results: [EncryptedMessage(type: "msg", ciphertext: Data())]),
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		await #expect(throws: WhatsAppClientForwardMessageError.unsupportedContent) {
			try await client.sendForwardedMessage(
				to: "123@s.whatsapp.net",
				message: ReceivedMessage(
					id: "STUB1",
					from: "456@s.whatsapp.net",
					timestamp: nil,
					content: .stub(ReceivedMessageStubContent(type: .groupCreate, parameters: ["Group"])),
					fromMe: false
				)
			)
		}
	}

	@Test("reports whether received content can be forwarded")
	func reportsWhetherReceivedContentCanBeForwarded() {
		#expect(ReceivedMessageContent.text("forward me").isForwardable)
		#expect(ReceivedMessageContent.phoneNumberShared(ReceivedPhoneNumberSharedContent()).isForwardable)
		#expect(ReceivedMessageContent.encryptedEventResponse(ReceivedEncryptedEventResponseContent(
			eventCreationMessageKey: nil,
			encryptedPayload: nil,
			encryptedIV: nil
		)).isForwardable)
		#expect(!ReceivedMessageContent.stub(ReceivedMessageStubContent(type: .groupCreate, parameters: ["Group"])).isForwardable)
	}

	@Test("forwards encrypted event responses through the encrypted send path")
	func forwardsEncryptedEventResponsesThroughEncryptedSendPath() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x14]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "EVENTRESPONSE1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .encryptedEventResponse(ReceivedEncryptedEventResponseContent(
					eventCreationMessageKey: ReceivedMessageKey(
						remoteJID: "group@g.us",
						fromMe: false,
						id: "EVENT1",
						participant: "456@s.whatsapp.net"
					),
					encryptedPayload: Data([0x01, 0x02, 0x03]),
					encryptedIV: Data([0x04, 0x05])
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDEVENTRESPONSE"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.encEventResponseMessage.eventCreationMessageKey.remoteJid == "group@g.us")
		#expect(message.encEventResponseMessage.eventCreationMessageKey.id == "EVENT1")
		#expect(message.encEventResponseMessage.eventCreationMessageKey.participant == "456@s.whatsapp.net")
		#expect(message.encEventResponseMessage.encPayload == Data([0x01, 0x02, 0x03]))
		#expect(message.encEventResponseMessage.encIv == Data([0x04, 0x05]))
	}

	@Test("forwards text link previews through the encrypted send path")
	func forwardsTextLinkPreviewsThroughEncryptedSendPath() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x14]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "LINK1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .textLinkPreview(ReceivedTextLinkPreviewContent(
					text: "Read https://example.com",
					matchedText: "https://example.com",
					title: "Example",
					description: "Preview"
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDLINK"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.extendedTextMessage.text == "Read https://example.com")
		#expect(message.extendedTextMessage.matchedText == "https://example.com")
		#expect(message.extendedTextMessage.title == "Example")
		#expect(message.extendedTextMessage.description_p == "Preview")
		#expect(message.extendedTextMessage.contextInfo.isForwarded)
		#expect(message.extendedTextMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards received image messages through the encrypted send path")
	func forwardsReceivedImageMessagesThroughEncryptedSendPath() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x15]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "IMAGE1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .image(ReceivedImageContent(
					url: "https://mmg.whatsapp.net/o1/v/t62.7118-24/image.enc",
					directPath: "/o1/v/t62.7118-24/image.enc",
					mediaKey: Data([0x01, 0x02, 0x03]),
					fileEncSHA256: Data([0x04, 0x05]),
					fileSHA256: Data([0x06, 0x07]),
					fileLength: 12_345,
					mediaKeyTimestamp: 1_700_000_000,
					mimetype: "image/jpeg",
					caption: "forward this image",
					jpegThumbnail: Data([0x08, 0x09])
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDIMAGE"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.imageMessage.url == "https://mmg.whatsapp.net/o1/v/t62.7118-24/image.enc")
		#expect(message.imageMessage.directPath == "/o1/v/t62.7118-24/image.enc")
		#expect(message.imageMessage.mediaKey == Data([0x01, 0x02, 0x03]))
		#expect(message.imageMessage.fileEncSha256 == Data([0x04, 0x05]))
		#expect(message.imageMessage.fileSha256 == Data([0x06, 0x07]))
		#expect(message.imageMessage.fileLength == 12_345)
		#expect(message.imageMessage.mediaKeyTimestamp == 1_700_000_000)
		#expect(message.imageMessage.mimetype == "image/jpeg")
		#expect(message.imageMessage.caption == "forward this image")
		#expect(message.imageMessage.jpegThumbnail == Data([0x08, 0x09]))
		#expect(message.imageMessage.contextInfo.isForwarded)
		#expect(message.imageMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards received sticker messages while preserving sticker flags")
	func forwardsReceivedStickerMessagesWhilePreservingStickerFlags() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x16]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "STICKER1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .sticker(ReceivedStickerContent(
					url: "https://mmg.whatsapp.net/sticker.enc",
					directPath: "/sticker.enc",
					mediaKey: Data([0x01]),
					fileEncSHA256: Data([0x02]),
					fileSHA256: Data([0x03]),
					fileLength: 88,
					mediaKeyTimestamp: 1_700_000_200,
					mimetype: "image/webp",
					width: 512,
					height: 512,
					isAnimated: true,
					isAvatar: true,
					isAISticker: true,
					isLottie: true,
					pngThumbnail: Data([0x04])
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDSTICKER"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.stickerMessage.url == "https://mmg.whatsapp.net/sticker.enc")
		#expect(message.stickerMessage.directPath == "/sticker.enc")
		#expect(message.stickerMessage.mediaKey == Data([0x01]))
		#expect(message.stickerMessage.fileEncSha256 == Data([0x02]))
		#expect(message.stickerMessage.fileSha256 == Data([0x03]))
		#expect(message.stickerMessage.fileLength == 88)
		#expect(message.stickerMessage.mediaKeyTimestamp == 1_700_000_200)
		#expect(message.stickerMessage.mimetype == "image/webp")
		#expect(message.stickerMessage.width == 512)
		#expect(message.stickerMessage.height == 512)
		#expect(message.stickerMessage.isAnimated)
		#expect(message.stickerMessage.isAvatar)
		#expect(message.stickerMessage.isAiSticker)
		#expect(message.stickerMessage.isLottie)
		#expect(message.stickerMessage.pngThumbnail == Data([0x04]))
		#expect(message.stickerMessage.contextInfo.isForwarded)
		#expect(message.stickerMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards received location messages while preserving optional metadata")
	func forwardsReceivedLocationMessagesWhilePreservingOptionalMetadata() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x17]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "LOCATION1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .location(ReceivedLocationContent(
					latitude: -25.966,
					longitude: 32.583,
					name: "Maputo",
					address: "Av. 24 de Julho",
					url: "https://maps.example/location",
					accuracyInMeters: 12,
					comment: "meet here",
					jpegThumbnail: Data([0x01, 0x02])
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDLOCATION"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.locationMessage.degreesLatitude == -25.966)
		#expect(message.locationMessage.degreesLongitude == 32.583)
		#expect(message.locationMessage.name == "Maputo")
		#expect(message.locationMessage.address == "Av. 24 de Julho")
		#expect(message.locationMessage.url == "https://maps.example/location")
		#expect(message.locationMessage.accuracyInMeters == 12)
		#expect(message.locationMessage.comment == "meet here")
		#expect(message.locationMessage.jpegThumbnail == Data([0x01, 0x02]))
		#expect(message.locationMessage.contextInfo.isForwarded)
		#expect(message.locationMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards received live location messages while preserving movement metadata")
	func forwardsReceivedLiveLocationMessagesWhilePreservingMovementMetadata() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x18]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "LIVELOCATION1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .liveLocation(ReceivedLiveLocationContent(
					latitude: -25.965331,
					longitude: 32.589245,
					accuracyInMeters: 8,
					speedInMetersPerSecond: 4.5,
					degreesClockwiseFromMagneticNorth: 91,
					caption: "on my way",
					sequenceNumber: 42,
					timeOffsetSeconds: 120,
					jpegThumbnail: Data([0x0c, 0x0d])
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDLIVELOCATION"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.liveLocationMessage.degreesLatitude == -25.965331)
		#expect(message.liveLocationMessage.degreesLongitude == 32.589245)
		#expect(message.liveLocationMessage.accuracyInMeters == 8)
		#expect(message.liveLocationMessage.speedInMps == 4.5)
		#expect(message.liveLocationMessage.degreesClockwiseFromMagneticNorth == 91)
		#expect(message.liveLocationMessage.caption == "on my way")
		#expect(message.liveLocationMessage.sequenceNumber == 42)
		#expect(message.liveLocationMessage.timeOffset == 120)
		#expect(message.liveLocationMessage.jpegThumbnail == Data([0x0c, 0x0d]))
		#expect(message.liveLocationMessage.contextInfo.isForwarded)
		#expect(message.liveLocationMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards received group invite messages while preserving invite type")
	func forwardsReceivedGroupInviteMessagesWhilePreservingInviteType() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x19]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "GROUPINVITE1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .groupInvite(ReceivedGroupInviteContent(
					groupJID: "120363000000000000@g.us",
					inviteCode: "ABCD1234",
					inviteExpiration: 1_700_010_000,
					groupName: "Swift Group",
					caption: "Join us",
					groupType: .parent,
					jpegThumbnail: Data([0x01, 0x02])
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDGROUPINVITE"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.groupInviteMessage.groupJid == "120363000000000000@g.us")
		#expect(message.groupInviteMessage.inviteCode == "ABCD1234")
		#expect(message.groupInviteMessage.inviteExpiration == 1_700_010_000)
		#expect(message.groupInviteMessage.groupName == "Swift Group")
		#expect(message.groupInviteMessage.caption == "Join us")
		#expect(message.groupInviteMessage.groupType == .parent)
		#expect(message.groupInviteMessage.jpegThumbnail == Data([0x01, 0x02]))
		#expect(message.groupInviteMessage.contextInfo.isForwarded)
		#expect(message.groupInviteMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards received event messages while preserving embedded location")
	func forwardsReceivedEventMessagesWhilePreservingEmbeddedLocation() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x1a]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "EVENT1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .event(ReceivedEventContent(
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
						url: "https://maps.example/event",
						accuracyInMeters: 8,
						comment: "front entrance",
						jpegThumbnail: Data([0x03, 0x04])
					)
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDEVENT"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.eventMessage.name == "Swift Baileys meetup")
		#expect(message.eventMessage.description_p == "Protocol parity session")
		#expect(message.eventMessage.startTime == 1_700_100_000)
		#expect(message.eventMessage.endTime == 1_700_103_600)
		#expect(message.eventMessage.joinLink == "https://call.whatsapp.com/video/example")
		#expect(message.eventMessage.isCanceled == false)
		#expect(message.eventMessage.extraGuestsAllowed)
		#expect(message.eventMessage.isScheduleCall)
		#expect(message.eventMessage.location.degreesLatitude == -25.966213)
		#expect(message.eventMessage.location.degreesLongitude == 32.56745)
		#expect(message.eventMessage.location.name == "Maputo Central")
		#expect(message.eventMessage.location.address == "Av. 25 de Setembro")
		#expect(message.eventMessage.location.url == "https://maps.example/event")
		#expect(message.eventMessage.location.accuracyInMeters == 8)
		#expect(message.eventMessage.location.comment == "front entrance")
		#expect(message.eventMessage.location.jpegThumbnail == Data([0x03, 0x04]))
		#expect(message.eventMessage.contextInfo.isForwarded)
		#expect(message.eventMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards request phone number messages through the encrypted send path")
	func forwardsRequestPhoneNumberMessagesThroughEncryptedSendPath() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x1b]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "REQUESTPHONE1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .requestPhoneNumber(ReceivedRequestPhoneNumberContent()),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDREQUESTPHONE"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.hasRequestPhoneNumberMessage)
		#expect(message.requestPhoneNumberMessage.contextInfo.isForwarded)
		#expect(message.requestPhoneNumberMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards shared phone number protocol messages through the encrypted send path")
	func forwardsSharedPhoneNumberProtocolMessagesThroughEncryptedSendPath() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x1c]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "SHAREPHONE1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .phoneNumberShared(ReceivedPhoneNumberSharedContent()),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDSHAREPHONE"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.hasProtocolMessage)
		#expect(message.protocolMessage.type == .sharePhoneNumber)
	}

}
