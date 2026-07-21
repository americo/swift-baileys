import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Message content builder")
struct MessageContentBuilderTests {
	@Test("builds text content matching Baileys WAProto encoding")
	func buildsTextContentMatchingBaileysWAProtoEncoding() throws {
		let message = MessageContentBuilder.text("hello from swift")

		#expect(message.hasExtendedTextMessage)
		#expect(message.extendedTextMessage.text == "hello from swift")
		#expect(try message.serializedData() == Data(hexString: "32120a1068656c6c6f2066726f6d207377696674"))
	}

	@Test("builds styled text content matching Baileys WAProto encoding")
	func buildsStyledTextContentMatchingBaileysWAProtoEncoding() throws {
		let content = OutgoingTextContent(
			text: "styled text",
			backgroundARGB: 0xff112233,
			font: .fbScript
		)

		let message = MessageContentBuilder.text(content)

		#expect(message.hasExtendedTextMessage)
		#expect(message.extendedTextMessage.text == "styled text")
		#expect(message.extendedTextMessage.backgroundArgb == 0xff112233)
		#expect(message.extendedTextMessage.font == .fbScript)
		#expect(try message.serializedData() == Data(hexString: "32140a0b7374796c6564207465787445332211ff4802"))
	}

	@Test("builds text link preview content matching Baileys WAProto encoding")
	func buildsTextLinkPreviewContentMatchingBaileysWAProtoEncoding() throws {
		let content = OutgoingTextContent(
			text: "Read https://example.com now",
			linkPreview: OutgoingLinkPreviewContent(
				matchedText: "https://example.com",
				title: "Example title",
				description: "Example description",
				jpegThumbnail: Data([0x01, 0x02, 0x03]),
				thumbnail: OutgoingLinkPreviewThumbnailContent(
					directPath: "/v/t62.7118-24/link",
					mediaKey: Data([0x04, 0x05, 0x06]),
					mediaKeyTimestamp: 1_717_000_000,
					width: 640,
					height: 360,
					fileSha256: Data([0x07, 0x08, 0x09]),
					fileEncSha256: Data([0x0a, 0x0b, 0x0c])
				)
			)
		)

		let message = MessageContentBuilder.textWithLinkPreview(content)

		#expect(message.hasExtendedTextMessage)
		#expect(message.extendedTextMessage.text == "Read https://example.com now")
		#expect(message.extendedTextMessage.matchedText == "https://example.com")
		#expect(message.extendedTextMessage.title == "Example title")
		#expect(message.extendedTextMessage.description_p == "Example description")
		#expect(message.extendedTextMessage.previewType == .none)
		#expect(message.extendedTextMessage.jpegThumbnail == Data([0x01, 0x02, 0x03]))
		#expect(message.extendedTextMessage.thumbnailDirectPath == "/v/t62.7118-24/link")
		#expect(message.extendedTextMessage.mediaKey == Data([0x04, 0x05, 0x06]))
		#expect(message.extendedTextMessage.mediaKeyTimestamp == 1_717_000_000)
		#expect(message.extendedTextMessage.thumbnailWidth == 640)
		#expect(message.extendedTextMessage.thumbnailHeight == 360)
		#expect(message.extendedTextMessage.thumbnailSha256 == Data([0x07, 0x08, 0x09]))
		#expect(message.extendedTextMessage.thumbnailEncSha256 == Data([0x0a, 0x0b, 0x0c]))
		#expect(try message.serializedData() == Data(hexString: "3296010a1c526561642068747470733a2f2f6578616d706c652e636f6d206e6f77121368747470733a2f2f6578616d706c652e636f6d2a134578616d706c65206465736372697074696f6e320d4578616d706c65207469746c6550008201030102039a01132f762f7436322e373131382d32342f6c696e6ba20103070809aa01030a0b0cb20103040506b801c0aeddb206c001e802c8018005"))
	}

	@Test("builds uploaded image content matching Baileys WAProto encoding")
	func buildsUploadedImageContentMatchingBaileysWAProtoEncoding() throws {
		let image = UploadedImageContent(
			url: "https://mmg.whatsapp.net/o1/v/t62.7118-24/example",
			directPath: "/v/t62.7118-24/example.enc?ccb=11-4&oh=01",
			mediaKey: try Data(hexString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"),
			fileEncSha256: try Data(hexString: "00f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d03"),
			fileSha256: try Data(hexString: "fe07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce"),
			fileLength: 27,
			mediaKeyTimestamp: 1_700_000_000,
			mimetype: "image/jpeg",
			caption: "swift image"
		)

		let message = MessageContentBuilder.uploadedImage(image)

		#expect(message.hasImageMessage)
		#expect(message.imageMessage.url == image.url)
		#expect(message.imageMessage.directPath == image.directPath)
		#expect(message.imageMessage.mediaKey == image.mediaKey)
		#expect(message.imageMessage.fileEncSha256 == image.fileEncSha256)
		#expect(message.imageMessage.fileSha256 == image.fileSha256)
		#expect(message.imageMessage.fileLength == image.fileLength)
		#expect(message.imageMessage.mediaKeyTimestamp == image.mediaKeyTimestamp)
		#expect(message.imageMessage.mimetype == image.mimetype)
		#expect(message.imageMessage.caption == image.caption)
		#expect(try message.serializedData() == Data(hexString: "1ae5010a3168747470733a2f2f6d6d672e77686174736170702e6e65742f6f312f762f7436322e373131382d32342f6578616d706c65120a696d6167652f6a7065671a0b737769667420696d6167652220fe07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce281b4220000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f4a2000f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d035a292f762f7436322e373131382d32342f6578616d706c652e656e633f6363623d31312d34266f683d30316080e2cfaa06"))
	}

	@Test("associates media content with an album parent")
	func associatesMediaContentWithAlbumParent() throws {
		let image = UploadedImageContent(
			url: "https://mmg.whatsapp.net/o1/v/t62.7118-24/example",
			directPath: "/v/t62.7118-24/example.enc?ccb=11-4&oh=01",
			mediaKey: try Data(hexString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"),
			fileEncSha256: try Data(hexString: "00f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d03"),
			fileSha256: try Data(hexString: "fe07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce"),
			fileLength: 27,
			mediaKeyTimestamp: 1_700_000_000,
			mimetype: "image/jpeg",
			caption: "swift image"
		)
		let parent = WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: true, id: "3EB0ALBUM")

		let message = MessageContentBuilder.withAlbumParent(
			MessageContentBuilder.uploadedImage(image),
			parent: parent
		)

		#expect(message.imageMessage.caption == "swift image")
		#expect(message.messageContextInfo.messageAssociation.associationType == .mediaAlbum)
		#expect(message.messageContextInfo.messageAssociation.parentMessageKey.remoteJid == "123@s.whatsapp.net")
		#expect(message.messageContextInfo.messageAssociation.parentMessageKey.fromMe)
		#expect(message.messageContextInfo.messageAssociation.parentMessageKey.id == "3EB0ALBUM")
		#expect(try message.serializedData() == Data(hexString: "1ae5010a3168747470733a2f2f6d6d672e77686174736170702e6e65742f6f312f762f7436322e373131382d32342f6578616d706c65120a696d6167652f6a7065671a0b737769667420696d6167652220fe07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce281b4220000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f4a2000f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d035a292f762f7436322e373131382d32342f6578616d706c652e656e633f6363623d31312d34266f683d30316080e2cfaa069a02275225080112210a1231323340732e77686174736170702e6e657410011a0933454230414c42554d"))
	}

	@Test("builds album content matching Baileys WAProto encoding")
	func buildsAlbumContentMatchingBaileysWAProtoEncoding() throws {
		let album = OutgoingAlbumContent(expectedImageCount: 2, expectedVideoCount: 1)

		let message = MessageContentBuilder.album(album)

		#expect(message.hasAlbumMessage)
		#expect(message.albumMessage.expectedImageCount == 2)
		#expect(message.albumMessage.expectedVideoCount == 1)
		#expect(try message.serializedData() == Data(hexString: "9a050410021801"))
	}

	@Test("wraps content as view once")
	func wrapsContentAsViewOnce() {
		let text = MessageContentBuilder.text("single view")

		let message = MessageContentBuilder.viewOnce(text)

		#expect(message.hasViewOnceMessage)
		#expect(message.viewOnceMessage.hasMessage)
		#expect(message.viewOnceMessage.message.extendedTextMessage.text == "single view")
	}

	@Test("builds reaction content for a target message")
	func buildsReactionContentForTargetMessage() throws {
		let target = MessageReactionTarget(
			chatJID: "123@s.whatsapp.net",
			messageID: "3EB0TARGET",
			fromMe: false,
			participantJID: "456@s.whatsapp.net"
		)

		let message = MessageContentBuilder.reaction("+1", to: target, timestampMilliseconds: 1_700_000_999_000)

		#expect(message.hasReactionMessage)
		#expect(message.reactionMessage.text == "+1")
		#expect(message.reactionMessage.senderTimestampMs == 1_700_000_999_000)
		#expect(message.reactionMessage.key.remoteJid == "123@s.whatsapp.net")
		#expect(message.reactionMessage.key.id == "3EB0TARGET")
		#expect(message.reactionMessage.key.fromMe == false)
		#expect(message.reactionMessage.key.participant == "456@s.whatsapp.net")
		let actualHex = try message.serializedData().map { String(format: "%02x", $0) }.joined()
		#expect(actualHex == "f202430a360a1231323340732e77686174736170702e6e657410001a0a33454230544152474554221234353640732e77686174736170702e6e657412022b3120d8ccd2ffbc31")
	}

	@Test("builds location content")
	func buildsLocationContent() throws {
		let content = OutgoingLocationContent(
			latitude: -25.966213,
			longitude: 32.56745,
			name: "Maputo Central",
			address: "Av. 25 de Setembro",
			url: "https://maps.example/maputo"
		)

		let message = MessageContentBuilder.location(content)

		#expect(message.hasLocationMessage)
		#expect(message.locationMessage.degreesLatitude == -25.966213)
		#expect(message.locationMessage.degreesLongitude == 32.56745)
		#expect(message.locationMessage.name == "Maputo Central")
		#expect(message.locationMessage.address == "Av. 25 de Setembro")
		#expect(message.locationMessage.url == "https://maps.example/maputo")
		let actualHex = try message.serializedData().map { String(format: "%02x", $0) }.joined()
		#expect(actualHex == "2a530955f833bc59f739c011bf0e9c33a24840401a0e4d617075746f2043656e7472616c221241762e20323520646520536574656d62726f2a1b68747470733a2f2f6d6170732e6578616d706c652f6d617075746f")
	}

	@Test("builds request phone number content")
	func buildsRequestPhoneNumberContent() throws {
		let message = MessageContentBuilder.requestPhoneNumber()

		#expect(message.hasRequestPhoneNumberMessage)
		#expect(try message.serializedData() == Data(hexString: "b20300"))
	}

	@Test("builds share phone number content")
	func buildsSharePhoneNumberContent() throws {
		let message = MessageContentBuilder.sharePhoneNumber()

		#expect(message.protocolMessage.type == .sharePhoneNumber)
		#expect(try message.serializedData() == Data(hexString: "6202100b"))
	}

	@Test("builds limit sharing content")
	func buildsLimitSharingContent() throws {
		let content = OutgoingLimitSharingContent(
			sharingLimited: true,
			settingTimestampMilliseconds: 1_800_000_123_456
		)

		let message = MessageContentBuilder.limitSharing(content)

		#expect(message.protocolMessage.type == .limitSharing)
		#expect(message.protocolMessage.limitSharing.sharingLimited)
		#expect(message.protocolMessage.limitSharing.trigger == .chatSetting)
		#expect(message.protocolMessage.limitSharing.limitSharingSettingTimestamp == 1_800_000_123_456)
		#expect(message.protocolMessage.limitSharing.initiatedByMe)
		#expect(try message.serializedData() == Data(hexString: "6212101bc2010d0801100118c0e4f8c2b1342001"))
	}

	@Test("builds plain button reply content like Baileys")
	func buildsPlainButtonReplyContent() throws {
		let message = MessageContentBuilder.buttonReply(OutgoingButtonReplyContent(
			style: .plain,
			id: "confirm",
			displayText: "Confirm",
			index: 0
		))

		#expect(try message.serializedData() == Data(hexString: "da02140a07636f6e6669726d1207436f6e6669726d2001"))
	}

	@Test("builds template button reply content like Baileys")
	func buildsTemplateButtonReplyContent() throws {
		let message = MessageContentBuilder.buttonReply(OutgoingButtonReplyContent(
			style: .template,
			id: "ship_now",
			displayText: "Ship now",
			index: 2
		))

		#expect(try message.serializedData() == Data(hexString: "ea01160a08736869705f6e6f77120853686970206e6f772002"))
	}

	@Test("builds list reply content like Baileys")
	func buildsListReplyContent() throws {
		let message = MessageContentBuilder.listReply(OutgoingListReplyContent(
			title: "Delivery",
			selectedRowID: "delivery",
			description: "Send it to my address"
		))

		#expect(try message.serializedData() == Data(hexString: "ba022f0a0844656c697665727910011a0a0a0864656c69766572792a1553656e6420697420746f206d792061646472657373"))
	}

	@Test("builds default disappearing messages setting content like Baileys")
	func buildsDefaultDisappearingMessagesSettingContent() throws {
		let message = MessageContentBuilder.disappearingMessages(OutgoingDisappearingMessagesContent(enabled: true))

		#expect(message.ephemeralMessage.message.protocolMessage.type == .ephemeralSetting)
		#expect(message.ephemeralMessage.message.protocolMessage.ephemeralExpiration == 604_800)
		#expect(try message.serializedData() == Data(hexString: "c2020a0a08620610032080f524"))
	}

	@Test("builds disabled disappearing messages setting content like Baileys")
	func buildsDisabledDisappearingMessagesSettingContent() throws {
		let message = MessageContentBuilder.disappearingMessages(OutgoingDisappearingMessagesContent(enabled: false))

		#expect(message.ephemeralMessage.message.protocolMessage.type == .ephemeralSetting)
		#expect(message.ephemeralMessage.message.protocolMessage.ephemeralExpiration == 0)
		#expect(try message.serializedData() == Data(hexString: "c202080a06620410032000"))
	}

	@Test("prepares disappearing message setting content with nil default like Baileys")
	func preparesDisappearingMessageSettingContentWithNilDefaultLikeBaileys() throws {
		let message = MessageContentBuilder.disappearingMessageSetting()

		#expect(message.ephemeralMessage.message.protocolMessage.type == .ephemeralSetting)
		#expect(message.ephemeralMessage.message.protocolMessage.ephemeralExpiration == 0)
		#expect(try message.serializedData() == Data(hexString: "c202080a06620410032000"))
	}

	@Test("prepares disappearing message setting content with explicit expiration like Baileys")
	func preparesDisappearingMessageSettingContentWithExplicitExpirationLikeBaileys() throws {
		let message = MessageContentBuilder.disappearingMessageSetting(expirationSeconds: 86_400)

		#expect(message.ephemeralMessage.message.protocolMessage.type == .ephemeralSetting)
		#expect(message.ephemeralMessage.message.protocolMessage.ephemeralExpiration == 86_400)
	}

	@Test("builds product content like Baileys")
	func buildsProductContent() throws {
		let image = UploadedImageContent(
			url: "https://mmg.whatsapp.net/product.enc",
			directPath: "/v/t62.7118-24/product",
			mediaKey: Data([0x01, 0x02, 0x03]),
			fileEncSha256: Data([0x04, 0x05, 0x06]),
			fileSha256: Data([0x07, 0x08, 0x09]),
			fileLength: 12_345,
			mediaKeyTimestamp: 1_717_000_000,
			mimetype: "image/jpeg",
			caption: "Product hero",
			jpegThumbnail: Data([0x0a, 0x0b])
		)
		let message = MessageContentBuilder.product(UploadedProductContent(
			image: image,
			product: OutgoingProductContent(
				productID: "product-123",
				title: "Running shoes",
				description: "Lightweight shoes",
				currencyCode: "MZN",
				priceAmount1000: 15_990_000,
				retailerID: "sku-123",
				url: "https://shop.example/products/product-123",
				productImageCount: 3,
				firstImageID: "image-1",
				salePriceAmount1000: 12_990_000,
				signedURL: "https://shop.example/signed/product-123",
				businessOwnerJID: "258840000100@s.whatsapp.net",
				body: "Available now",
				footer: "Tap to view"
			)
		))

		#expect(message.productMessage.product.title == "Running shoes")
		#expect(message.productMessage.product.productImage.url == "https://mmg.whatsapp.net/product.enc")
		#expect(try message.serializedData() == Data(hexString: "f201d9020a9d020a750a2468747470733a2f2f6d6d672e77686174736170702e6e65742f70726f647563742e656e63120a696d6167652f6a7065671a0c50726f64756374206865726f220307080928b96042030102034a030405065a162f762f7436322e373131382d32342f70726f6475637460c0aeddb2068201020a0b120b70726f647563742d3132331a0d52756e6e696e672073686f657322114c696768747765696768742073686f65732a034d5a4e30f0f9cf073a07736b752d313233422968747470733a2f2f73686f702e6578616d706c652f70726f64756374732f70726f647563742d31323348035a07696d6167652d3160b0ec98066a2768747470733a2f2f73686f702e6578616d706c652f7369676e65642f70726f647563742d313233121b32353838343030303031303040732e77686174736170702e6e65742a0d417661696c61626c65206e6f77320b54617020746f2076696577"))
	}

	@Test("builds live location content")
	func buildsLiveLocationContent() {
		let content = OutgoingLiveLocationContent(
			latitude: -25.966213,
			longitude: 32.56745,
			accuracyInMeters: 12,
			speedInMetersPerSecond: 1.5,
			degreesClockwiseFromMagneticNorth: 90,
			caption: "On my way",
			sequenceNumber: 7,
			timeOffsetSeconds: 30,
			jpegThumbnail: Data([0x03, 0x04])
		)

		let message = MessageContentBuilder.liveLocation(content)

		#expect(message.hasLiveLocationMessage)
		#expect(message.liveLocationMessage.degreesLatitude == content.latitude)
		#expect(message.liveLocationMessage.degreesLongitude == content.longitude)
		#expect(message.liveLocationMessage.accuracyInMeters == content.accuracyInMeters)
		#expect(message.liveLocationMessage.speedInMps == content.speedInMetersPerSecond)
		#expect(message.liveLocationMessage.degreesClockwiseFromMagneticNorth == content.degreesClockwiseFromMagneticNorth)
		#expect(message.liveLocationMessage.caption == content.caption)
		#expect(message.liveLocationMessage.sequenceNumber == content.sequenceNumber)
		#expect(message.liveLocationMessage.timeOffset == content.timeOffsetSeconds)
		#expect(message.liveLocationMessage.jpegThumbnail == content.jpegThumbnail)
	}

	@Test("builds contact content")
	func buildsContactContent() throws {
		let content = OutgoingContactContent(
			displayName: "Jane Swift",
			vcard: "BEGIN:VCARD\nVERSION:3.0\nFN:Jane Swift\nTEL;type=CELL;waid=258841234567:+258 84 123 4567\nEND:VCARD"
		)

		let message = MessageContentBuilder.contact(content)

		#expect(message.hasContactMessage)
		#expect(message.contactMessage.displayName == "Jane Swift")
		#expect(message.contactMessage.vcard == content.vcard)
		let actualHex = try message.serializedData().map { String(format: "%02x", $0) }.joined()
		#expect(actualHex == "226f0a0a4a616e65205377696674820160424547494e3a56434152440a56455253494f4e3a332e300a464e3a4a616e652053776966740a54454c3b747970653d43454c4c3b776169643d3235383834313233343536373a2b3235382038342031323320343536370a454e443a5643415244")
	}

	@Test("builds contacts array content")
	func buildsContactsArrayContent() throws {
		let first = OutgoingContactContent(
			displayName: "Jane Swift",
			vcard: "BEGIN:VCARD\nVERSION:3.0\nFN:Jane Swift\nEND:VCARD"
		)
		let second = OutgoingContactContent(
			displayName: "John Swift",
			vcard: "BEGIN:VCARD\nVERSION:3.0\nFN:John Swift\nEND:VCARD"
		)

		let message = MessageContentBuilder.contacts(displayName: "Swift Contacts", contacts: [first, second])

		#expect(message.hasContactsArrayMessage)
		#expect(message.contactsArrayMessage.displayName == "Swift Contacts")
		#expect(message.contactsArrayMessage.contacts.map { $0.displayName } == ["Jane Swift", "John Swift"])
		#expect(message.contactsArrayMessage.contacts.map { $0.vcard } == [first.vcard, second.vcard])
		let actualHex = try message.serializedData().map { String(format: "%02x", $0) }.joined()
		#expect(actualHex == "6a90010a0e537769667420436f6e7461637473123e0a0a4a616e6520537769667482012f424547494e3a56434152440a56455253494f4e3a332e300a464e3a4a616e652053776966740a454e443a5643415244123e0a0a4a6f686e20537769667482012f424547494e3a56434152440a56455253494f4e3a332e300a464e3a4a6f686e2053776966740a454e443a5643415244")
	}

	@Test("builds poll creation content")
	func buildsPollCreationContent() throws {
		let messageSecret = try Data(hexString: "101112131415161718191a1b1c1d1e1f")
		let poll = OutgoingPollContent(
			name: "Best Swift feature?",
			options: ["Actors", "Macros", "AsyncSequence"],
			selectableOptionsCount: 1,
			encryptedKey: try Data(hexString: "000102030405060708090a0b0c0d0e0f"),
			messageSecret: messageSecret
		)

		let message = try MessageContentBuilder.poll(poll)

		#expect(message.hasMessageContextInfo)
		#expect(message.messageContextInfo.messageSecret == messageSecret)
		#expect(message.hasPollCreationMessageV3)
		#expect(message.pollCreationMessageV3.name == "Best Swift feature?")
		#expect(message.pollCreationMessageV3.options.map { $0.optionName } == ["Actors", "Macros", "AsyncSequence"])
		#expect(message.pollCreationMessageV3.selectableOptionsCount == 1)
		#expect(message.pollCreationMessageV3.encKey == poll.encryptedKey)
		let actualHex = try message.serializedData().map { String(format: "%02x", $0) }.joined()
		#expect(actualHex == "9a02121a10101112131415161718191a1b1c1d1e1f8204520a10000102030405060708090a0b0c0d0e0f12134265737420537769667420666561747572653f1a080a064163746f72731a080a064d6163726f731a0f0a0d4173796e6353657175656e6365200130013800")
	}

	@Test("builds announcement group poll creation content")
	func buildsAnnouncementGroupPollCreationContent() throws {
		let poll = OutgoingPollContent(
			name: "Announcement poll",
			options: ["One", "Two"],
			selectableOptionsCount: 2,
			isAnnouncementGroup: true
		)

		let message = try MessageContentBuilder.poll(poll)

		#expect(message.hasPollCreationMessageV2)
		#expect(message.pollCreationMessageV2.name == "Announcement poll")
		#expect(message.pollCreationMessageV2.options.map { $0.optionName } == ["One", "Two"])
		#expect(message.pollCreationMessageV2.selectableOptionsCount == 2)
	}

	@Test("rejects poll creation content with empty required fields")
	func rejectsPollCreationContentWithEmptyRequiredFields() throws {
		#expect(throws: OutgoingPollContentValidationError.emptyName) {
			try MessageContentBuilder.poll(OutgoingPollContent(name: "", options: ["One"], selectableOptionsCount: 1))
		}
		#expect(throws: OutgoingPollContentValidationError.emptyOptions) {
			try MessageContentBuilder.poll(OutgoingPollContent(name: "Empty options", options: [], selectableOptionsCount: 0))
		}
		#expect(throws: OutgoingPollContentValidationError.emptyOption(index: 1)) {
			try MessageContentBuilder.poll(OutgoingPollContent(name: "Empty option", options: ["One", ""], selectableOptionsCount: 1))
		}
	}

	@Test("builds event message content")
	func buildsEventMessageContent() throws {
		let messageSecret = try Data(hexString: "202122232425262728292a2b2c2d2e2f")
		let event = OutgoingEventContent(
			name: "Swift meetup",
			description: "Discuss Baileys porting",
			startTime: 1_800_000_000,
			endTime: 1_800_003_600,
			joinLink: "https://call.whatsapp.com/swift",
			location: OutgoingLocationContent(
				latitude: -25.966,
				longitude: 32.583,
				name: "Maputo",
				address: "Av. Julius Nyerere"
			),
			extraGuestsAllowed: true,
			isScheduledCall: true,
			messageSecret: messageSecret
		)

		let message = MessageContentBuilder.event(event)

		#expect(message.hasMessageContextInfo)
		#expect(message.messageContextInfo.messageSecret == messageSecret)
		#expect(message.hasEventMessage)
		#expect(message.eventMessage.name == event.name)
		#expect(message.eventMessage.description_p == event.description)
		#expect(message.eventMessage.startTime == event.startTime)
		#expect(message.eventMessage.endTime == event.endTime)
		#expect(message.eventMessage.joinLink == event.joinLink)
		#expect(message.eventMessage.location.name == event.location?.name)
		#expect(message.eventMessage.location.address == event.location?.address)
		#expect(message.eventMessage.extraGuestsAllowed)
		#expect(message.eventMessage.isScheduleCall)
		#expect(!message.eventMessage.hasIsCanceled)
	}

	@Test("builds encrypted event response content")
	func buildsEncryptedEventResponseContent() throws {
		let target = EventCreationMessageTarget(
			chatJID: "120363000000000000@g.us",
			messageID: "3EB0EVENTCREATE",
			fromMe: false,
			participantJID: "111@s.whatsapp.net"
		)
		let encrypted = EncryptedEventResponseContent(
			encPayload: try Data(hexString: "e5e06ccecdde6bc10ab15672664cd3251c67a7a96bb87b79ee34ea"),
			encIv: try Data(hexString: "202122232425262728292a2b")
		)

		let message = MessageContentBuilder.encryptedEventResponse(target: target, encrypted: encrypted)

		#expect(message.hasEncEventResponseMessage)
		#expect(message.encEventResponseMessage.eventCreationMessageKey.remoteJid == target.chatJID)
		#expect(message.encEventResponseMessage.eventCreationMessageKey.id == target.messageID)
		#expect(message.encEventResponseMessage.eventCreationMessageKey.fromMe == target.fromMe)
		#expect(message.encEventResponseMessage.eventCreationMessageKey.participant == target.participantJID)
		#expect(message.encEventResponseMessage.encPayload == encrypted.encPayload)
		#expect(message.encEventResponseMessage.encIv == encrypted.encIv)
	}

	@Test("builds group invite content")
	func buildsGroupInviteContent() {
		let invite = OutgoingGroupInviteContent(
			groupJID: "120363000000000000@g.us",
			inviteCode: "ABCD1234",
			inviteExpiration: 1_700_010_000,
			groupName: "Swift Group",
			caption: "Join us",
			jpegThumbnail: Data([0x01, 0x02])
		)

		let message = MessageContentBuilder.groupInvite(invite)

		#expect(message.hasGroupInviteMessage)
		#expect(message.groupInviteMessage.groupJid == invite.groupJID)
		#expect(message.groupInviteMessage.inviteCode == invite.inviteCode)
		#expect(message.groupInviteMessage.inviteExpiration == invite.inviteExpiration)
		#expect(message.groupInviteMessage.groupName == invite.groupName)
		#expect(message.groupInviteMessage.caption == invite.caption)
		#expect(message.groupInviteMessage.jpegThumbnail == invite.jpegThumbnail)
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw MessageContentBuilderTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum MessageContentBuilderTestError: Error {
	case invalidHex
}
