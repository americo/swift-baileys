enum ForwardBusinessCallMessageMapper {
	static func message(from content: ReceivedBusinessCallContent) -> Proto_Message {
		var businessCallMessage = Proto_Message.BCallMessage()
		if let sessionID = content.sessionID {
			businessCallMessage.sessionID = sessionID
		}
		if let mediaType = content.mediaType {
			businessCallMessage.mediaType = switch mediaType {
			case .unknown:
				.unknown
			case .audio:
				.audio
			case .video:
				.video
			case .unrecognized(let value):
				.UNRECOGNIZED(value)
			}
		}
		if let masterKey = content.masterKey {
			businessCallMessage.masterKey = masterKey
		}
		if let caption = content.caption {
			businessCallMessage.caption = caption
		}

		var message = Proto_Message()
		message.bcallMessage = businessCallMessage
		return message
	}
}

enum ForwardOrderMessageMapper {
	static func message(from content: ReceivedOrderContent) -> Proto_Message {
		var orderMessage = Proto_Message.OrderMessage()
		if let orderID = content.orderID {
			orderMessage.orderID = orderID
		}
		if let thumbnail = content.thumbnail {
			orderMessage.thumbnail = thumbnail
		}
		if let itemCount = content.itemCount {
			orderMessage.itemCount = itemCount
		}
		if let status = content.status {
			orderMessage.status = switch status {
			case .unknown:
				.unknown
			case .inquiry:
				.inquiry
			case .accepted:
				.accepted
			case .declined:
				.declined
			case .unrecognized(let value):
				.UNRECOGNIZED(value)
			}
		}
		if let surface = content.surface {
			orderMessage.surface = switch surface {
			case .unknown:
				.unknown
			case .catalog:
				.catalog
			case .unrecognized(let value):
				.UNRECOGNIZED(value)
			}
		}
		if let message = content.message {
			orderMessage.message = message
		}
		if let orderTitle = content.orderTitle {
			orderMessage.orderTitle = orderTitle
		}
		if let sellerJID = content.sellerJID {
			orderMessage.sellerJid = sellerJID
		}
		if let token = content.token {
			orderMessage.token = token
		}
		if let totalAmount1000 = content.totalAmount1000 {
			orderMessage.totalAmount1000 = totalAmount1000
		}
		if let totalCurrencyCode = content.totalCurrencyCode {
			orderMessage.totalCurrencyCode = totalCurrencyCode
		}
		if let messageVersion = content.messageVersion {
			orderMessage.messageVersion = messageVersion
		}
		if let orderRequestMessageID = content.orderRequestMessageID {
			orderMessage.orderRequestMessageID = ForwardMessageKeyMapper.key(from: orderRequestMessageID)
		}
		if let catalogType = content.catalogType {
			orderMessage.catalogType = catalogType
		}

		var message = Proto_Message()
		message.orderMessage = orderMessage
		return message
	}
}

enum ForwardAlbumMessageMapper {
	static func message(from content: ReceivedAlbumContent) -> Proto_Message {
		var albumMessage = Proto_Message.AlbumMessage()
		if let expectedImageCount = content.expectedImageCount {
			albumMessage.expectedImageCount = expectedImageCount
		}
		if let expectedVideoCount = content.expectedVideoCount {
			albumMessage.expectedVideoCount = expectedVideoCount
		}

		var message = Proto_Message()
		message.albumMessage = albumMessage
		return message
	}
}
