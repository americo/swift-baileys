import Foundation

extension WhatsAppClient {
	public func configureLinkPreviewResolver(_ resolver: (any LinkPreviewResolving)?) {
		linkPreviewResolver = resolver
	}

	public func sendTextMessage(
		to destinationJID: String,
		content: OutgoingTextContent,
		viewOnce: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		var resolvedContent = content
		if content.linkPreview == nil,
		   let url = MessageURLExtractor.extractURL(from: content.text),
		   let linkPreviewResolver {
			do {
				if let linkPreview = try await linkPreviewResolver.linkPreview(for: url) {
					resolvedContent = OutgoingTextContent(
						text: content.text,
						mentions: content.mentions,
						mentionAll: content.mentionAll,
						isForwarded: content.isForwarded,
						forwardingScore: content.forwardingScore,
						quoted: content.quoted,
						linkPreview: linkPreview,
						backgroundARGB: content.backgroundARGB,
						font: content.font,
						ephemeralExpiration: content.ephemeralExpiration
					)
				}
			} catch {}
		}

		return try await sendResolvedMessage(
			to: destinationJID,
			message: wrapViewOnce(MessageContentBuilder.text(
				resolvedContent,
				quotedRemoteJID: resolvedContent.quoted?.chatJID == destinationJID ? nil : resolvedContent.quoted?.chatJID
			), enabled: viewOnce),
			messageID: messageID
		)
	}

	public func sendTextMessage(
		to destinationJID: String,
		text: String,
		mentions: [String] = [],
		mentionAll: Bool = false,
		isForwarded: Bool = false,
		forwardingScore: UInt32? = nil,
		quoted: OutgoingQuotedTextContent? = nil,
		linkPreview: OutgoingLinkPreviewContent? = nil,
		backgroundARGB: UInt32? = nil,
		font: OutgoingTextFont? = nil,
		ephemeralExpiration: UInt32? = nil,
		viewOnce: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		try await sendTextMessage(
			to: destinationJID,
			content: OutgoingTextContent(
				text: text,
				mentions: mentions,
				mentionAll: mentionAll,
				isForwarded: isForwarded,
				forwardingScore: forwardingScore,
				quoted: quoted,
				linkPreview: linkPreview,
				backgroundARGB: backgroundARGB,
				font: font,
				ephemeralExpiration: ephemeralExpiration
			),
			viewOnce: viewOnce,
			messageID: messageID
		)
	}

	func sendDirectTextMessage(
		to destinationJID: String,
		text: String,
		recipientDeviceJIDs: [String],
		mentions: [String] = [],
		mentionAll: Bool = false,
		isForwarded: Bool = false,
		forwardingScore: UInt32? = nil,
		quoted: OutgoingQuotedTextContent? = nil,
		linkPreview: OutgoingLinkPreviewContent? = nil,
		backgroundARGB: UInt32? = nil,
		font: OutgoingTextFont? = nil,
		ephemeralExpiration: UInt32? = nil,
		viewOnce: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		var content = OutgoingTextContent(
			text: text,
			mentions: mentions,
			mentionAll: mentionAll,
			isForwarded: isForwarded,
			forwardingScore: forwardingScore,
			quoted: quoted,
			linkPreview: linkPreview,
			backgroundARGB: backgroundARGB,
			font: font,
			ephemeralExpiration: ephemeralExpiration
		)
		if linkPreview == nil,
		   let url = MessageURLExtractor.extractURL(from: text),
		   let linkPreviewResolver {
			do {
				if let resolvedLinkPreview = try await linkPreviewResolver.linkPreview(for: url) {
					content = OutgoingTextContent(
						text: text,
						mentions: mentions,
						mentionAll: mentionAll,
						isForwarded: isForwarded,
						forwardingScore: forwardingScore,
						quoted: quoted,
						linkPreview: resolvedLinkPreview,
						backgroundARGB: backgroundARGB,
						font: font,
						ephemeralExpiration: ephemeralExpiration
					)
				}
			} catch {}
		}

		return try await sendDirectMessage(
			to: destinationJID,
			message: wrapViewOnce(MessageContentBuilder.text(
				content,
				quotedRemoteJID: quoted?.chatJID == destinationJID ? nil : quoted?.chatJID
			), enabled: viewOnce),
			recipientDeviceJIDs: recipientDeviceJIDs,
			messageID: messageID
		)
	}
}
