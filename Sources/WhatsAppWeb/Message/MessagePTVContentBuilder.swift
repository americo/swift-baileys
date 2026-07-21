extension MessageContentBuilder {
	static func uploadedPTV(_ content: UploadedVideoContent) -> Proto_Message {
		var message = uploadedVideo(content)
		message.ptvMessage = message.videoMessage
		message.clearVideoMessage()
		return message
	}
}
