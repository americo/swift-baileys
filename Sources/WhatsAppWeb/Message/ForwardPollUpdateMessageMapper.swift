enum ForwardPollUpdateMessageMapper {
	static func pollUpdate(from content: ReceivedPollUpdateContent) -> Proto_Message {
		var update = Proto_Message.PollUpdateMessage()
		if let key = content.pollCreationMessageKey {
			update.pollCreationMessageKey = ForwardMessageKeyMapper.key(from: key)
		}
		if content.encryptedPayload != nil || content.encryptedIV != nil {
			var vote = Proto_Message.PollEncValue()
			if let encryptedPayload = content.encryptedPayload {
				vote.encPayload = encryptedPayload
			}
			if let encryptedIV = content.encryptedIV {
				vote.encIv = encryptedIV
			}
			update.vote = vote
		}
		if let senderTimestamp = content.senderTimestampMilliseconds {
			update.senderTimestampMs = senderTimestamp
		}
		var message = Proto_Message()
		message.pollUpdateMessage = update
		return message
	}

	static func pollResultSnapshot(from content: ReceivedPollResultSnapshotContent) -> Proto_Message {
		var snapshot = Proto_Message.PollResultSnapshotMessage()
		if let name = content.name {
			snapshot.name = name
		}
		snapshot.pollVotes = content.votes.map {
			var vote = Proto_Message.PollResultSnapshotMessage.PollVote()
			if let optionName = $0.optionName {
				vote.optionName = optionName
			}
			if let voteCount = $0.voteCount {
				vote.optionVoteCount = voteCount
			}
			return vote
		}
		snapshot.pollType = switch content.pollType {
		case .poll:
			.poll
		case .quiz:
			.quiz
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
		var message = Proto_Message()
		message.pollResultSnapshotMessage = snapshot
		return message
	}
}
