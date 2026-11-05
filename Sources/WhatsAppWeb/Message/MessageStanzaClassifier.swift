/// Stanza-level attributes that depend on what a message carries. The server validates them
/// against the payload, so a media message cannot travel as `type="text"`.
enum MessageStanzaClassifier {
	static func stanzaType(for message: Proto_Message) -> String {
		if isReaction(message) { return "reaction" }
		return mediaType(for: message) == nil ? "text" : "media"
	}

	/// Extra attributes for each `enc` node of the message.
	static func encAttributes(for message: Proto_Message) -> [String: String] {
		// A reaction the recipient cannot decrypt is dropped without asking for a retry.
		if isReaction(message) { return ["decrypt-fail": "hide"] }
		return mediaType(for: message).map { ["mediatype": $0] } ?? [:]
	}

	private static func isReaction(_ message: Proto_Message) -> Bool {
		message.hasReactionMessage || message.hasEncReactionMessage
	}

	private static func mediaType(for message: Proto_Message) -> String? {
		if message.hasImageMessage { return "image" }
		if message.hasStickerMessage { return "sticker" }
		if message.hasVideoMessage { return message.videoMessage.gifPlayback ? "gif" : "video" }
		if message.hasAudioMessage { return message.audioMessage.ptt ? "ptt" : "audio" }
		if message.hasDocumentMessage { return "document" }
		if message.hasViewOnceMessage { return mediaType(for: message.viewOnceMessage.message) }
		return nil
	}
}
