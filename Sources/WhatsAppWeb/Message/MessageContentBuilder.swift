import Foundation

struct UploadedImageContent: Equatable, Sendable {
	let url: String
	let directPath: String
	let mediaKey: Data
	let fileEncSha256: Data
	let fileSha256: Data
	let fileLength: UInt64
	let mediaKeyTimestamp: Int64
	let mimetype: String
	let caption: String?
	let jpegThumbnail: Data?

	init(
		url: String,
		directPath: String,
		mediaKey: Data,
		fileEncSha256: Data,
		fileSha256: Data,
		fileLength: UInt64,
		mediaKeyTimestamp: Int64,
		mimetype: String,
		caption: String? = nil,
		jpegThumbnail: Data? = nil
	) {
		self.url = url
		self.directPath = directPath
		self.mediaKey = mediaKey
		self.fileEncSha256 = fileEncSha256
		self.fileSha256 = fileSha256
		self.fileLength = fileLength
		self.mediaKeyTimestamp = mediaKeyTimestamp
		self.mimetype = mimetype
		self.caption = caption
		self.jpegThumbnail = jpegThumbnail
	}
}

struct UploadedDocumentContent: Equatable, Sendable {
	let url: String
	let directPath: String
	let mediaKey: Data
	let fileEncSha256: Data
	let fileSha256: Data
	let fileLength: UInt64
	let mediaKeyTimestamp: Int64
	let document: OutgoingDocumentContent
}

struct UploadedAudioContent: Equatable, Sendable {
	let url: String
	let directPath: String
	let mediaKey: Data
	let fileEncSha256: Data
	let fileSha256: Data
	let fileLength: UInt64
	let mediaKeyTimestamp: Int64
	let audio: OutgoingAudioContent
}

struct UploadedVideoContent: Equatable, Sendable {
	let url: String
	let directPath: String
	let mediaKey: Data
	let fileEncSha256: Data
	let fileSha256: Data
	let fileLength: UInt64
	let mediaKeyTimestamp: Int64
	let video: OutgoingVideoContent
}

struct UploadedStickerContent: Equatable, Sendable {
	let url: String
	let directPath: String
	let mediaKey: Data
	let fileEncSha256: Data
	let fileSha256: Data
	let fileLength: UInt64
	let mediaKeyTimestamp: Int64
	let sticker: OutgoingStickerContent
}

enum MessageContentBuilder {
	static func text(_ content: OutgoingTextContent, quotedRemoteJID: String? = nil) -> Proto_Message {
		var message = textWithPresentation(content, quotedRemoteJID: quotedRemoteJID)
		if let ephemeralExpiration = content.ephemeralExpiration {
			var extendedText = message.extendedTextMessage
			var contextInfo = extendedText.contextInfo
			contextInfo.expiration = ephemeralExpiration
			extendedText.contextInfo = contextInfo
			message.extendedTextMessage = extendedText
		}

		return message
	}

	static func text(
		_ value: String,
		mentions: [String] = [],
		mentionAll: Bool = false,
		isForwarded: Bool = false,
		forwardingScore: UInt32? = nil,
		quoted: OutgoingQuotedTextContent? = nil,
		quotedRemoteJID: String? = nil,
		ephemeralExpiration: UInt32? = nil
	) -> Proto_Message {
		var extendedText = Proto_Message.ExtendedTextMessage()
		extendedText.text = value
		if !mentions.isEmpty || mentionAll || isForwarded || forwardingScore != nil || quoted != nil || ephemeralExpiration != nil {
			var contextInfo = Proto_ContextInfo()
			contextInfo.mentionedJid = mentions
			if mentionAll {
				contextInfo.nonJidMentions = 1
			}
			if isForwarded {
				contextInfo.isForwarded = true
			}
			if let forwardingScore {
				contextInfo.forwardingScore = forwardingScore
			}
			if let ephemeralExpiration {
				contextInfo.expiration = ephemeralExpiration
			}
			if let quoted {
				contextInfo.stanzaID = quoted.messageID
				contextInfo.participant = quoted.participantJID
				contextInfo.quotedMessage = MessageContentBuilder.text(quoted.text)
				if let quotedRemoteJID {
					contextInfo.remoteJid = quotedRemoteJID
				}
			}

			extendedText.contextInfo = contextInfo
		}

		var message = Proto_Message()
		message.extendedTextMessage = extendedText
		return message
	}

	static func viewOnce(_ content: Proto_Message) -> Proto_Message {
		var futureProof = Proto_Message.FutureProofMessage()
		futureProof.message = content

		var message = Proto_Message()
		message.viewOnceMessage = futureProof
		return message
	}

	static func uploadedImage(_ content: UploadedImageContent) -> Proto_Message {
		var image = Proto_Message.ImageMessage()
		image.url = content.url
		image.directPath = content.directPath
		image.mediaKey = content.mediaKey
		image.fileEncSha256 = content.fileEncSha256
		image.fileSha256 = content.fileSha256
		image.fileLength = content.fileLength
		image.mediaKeyTimestamp = content.mediaKeyTimestamp
		image.mimetype = content.mimetype
		if let caption = content.caption {
			image.caption = caption
		}

		if let jpegThumbnail = content.jpegThumbnail {
			image.jpegThumbnail = jpegThumbnail
		}

		var message = Proto_Message()
		message.imageMessage = image
		return message
	}

	static func album(_ content: OutgoingAlbumContent) -> Proto_Message {
		var album = Proto_Message.AlbumMessage()
		if let expectedImageCount = content.expectedImageCount {
			album.expectedImageCount = expectedImageCount
		}

		if let expectedVideoCount = content.expectedVideoCount {
			album.expectedVideoCount = expectedVideoCount
		}

		var message = Proto_Message()
		message.albumMessage = album
		return message
	}

	static func withAlbumParent(_ content: Proto_Message, parent: WhatsAppMessageKey) -> Proto_Message {
		var message = content
		var context = message.messageContextInfo
		var parentKey = Proto_MessageKey()
		if let remoteJID = parent.remoteJID {
			parentKey.remoteJid = remoteJID
		}

		parentKey.fromMe = parent.fromMe
		if let id = parent.id {
			parentKey.id = id
		}

		if let participant = parent.participant {
			parentKey.participant = participant
		}

		var association = Proto_MessageAssociation()
		association.associationType = .mediaAlbum
		association.parentMessageKey = parentKey
		context.messageAssociation = association
		message.messageContextInfo = context
		return message
	}

	static func uploadedDocument(_ content: UploadedDocumentContent) -> Proto_Message {
		var document = Proto_Message.DocumentMessage()
		document.url = content.url
		document.directPath = content.directPath
		document.mediaKey = content.mediaKey
		document.fileEncSha256 = content.fileEncSha256
		document.fileSha256 = content.fileSha256
		document.fileLength = content.fileLength
		document.mediaKeyTimestamp = content.mediaKeyTimestamp
		document.mimetype = content.document.mimetype
		if let fileName = content.document.fileName {
			document.fileName = fileName
		}

		if let title = content.document.title {
			document.title = title
		}

		if let pageCount = content.document.pageCount {
			document.pageCount = pageCount
		}

		if let caption = content.document.caption {
			document.caption = caption
		}

		if let jpegThumbnail = content.document.jpegThumbnail {
			document.jpegThumbnail = jpegThumbnail
		}

		var message = Proto_Message()
		message.documentMessage = document
		return message
	}

	static func uploadedAudio(_ content: UploadedAudioContent) -> Proto_Message {
		var audio = Proto_Message.AudioMessage()
		audio.url = content.url
		audio.directPath = content.directPath
		audio.mediaKey = content.mediaKey
		audio.fileEncSha256 = content.fileEncSha256
		audio.fileSha256 = content.fileSha256
		audio.fileLength = content.fileLength
		audio.mediaKeyTimestamp = content.mediaKeyTimestamp
		audio.mimetype = content.audio.mimetype
		audio.ptt = content.audio.isVoiceMessage
		if let seconds = content.audio.seconds {
			audio.seconds = seconds
		}

		if let waveform = content.audio.waveform {
			audio.waveform = waveform
		}

		var message = Proto_Message()
		message.audioMessage = audio
		return message
	}

	static func uploadedVideo(_ content: UploadedVideoContent) -> Proto_Message {
		var video = Proto_Message.VideoMessage()
		video.url = content.url
		video.directPath = content.directPath
		video.mediaKey = content.mediaKey
		video.fileEncSha256 = content.fileEncSha256
		video.fileSha256 = content.fileSha256
		video.fileLength = content.fileLength
		video.mediaKeyTimestamp = content.mediaKeyTimestamp
		video.mimetype = content.video.mimetype
		video.gifPlayback = content.video.isGIFPlayback
		if let caption = content.video.caption {
			video.caption = caption
		}

		if let seconds = content.video.seconds {
			video.seconds = seconds
		}

		if let width = content.video.width {
			video.width = width
		}

		if let height = content.video.height {
			video.height = height
		}

		if let jpegThumbnail = content.video.jpegThumbnail {
			video.jpegThumbnail = jpegThumbnail
		}

		var message = Proto_Message()
		message.videoMessage = video
		return message
	}

	static func uploadedSticker(_ content: UploadedStickerContent) -> Proto_Message {
		var sticker = Proto_Message.StickerMessage()
		sticker.url = content.url
		sticker.directPath = content.directPath
		sticker.mediaKey = content.mediaKey
		sticker.fileEncSha256 = content.fileEncSha256
		sticker.fileSha256 = content.fileSha256
		sticker.fileLength = content.fileLength
		sticker.mediaKeyTimestamp = content.mediaKeyTimestamp
		sticker.mimetype = content.sticker.mimetype
		sticker.isAnimated = content.sticker.isAnimated
		if let width = content.sticker.width {
			sticker.width = width
		}

		if let height = content.sticker.height {
			sticker.height = height
		}

		if let pngThumbnail = content.sticker.pngThumbnail {
			sticker.pngThumbnail = pngThumbnail
		}

		var message = Proto_Message()
		message.stickerMessage = sticker
		return message
	}

	static func reaction(
		_ text: String,
		to target: MessageReactionTarget,
		timestampMilliseconds: Int64
	) -> Proto_Message {
		var key = Proto_MessageKey()
		key.remoteJid = target.chatJID
		key.id = target.messageID
		key.fromMe = target.fromMe
		if let participantJID = target.participantJID {
			key.participant = participantJID
		}

		var reaction = Proto_Message.ReactionMessage()
		reaction.key = key
		reaction.text = text
		reaction.senderTimestampMs = timestampMilliseconds

		var message = Proto_Message()
		message.reactionMessage = reaction
		return message
	}

	static func location(_ content: OutgoingLocationContent) -> Proto_Message {
		var message = Proto_Message()
		message.locationMessage = locationMessage(content)
		return message
	}

	static func requestPhoneNumber() -> Proto_Message {
		var message = Proto_Message()
		message.requestPhoneNumberMessage = Proto_Message.RequestPhoneNumberMessage()
		return message
	}

	static func event(_ content: OutgoingEventContent) -> Proto_Message {
		var event = Proto_Message.EventMessage()
		event.name = content.name
		event.startTime = content.startTime
		if let description = content.description {
			event.description_p = description
		}

		if let endTime = content.endTime {
			event.endTime = endTime
		}

		if let joinLink = content.joinLink {
			event.joinLink = joinLink
		}

		if let location = content.location {
			event.location = locationMessage(location)
		}

		if let isCanceled = content.isCanceled {
			event.isCanceled = isCanceled
		}

		if let extraGuestsAllowed = content.extraGuestsAllowed {
			event.extraGuestsAllowed = extraGuestsAllowed
		}

		if let isScheduledCall = content.isScheduledCall {
			event.isScheduleCall = isScheduledCall
		}

		var message = Proto_Message()
		if let messageSecret = content.messageSecret {
			var context = Proto_MessageContextInfo()
			context.messageSecret = messageSecret
			message.messageContextInfo = context
		}

		message.eventMessage = event
		return message
	}

	static func encryptedEventResponse(
		target: EventCreationMessageTarget,
		encrypted: EncryptedEventResponseContent
	) -> Proto_Message {
		var key = Proto_MessageKey()
		key.remoteJid = target.chatJID
		key.id = target.messageID
		key.fromMe = target.fromMe
		if let participantJID = target.participantJID {
			key.participant = participantJID
		}

		var response = Proto_Message.EncEventResponseMessage()
		response.eventCreationMessageKey = key
		response.encPayload = encrypted.encPayload
		response.encIv = encrypted.encIv

		var message = Proto_Message()
		message.encEventResponseMessage = response
		return message
	}

	private static func locationMessage(_ content: OutgoingLocationContent) -> Proto_Message.LocationMessage {
		var location = Proto_Message.LocationMessage()
		location.degreesLatitude = content.latitude
		location.degreesLongitude = content.longitude
		if let name = content.name {
			location.name = name
		}

		if let address = content.address {
			location.address = address
		}

		if let url = content.url {
			location.url = url
		}

		if let jpegThumbnail = content.jpegThumbnail {
			location.jpegThumbnail = jpegThumbnail
		}

		return location
	}

	static func liveLocation(_ content: OutgoingLiveLocationContent) -> Proto_Message {
		var liveLocation = Proto_Message.LiveLocationMessage()
		liveLocation.degreesLatitude = content.latitude
		liveLocation.degreesLongitude = content.longitude
		if let accuracyInMeters = content.accuracyInMeters {
			liveLocation.accuracyInMeters = accuracyInMeters
		}

		if let speedInMetersPerSecond = content.speedInMetersPerSecond {
			liveLocation.speedInMps = speedInMetersPerSecond
		}

		if let degreesClockwiseFromMagneticNorth = content.degreesClockwiseFromMagneticNorth {
			liveLocation.degreesClockwiseFromMagneticNorth = degreesClockwiseFromMagneticNorth
		}

		if let caption = content.caption {
			liveLocation.caption = caption
		}

		if let sequenceNumber = content.sequenceNumber {
			liveLocation.sequenceNumber = sequenceNumber
		}

		if let timeOffsetSeconds = content.timeOffsetSeconds {
			liveLocation.timeOffset = timeOffsetSeconds
		}

		if let jpegThumbnail = content.jpegThumbnail {
			liveLocation.jpegThumbnail = jpegThumbnail
		}

		var message = Proto_Message()
		message.liveLocationMessage = liveLocation
		return message
	}

	static func contact(_ content: OutgoingContactContent) -> Proto_Message {
		var contact = Proto_Message.ContactMessage()
		contact.displayName = content.displayName
		contact.vcard = content.vcard

		var message = Proto_Message()
		message.contactMessage = contact
		return message
	}

	static func contacts(displayName: String, contacts: [OutgoingContactContent]) -> Proto_Message {
		var contactsArray = Proto_Message.ContactsArrayMessage()
		contactsArray.displayName = displayName
		contactsArray.contacts = contacts.map {
			var contact = Proto_Message.ContactMessage()
			contact.displayName = $0.displayName
			contact.vcard = $0.vcard
			return contact
		}

		var message = Proto_Message()
		message.contactsArrayMessage = contactsArray
		return message
	}

	static func poll(_ content: OutgoingPollContent) throws -> Proto_Message {
		try content.validate()

		var poll = Proto_Message.PollCreationMessage()
		poll.name = content.name
		poll.options = content.options.map {
			var option = Proto_Message.PollCreationMessage.Option()
			option.optionName = $0
			return option
		}
		poll.selectableOptionsCount = content.selectableOptionsCount
		poll.pollContentType = .text
		poll.pollType = .poll
		if let encryptedKey = content.encryptedKey {
			poll.encKey = encryptedKey
		}

		var message = Proto_Message()
		if let messageSecret = content.messageSecret {
			var context = Proto_MessageContextInfo()
			context.messageSecret = messageSecret
			message.messageContextInfo = context
		}

		if content.isAnnouncementGroup {
			message.pollCreationMessageV2 = poll
		} else if content.selectableOptionsCount == 1 {
			message.pollCreationMessageV3 = poll
		} else {
			message.pollCreationMessage = poll
		}
		return message
	}

	static func groupInvite(_ content: OutgoingGroupInviteContent) -> Proto_Message {
		var invite = Proto_Message.GroupInviteMessage()
		invite.groupJid = content.groupJID
		invite.inviteCode = content.inviteCode
		invite.inviteExpiration = content.inviteExpiration
		invite.groupName = content.groupName
		if let caption = content.caption {
			invite.caption = caption
		}

		if let jpegThumbnail = content.jpegThumbnail {
			invite.jpegThumbnail = jpegThumbnail
		}

		var message = Proto_Message()
		message.groupInviteMessage = invite
		return message
	}

}
