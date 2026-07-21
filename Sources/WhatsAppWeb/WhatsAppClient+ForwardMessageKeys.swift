enum ForwardMessageKeyMapper {
	static func key(from content: ReceivedMessageKey) -> Proto_MessageKey {
		var key = Proto_MessageKey()
		if let remoteJID = content.remoteJID {
			key.remoteJid = remoteJID
		}
		key.fromMe = content.fromMe
		if let id = content.id {
			key.id = id
		}
		if let participant = content.participant {
			key.participant = participant
		}
		return key
	}
}
