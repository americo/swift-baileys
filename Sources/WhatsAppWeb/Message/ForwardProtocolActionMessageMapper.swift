enum ForwardProtocolActionMessageMapper {
	static func groupMemberLabelChange(from content: ReceivedGroupMemberLabelChangeContent) -> Proto_Message {
		var label = Proto_MemberLabel()
		if let value = content.label {
			label.label = value
		}
		if let timestamp = content.labelTimestamp {
			label.labelTimestamp = timestamp
		}

		var action = Proto_Message.ProtocolMessageMessage()
		action.type = .groupMemberLabelChange
		action.memberLabel = label
		var message = Proto_Message()
		message.protocolMessage = action
		return message
	}

	static func limitSharing(from content: ReceivedLimitSharingContent) -> Proto_Message {
		var limitSharing = Proto_LimitSharing()
		if let sharingLimited = content.sharingLimited {
			limitSharing.sharingLimited = sharingLimited
		}
		if let trigger = content.trigger {
			limitSharing.trigger = switch trigger {
			case .unknown:
				.unknown
			case .chatSetting:
				.chatSetting
			case .bizSupportsFBHosting:
				.bizSupportsFbHosting
			case .unknownGroup:
				.unknownGroup
			case .unrecognized(let value):
				.UNRECOGNIZED(value)
			}
		}
		if let settingTimestampMilliseconds = content.settingTimestampMilliseconds {
			limitSharing.limitSharingSettingTimestamp = settingTimestampMilliseconds
		}
		if let initiatedByMe = content.initiatedByMe {
			limitSharing.initiatedByMe = initiatedByMe
		}

		var action = Proto_Message.ProtocolMessageMessage()
		action.type = .limitSharing
		action.limitSharing = limitSharing
		var message = Proto_Message()
		message.protocolMessage = action
		return message
	}

	static func ephemeralSetting(from content: ReceivedEphemeralSettingContent) -> Proto_Message {
		var action = Proto_Message.ProtocolMessageMessage()
		action.type = .ephemeralSetting
		if let expirationSeconds = content.expirationSeconds {
			action.ephemeralExpiration = expirationSeconds
		}
		if let settingTimestampSeconds = content.settingTimestampSeconds {
			action.ephemeralSettingTimestamp = settingTimestampSeconds
		}
		if let mode = content.disappearingMode {
			var disappearingMode = Proto_DisappearingMode()
			if let initiator = mode.initiator {
				disappearingMode.initiator = switch initiator {
				case .changedInChat:
					.changedInChat
				case .initiatedByMe:
					.initiatedByMe
				case .initiatedByOther:
					.initiatedByOther
				case .businessUpgradeFBHosting:
					.bizUpgradeFbHosting
				case .unrecognized(let value):
					.UNRECOGNIZED(value)
				}
			}
			if let trigger = mode.trigger {
				disappearingMode.trigger = switch trigger {
				case .unknown:
					.unknown
				case .chatSetting:
					.chatSetting
				case .accountSetting:
					.accountSetting
				case .bulkChange:
					.bulkChange
				case .bizSupportsFBHosting:
					.bizSupportsFbHosting
				case .unknownGroups:
					.unknownGroups
				case .unrecognized(let value):
					.UNRECOGNIZED(value)
				}
			}
			if let initiatorDeviceJID = mode.initiatorDeviceJID {
				disappearingMode.initiatorDeviceJid = initiatorDeviceJID
			}
			if let initiatedByMe = mode.initiatedByMe {
				disappearingMode.initiatedByMe = initiatedByMe
			}
			action.disappearingMode = disappearingMode
		}
		var message = Proto_Message()
		message.protocolMessage = action
		return message
	}

	static func revoked(from content: ReceivedMessageRevokedContent) -> Proto_Message {
		var action = Proto_Message.ProtocolMessageMessage()
		action.type = .revoke
		if let key = content.key {
			action.key = ForwardMessageKeyMapper.key(from: key)
		}
		if let timestamp = content.timestampMilliseconds {
			action.timestampMs = timestamp
		}
		var message = Proto_Message()
		message.protocolMessage = action
		return message
	}

	static func edited(from content: ReceivedMessageEditedContent) throws -> Proto_Message {
		var action = Proto_Message.ProtocolMessageMessage()
		action.type = .messageEdit
		if let key = content.key {
			action.key = ForwardMessageKeyMapper.key(from: key)
		}
		if let editedContent = content.content {
			action.editedMessage = try ForwardNestedMessageMapper.message(from: editedContent)
		}
		if let timestamp = content.timestampMilliseconds {
			action.timestampMs = timestamp
		}
		var message = Proto_Message()
		message.protocolMessage = action
		return message
	}
}
