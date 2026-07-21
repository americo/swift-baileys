import Foundation

public enum MediaFileExtensionResolver {
	public static func fileExtension(for content: ReceivedMessageContent) -> String? {
		switch content {
		case .location, .liveLocation, .product:
			return ".jpeg"
		case .image(let image):
			return fileExtension(from: image.mimetype)
		case .document(let document):
			return fileExtension(from: document.mimetype)
		case .audio(let audio):
			return fileExtension(from: audio.mimetype)
		case .video(let video):
			return fileExtension(from: video.mimetype)
		case .sticker(let sticker):
			return fileExtension(from: sticker.mimetype)
		default:
			return nil
		}
	}

	private static func fileExtension(from mimetype: String) -> String? {
		guard let base = mimetype.split(separator: ";", maxSplits: 1).first,
			  let subtype = base.split(separator: "/", maxSplits: 1).last,
			  subtype != base,
			  !subtype.isEmpty else {
			return nil
		}

		return ".\(subtype)"
	}
}
