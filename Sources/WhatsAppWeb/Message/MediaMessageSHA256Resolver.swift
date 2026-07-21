import Foundation

public enum MediaMessageSHA256Resolver {
	public static func base64FileSHA256(for content: ReceivedMessageContent) -> String? {
		switch content {
		case .image(let image):
			return image.fileSHA256.base64EncodedString()
		case .document(let document):
			return document.fileSHA256.base64EncodedString()
		case .audio(let audio):
			return audio.fileSHA256.base64EncodedString()
		case .video(let video):
			return video.fileSHA256.base64EncodedString()
		case .sticker(let sticker):
			return sticker.fileSHA256.base64EncodedString()
		default:
			return nil
		}
	}
}
