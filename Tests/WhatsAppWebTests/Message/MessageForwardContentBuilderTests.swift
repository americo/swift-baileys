import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Message forward content builder")
struct MessageForwardContentBuilderTests {
	@Test("forwards received conversation text as extended text with forwarding context")
	func forwardsReceivedConversationTextAsExtendedTextWithForwardingContext() throws {
		var source = Proto_Message()
		source.conversation = "forward me"

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasExtendedTextMessage)
		#expect(message.extendedTextMessage.text == "forward me")
		#expect(message.extendedTextMessage.contextInfo.isForwarded)
		#expect(message.extendedTextMessage.contextInfo.forwardingScore == 1)
		let actualHex = try message.serializedData().map { String(format: "%02x", $0) }.joined()
		#expect(actualHex == "32150a0a666f7277617264206d658a0106a80101b00101")
	}

	@Test("forwards own text without force using zero forwarding score")
	func forwardsOwnTextWithoutForceUsingZeroForwardingScore() throws {
		let source = MessageContentBuilder.text("own message")

		let message = try MessageContentBuilder.forward(source, fromMe: true)

		#expect(message.extendedTextMessage.text == "own message")
		#expect(message.extendedTextMessage.hasContextInfo)
		#expect(message.extendedTextMessage.contextInfo.isForwarded == false)
		#expect(message.extendedTextMessage.contextInfo.forwardingScore == 0)
	}

	@Test("force forwards own text by incrementing forwarding score")
	func forceForwardsOwnTextByIncrementingForwardingScore() throws {
		let source = MessageContentBuilder.text("force me")

		let message = try MessageContentBuilder.forward(source, fromMe: true, forceForward: true)

		#expect(message.extendedTextMessage.text == "force me")
		#expect(message.extendedTextMessage.contextInfo.isForwarded)
		#expect(message.extendedTextMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards audio messages by preserving media metadata")
	func forwardsAudioMessagesByPreservingMediaMetadata() throws {
		var audio = Proto_Message.AudioMessage()
		audio.url = "https://mmg.whatsapp.net/audio.enc"
		audio.directPath = "/audio.enc"
		audio.mediaKey = Data([0x01])
		audio.fileEncSha256 = Data([0x02])
		audio.fileSha256 = Data([0x03])
		audio.fileLength = 44
		audio.mediaKeyTimestamp = 1_700_000_100
		audio.mimetype = "audio/ogg"
		audio.ptt = true
		audio.seconds = 7
		audio.waveform = Data([0x04, 0x05])
		var source = Proto_Message()
		source.audioMessage = audio

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.audioMessage.url == "https://mmg.whatsapp.net/audio.enc")
		#expect(message.audioMessage.directPath == "/audio.enc")
		#expect(message.audioMessage.mediaKey == Data([0x01]))
		#expect(message.audioMessage.fileEncSha256 == Data([0x02]))
		#expect(message.audioMessage.fileSha256 == Data([0x03]))
		#expect(message.audioMessage.fileLength == 44)
		#expect(message.audioMessage.mediaKeyTimestamp == 1_700_000_100)
		#expect(message.audioMessage.mimetype == "audio/ogg")
		#expect(message.audioMessage.ptt)
		#expect(message.audioMessage.seconds == 7)
		#expect(message.audioMessage.waveform == Data([0x04, 0x05]))
		#expect(message.audioMessage.contextInfo.isForwarded)
		#expect(message.audioMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards sticker messages by preserving sticker flags")
	func forwardsStickerMessagesByPreservingStickerFlags() throws {
		var sticker = Proto_Message.StickerMessage()
		sticker.url = "https://mmg.whatsapp.net/sticker.enc"
		sticker.directPath = "/sticker.enc"
		sticker.mediaKey = Data([0x01])
		sticker.fileEncSha256 = Data([0x02])
		sticker.fileSha256 = Data([0x03])
		sticker.fileLength = 88
		sticker.mediaKeyTimestamp = 1_700_000_200
		sticker.mimetype = "image/webp"
		sticker.width = 512
		sticker.height = 512
		sticker.isAnimated = true
		sticker.isAvatar = true
		sticker.isAiSticker = true
		sticker.isLottie = true
		sticker.pngThumbnail = Data([0x04])
		var source = Proto_Message()
		source.stickerMessage = sticker

		let message = try MessageContentBuilder.forward(source, fromMe: false)

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

	@Test("forwards contacts arrays by applying context to the array envelope")
	func forwardsContactsArraysByApplyingContextToTheArrayEnvelope() throws {
		var first = Proto_Message.ContactMessage()
		first.displayName = "Jane Swift"
		first.vcard = "BEGIN:VCARD\nFN:Jane Swift\nEND:VCARD"
		var second = Proto_Message.ContactMessage()
		second.displayName = "John Swift"
		second.vcard = "BEGIN:VCARD\nFN:John Swift\nEND:VCARD"
		var contacts = Proto_Message.ContactsArrayMessage()
		contacts.displayName = "Swift Contacts"
		contacts.contacts = [first, second]
		var source = Proto_Message()
		source.contactsArrayMessage = contacts

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.contactsArrayMessage.displayName == "Swift Contacts")
		#expect(message.contactsArrayMessage.contacts.map { $0.displayName } == ["Jane Swift", "John Swift"])
		#expect(message.contactsArrayMessage.contacts.map { $0.vcard } == [first.vcard, second.vcard])
		#expect(message.contactsArrayMessage.contextInfo.isForwarded)
		#expect(message.contactsArrayMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards live location messages by preserving movement metadata")
	func forwardsLiveLocationMessagesByPreservingMovementMetadata() throws {
		var liveLocation = Proto_Message.LiveLocationMessage()
		liveLocation.degreesLatitude = -25.965331
		liveLocation.degreesLongitude = 32.589245
		liveLocation.accuracyInMeters = 8
		liveLocation.speedInMps = 4.5
		liveLocation.degreesClockwiseFromMagneticNorth = 91
		liveLocation.caption = "on my way"
		liveLocation.sequenceNumber = 42
		liveLocation.timeOffset = 120
		liveLocation.jpegThumbnail = Data([0x0c, 0x0d])
		var source = Proto_Message()
		source.liveLocationMessage = liveLocation

		let message = try MessageContentBuilder.forward(source, fromMe: false)

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

	@Test("forwards group invite messages by preserving invite type")
	func forwardsGroupInviteMessagesByPreservingInviteType() throws {
		var invite = Proto_Message.GroupInviteMessage()
		invite.groupJid = "120363000000000000@g.us"
		invite.inviteCode = "ABCD1234"
		invite.inviteExpiration = 1_700_010_000
		invite.groupName = "Swift Group"
		invite.caption = "Join us"
		invite.groupType = .parent
		invite.jpegThumbnail = Data([0x01, 0x02])
		var source = Proto_Message()
		source.groupInviteMessage = invite

		let message = try MessageContentBuilder.forward(source, fromMe: false)

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

	@Test("forwards event messages by preserving embedded location")
	func forwardsEventMessagesByPreservingEmbeddedLocation() throws {
		var location = Proto_Message.LocationMessage()
		location.degreesLatitude = -25.966213
		location.degreesLongitude = 32.56745
		location.name = "Maputo Central"
		location.address = "Av. 25 de Setembro"
		location.url = "https://maps.example/event"
		location.accuracyInMeters = 8
		location.comment = "front entrance"
		location.jpegThumbnail = Data([0x03, 0x04])
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
		var source = Proto_Message()
		source.eventMessage = event

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.eventMessage.name == "Swift Baileys meetup")
		#expect(message.eventMessage.description_p == "Protocol parity session")
		#expect(message.eventMessage.startTime == 1_700_100_000)
		#expect(message.eventMessage.endTime == 1_700_103_600)
		#expect(message.eventMessage.joinLink == "https://call.whatsapp.com/video/example")
		#expect(message.eventMessage.isCanceled == false)
		#expect(message.eventMessage.extraGuestsAllowed)
		#expect(message.eventMessage.isScheduleCall)
		#expect(message.eventMessage.location.name == "Maputo Central")
		#expect(message.eventMessage.location.comment == "front entrance")
		#expect(message.eventMessage.location.jpegThumbnail == Data([0x03, 0x04]))
		#expect(message.eventMessage.contextInfo.isForwarded)
		#expect(message.eventMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards request phone number messages by applying context")
	func forwardsRequestPhoneNumberMessagesByApplyingContext() throws {
		var source = Proto_Message()
		source.requestPhoneNumberMessage = Proto_Message.RequestPhoneNumberMessage()

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasRequestPhoneNumberMessage)
		#expect(message.requestPhoneNumberMessage.contextInfo.isForwarded)
		#expect(message.requestPhoneNumberMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards shared phone number protocol messages")
	func forwardsSharedPhoneNumberProtocolMessages() throws {
		let source = MessageContentBuilder.sharePhoneNumber()

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasProtocolMessage)
		#expect(message.protocolMessage.type == .sharePhoneNumber)
	}

	@Test("forwards poll creation messages by preserving options")
	func forwardsPollCreationMessagesByPreservingOptions() throws {
		var first = Proto_Message.PollCreationMessage.Option()
		first.optionName = "Swift"
		first.optionHash = "hash-swift"
		var second = Proto_Message.PollCreationMessage.Option()
		second.optionName = "TypeScript"
		second.optionHash = "hash-typescript"
		var poll = Proto_Message.PollCreationMessage()
		poll.name = "Best Baileys port?"
		poll.options = [first, second]
		poll.selectableOptionsCount = 1
		poll.encKey = Data([0x01, 0x02, 0x03])
		poll.pollContentType = .text
		poll.pollType = .quiz
		poll.correctAnswer = first
		var source = Proto_Message()
		source.pollCreationMessageV3 = poll

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasPollCreationMessageV3)
		#expect(message.pollCreationMessageV3.name == "Best Baileys port?")
		#expect(message.pollCreationMessageV3.options.map { $0.optionName } == ["Swift", "TypeScript"])
		#expect(message.pollCreationMessageV3.options.map { $0.optionHash } == ["hash-swift", "hash-typescript"])
		#expect(message.pollCreationMessageV3.encKey == Data([0x01, 0x02, 0x03]))
		#expect(message.pollCreationMessageV3.correctAnswer.optionName == "Swift")
		#expect(message.pollCreationMessageV3.contextInfo.isForwarded)
		#expect(message.pollCreationMessageV3.contextInfo.forwardingScore == 1)
	}

	@Test("forwards newsletter invite messages by preserving metadata")
	func forwardsNewsletterInviteMessagesByPreservingMetadata() throws {
		var adminInvite = Proto_Message.NewsletterAdminInviteMessage()
		adminInvite.newsletterJid = "120363000000000000@newsletter"
		adminInvite.newsletterName = "Swift Updates"
		adminInvite.caption = "Join as an admin"
		adminInvite.inviteExpiration = 1_700_555_666
		adminInvite.jpegThumbnail = Data([0x01, 0x02, 0x03])
		var adminSource = Proto_Message()
		adminSource.newsletterAdminInviteMessage = adminInvite

		let adminMessage = try MessageContentBuilder.forward(adminSource, fromMe: false)

		#expect(adminMessage.newsletterAdminInviteMessage.newsletterJid == "120363000000000000@newsletter")
		#expect(adminMessage.newsletterAdminInviteMessage.newsletterName == "Swift Updates")
		#expect(adminMessage.newsletterAdminInviteMessage.caption == "Join as an admin")
		#expect(adminMessage.newsletterAdminInviteMessage.inviteExpiration == 1_700_555_666)
		#expect(adminMessage.newsletterAdminInviteMessage.jpegThumbnail == Data([0x01, 0x02, 0x03]))
		#expect(adminMessage.newsletterAdminInviteMessage.contextInfo.isForwarded)
		#expect(adminMessage.newsletterAdminInviteMessage.contextInfo.forwardingScore == 1)

		var followerInvite = Proto_Message.NewsletterFollowerInviteMessage()
		followerInvite.newsletterJid = "120363000000000001@newsletter"
		followerInvite.newsletterName = "Swift Releases"
		followerInvite.caption = "Follow this channel"
		followerInvite.jpegThumbnail = Data([0x04, 0x05, 0x06])
		var followerSource = Proto_Message()
		followerSource.newsletterFollowerInviteMessageV2 = followerInvite

		let followerMessage = try MessageContentBuilder.forward(followerSource, fromMe: false)

		#expect(followerMessage.newsletterFollowerInviteMessageV2.newsletterJid == "120363000000000001@newsletter")
		#expect(followerMessage.newsletterFollowerInviteMessageV2.newsletterName == "Swift Releases")
		#expect(followerMessage.newsletterFollowerInviteMessageV2.caption == "Follow this channel")
		#expect(followerMessage.newsletterFollowerInviteMessageV2.jpegThumbnail == Data([0x04, 0x05, 0x06]))
		#expect(followerMessage.newsletterFollowerInviteMessageV2.contextInfo.isForwarded)
		#expect(followerMessage.newsletterFollowerInviteMessageV2.contextInfo.forwardingScore == 1)
	}

	@Test("forwards order messages by preserving commerce metadata")
	func forwardsOrderMessagesByPreservingCommerceMetadata() throws {
		var requestKey = Proto_MessageKey()
		requestKey.remoteJid = "258840000000@s.whatsapp.net"
		requestKey.fromMe = true
		requestKey.id = "ORDER_REQUEST"
		var order = Proto_Message.OrderMessage()
		order.orderID = "ORDER-123"
		order.thumbnail = Data([0x07, 0x08, 0x09])
		order.itemCount = 3
		order.status = .accepted
		order.surface = .catalog
		order.message = "Please confirm"
		order.orderTitle = "Running shoes"
		order.sellerJid = "258840000100@s.whatsapp.net"
		order.token = "order-token"
		order.totalAmount1000 = 15_990_000
		order.totalCurrencyCode = "MZN"
		order.messageVersion = 2
		order.orderRequestMessageID = requestKey
		order.catalogType = "retail"
		var source = Proto_Message()
		source.orderMessage = order

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.orderMessage.orderID == "ORDER-123")
		#expect(message.orderMessage.thumbnail == Data([0x07, 0x08, 0x09]))
		#expect(message.orderMessage.itemCount == 3)
		#expect(message.orderMessage.status == .accepted)
		#expect(message.orderMessage.surface == .catalog)
		#expect(message.orderMessage.message == "Please confirm")
		#expect(message.orderMessage.orderTitle == "Running shoes")
		#expect(message.orderMessage.sellerJid == "258840000100@s.whatsapp.net")
		#expect(message.orderMessage.token == "order-token")
		#expect(message.orderMessage.totalAmount1000 == 15_990_000)
		#expect(message.orderMessage.totalCurrencyCode == "MZN")
		#expect(message.orderMessage.messageVersion == 2)
		#expect(message.orderMessage.orderRequestMessageID.id == "ORDER_REQUEST")
		#expect(message.orderMessage.catalogType == "retail")
		#expect(message.orderMessage.contextInfo.isForwarded)
		#expect(message.orderMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards product messages by preserving commerce snapshots")
	func forwardsProductMessagesByPreservingCommerceSnapshots() throws {
		var image = Proto_Message.ImageMessage()
		image.url = "https://mmg.whatsapp.net/product.enc"
		image.directPath = "/product.enc"
		image.mediaKey = Data([0x01])
		image.fileEncSha256 = Data([0x02])
		image.fileSha256 = Data([0x03])
		image.fileLength = 512
		image.mediaKeyTimestamp = 1_700_000_000
		image.mimetype = "image/jpeg"
		image.jpegThumbnail = Data([0x04])
		var snapshot = Proto_Message.ProductMessage.ProductSnapshot()
		snapshot.productImage = image
		snapshot.productID = "PROD-123"
		snapshot.title = "Swift Baileys mug"
		snapshot.priceAmount1000 = 349_000
		snapshot.currencyCode = "MZN"
		var catalog = Proto_Message.ProductMessage.CatalogSnapshot()
		catalog.catalogImage = image
		catalog.title = "Swift Store"
		var product = Proto_Message.ProductMessage()
		product.product = snapshot
		product.businessOwnerJid = "258840000100@s.whatsapp.net"
		product.catalog = catalog
		product.body = "Product details"
		product.footer = "Catalog footer"
		var source = Proto_Message()
		source.productMessage = product

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.productMessage.product.productID == "PROD-123")
		#expect(message.productMessage.product.title == "Swift Baileys mug")
		#expect(message.productMessage.product.priceAmount1000 == 349_000)
		#expect(message.productMessage.product.productImage.directPath == "/product.enc")
		#expect(message.productMessage.businessOwnerJid == "258840000100@s.whatsapp.net")
		#expect(message.productMessage.catalog.title == "Swift Store")
		#expect(message.productMessage.catalog.catalogImage.fileSha256 == Data([0x03]))
		#expect(message.productMessage.body == "Product details")
		#expect(message.productMessage.footer == "Catalog footer")
		#expect(message.productMessage.contextInfo.isForwarded)
		#expect(message.productMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards album messages by preserving declared counts")
	func forwardsAlbumMessagesByPreservingDeclaredCounts() throws {
		var album = Proto_Message.AlbumMessage()
		album.expectedImageCount = 3
		album.expectedVideoCount = 2
		var source = Proto_Message()
		source.albumMessage = album

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasAlbumMessage)
		#expect(message.albumMessage.expectedImageCount == 3)
		#expect(message.albumMessage.expectedVideoCount == 2)
		#expect(message.albumMessage.contextInfo.isForwarded)
		#expect(message.albumMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards list messages by preserving sections")
	func forwardsListMessagesByPreservingSections() throws {
		var row = Proto_Message.ListMessage.Row()
		row.title = "Delivery"
		row.description_p = "Send it to my address"
		row.rowID = "delivery"
		var section = Proto_Message.ListMessage.Section()
		section.title = "Fulfillment"
		section.rows = [row]
		var list = Proto_Message.ListMessage()
		list.title = "Choose an option"
		list.description_p = "How should we handle this order?"
		list.buttonText = "Options"
		list.listType = .singleSelect
		list.sections = [section]
		list.footerText = "Reply with one option"
		var source = Proto_Message()
		source.listMessage = list

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasListMessage)
		#expect(message.listMessage.title == "Choose an option")
		#expect(message.listMessage.description_p == "How should we handle this order?")
		#expect(message.listMessage.buttonText == "Options")
		#expect(message.listMessage.listType == .singleSelect)
		#expect(message.listMessage.sections[0].rows[0].rowID == "delivery")
		#expect(message.listMessage.footerText == "Reply with one option")
		#expect(message.listMessage.contextInfo.isForwarded)
		#expect(message.listMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards interactive response messages by preserving selected values")
	func forwardsInteractiveResponseMessagesByPreservingSelectedValues() throws {
		var buttons = Proto_Message.ButtonsResponseMessage()
		buttons.selectedButtonID = "confirm"
		buttons.selectedDisplayText = "Confirm"
		buttons.type = .displayText
		var buttonsSource = Proto_Message()
		buttonsSource.buttonsResponseMessage = buttons

		let buttonsMessage = try MessageContentBuilder.forward(buttonsSource, fromMe: false)

		#expect(buttonsMessage.buttonsResponseMessage.selectedButtonID == "confirm")
		#expect(buttonsMessage.buttonsResponseMessage.selectedDisplayText == "Confirm")
		#expect(buttonsMessage.buttonsResponseMessage.contextInfo.isForwarded)

		var reply = Proto_Message.ListResponseMessage.SingleSelectReply()
		reply.selectedRowID = "delivery"
		var list = Proto_Message.ListResponseMessage()
		list.title = "Delivery"
		list.listType = .singleSelect
		list.singleSelectReply = reply
		var listSource = Proto_Message()
		listSource.listResponseMessage = list

		let listMessage = try MessageContentBuilder.forward(listSource, fromMe: false)

		#expect(listMessage.listResponseMessage.singleSelectReply.selectedRowID == "delivery")
		#expect(listMessage.listResponseMessage.contextInfo.forwardingScore == 1)

		var nativeFlow = Proto_Message.InteractiveResponseMessage.NativeFlowResponseMessage()
		nativeFlow.name = "single_select"
		nativeFlow.paramsJson = #"{"selected":"delivery"}"#
		var interactive = Proto_Message.InteractiveResponseMessage()
		interactive.nativeFlowResponseMessage = nativeFlow
		var interactiveSource = Proto_Message()
		interactiveSource.interactiveResponseMessage = interactive

		let interactiveMessage = try MessageContentBuilder.forward(interactiveSource, fromMe: false)

		#expect(interactiveMessage.interactiveResponseMessage.nativeFlowResponseMessage.name == "single_select")
		#expect(interactiveMessage.interactiveResponseMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards interactive messages by preserving native-flow metadata")
	func forwardsInteractiveMessagesByPreservingNativeFlowMetadata() throws {
		var button = Proto_Message.InteractiveMessage.NativeFlowMessage.NativeFlowButton()
		button.name = "single_select"
		button.buttonParamsJson = #"{"screen":"delivery"}"#
		var nativeFlow = Proto_Message.InteractiveMessage.NativeFlowMessage()
		nativeFlow.buttons = [button]
		nativeFlow.messageParamsJson = #"{"flow":"checkout"}"#
		nativeFlow.messageVersion = 3
		var interactive = Proto_Message.InteractiveMessage()
		interactive.nativeFlowMessage = nativeFlow
		var source = Proto_Message()
		source.interactiveMessage = interactive

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.interactiveMessage.nativeFlowMessage.buttons.map { $0.name } == ["single_select"])
		#expect(message.interactiveMessage.nativeFlowMessage.messageParamsJson == #"{"flow":"checkout"}"#)
		#expect(message.interactiveMessage.contextInfo.isForwarded)
		#expect(message.interactiveMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards scheduled call messages by preserving call metadata")
	func forwardsScheduledCallMessagesByPreservingCallMetadata() throws {
		var creation = Proto_Message.ScheduledCallCreationMessage()
		creation.scheduledTimestampMs = 1_700_200_000_000
		creation.callType = .video
		creation.title = "Weekly sync"
		var creationSource = Proto_Message()
		creationSource.scheduledCallCreationMessage = creation

		let creationMessage = try MessageContentBuilder.forward(creationSource, fromMe: false)

		#expect(creationMessage.scheduledCallCreationMessage.scheduledTimestampMs == 1_700_200_000_000)
		#expect(creationMessage.scheduledCallCreationMessage.callType == .video)
		#expect(creationMessage.scheduledCallCreationMessage.title == "Weekly sync")

		var key = Proto_MessageKey()
		key.remoteJid = "120363000000000000@g.us"
		key.id = "SCHEDULED_CALL_MESSAGE_ID"
		var edit = Proto_Message.ScheduledCallEditMessage()
		edit.key = key
		edit.editType = .cancel
		var editSource = Proto_Message()
		editSource.scheduledCallEditMessage = edit

		let editMessage = try MessageContentBuilder.forward(editSource, fromMe: false)

		#expect(editMessage.scheduledCallEditMessage.key.id == "SCHEDULED_CALL_MESSAGE_ID")
		#expect(editMessage.scheduledCallEditMessage.editType == .cancel)
	}
}
