enum ForwardEventResponseMessageMapper {
	static func encryptedEventResponse(from content: ReceivedEncryptedEventResponseContent) -> Proto_Message {
		var response = Proto_Message.EncEventResponseMessage()
		if let eventCreationMessageKey = content.eventCreationMessageKey {
			response.eventCreationMessageKey = ForwardMessageKeyMapper.key(from: eventCreationMessageKey)
		}
		if let encryptedPayload = content.encryptedPayload {
			response.encPayload = encryptedPayload
		}
		if let encryptedIV = content.encryptedIV {
			response.encIv = encryptedIV
		}

		var message = Proto_Message()
		message.encEventResponseMessage = response
		return message
	}
}
