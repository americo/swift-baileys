import Foundation

extension WhatsAppClient {
	func handleNewsletterNotification(_ node: BinaryNode) {
		guard let from = node.attrs["from"], case let .nodes(children) = node.content else {
			return
		}

		let author = node.attrs["participant"] ?? ""
		for child in children {
			switch child.tag {
			case "reaction":
				if let serverID = child.attrs["message_id"] {
					eventContinuation.yield(.newsletterReactionUpdated(NewsletterReactionUpdate(
						id: from,
						serverID: serverID,
						code: child.childString(named: "reaction"),
						count: 1
					)))
				}
			case "view":
				if let serverID = child.attrs["message_id"] {
					eventContinuation.yield(.newsletterViewUpdated(NewsletterViewUpdate(
						id: from,
						serverID: serverID,
						count: child.textContent.flatMap(Int.init) ?? 0
					)))
				}
			case "participant":
				if let user = child.attrs["jid"], let action = child.attrs["action"], let role = child.attrs["role"] {
					eventContinuation.yield(.newsletterParticipantsUpdated(NewsletterParticipantUpdate(
						id: from,
						author: author,
						user: user,
						action: action,
						newRole: role
					)))
				}
			case "update":
				if let settings = child.firstChild(named: "settings") {
					let update = NewsletterSettingsUpdate(
						id: from,
						name: settings.firstChild(named: "name")?.textContent,
						description: settings.firstChild(named: "description")?.textContent
					)
					if update.name != nil || update.description != nil {
						eventContinuation.yield(.newsletterSettingsUpdated(update))
					}
				}
			case "message":
				if let message = newsletterPlaintextMessage(from: child, newsletterJID: from) {
					eventContinuation.yield(.receivedMessage(message))
				}
			default:
				break
			}
		}
	}

	private func newsletterPlaintextMessage(from node: BinaryNode, newsletterJID: String) -> ReceivedMessage? {
		guard let plaintext = node.firstChild(named: "plaintext")?.dataContent,
			  let messageID = node.attrs["message_id"] ?? node.attrs["server_id"],
			  let protoMessage = try? Proto_Message(serializedBytes: plaintext) else {
			return nil
		}

		var key = Proto_MessageKey()
		key.remoteJid = newsletterJID
		key.id = messageID
		key.fromMe = false

		var info = Proto_WebMessageInfo()
		info.key = key
		info.message = protoMessage
		if let timestamp = node.attrs["t"].flatMap(UInt64.init) {
			info.messageTimestamp = timestamp
		}

		return ReceivedWebMessageInfoParser.parse(info)
	}
}

private extension BinaryNode {
	var textContent: String? {
		guard let content else {
			return nil
		}

		switch content {
		case .string(let value):
			return value
		case .data(let data):
			return String(data: data, encoding: .utf8)
		case .nodes:
			return nil
		}
	}

	var dataContent: Data? {
		guard let content else {
			return nil
		}

		switch content {
		case .data(let data):
			return data
		case .string(let string):
			return Data(string.utf8)
		case .nodes:
			return nil
		}
	}
}
