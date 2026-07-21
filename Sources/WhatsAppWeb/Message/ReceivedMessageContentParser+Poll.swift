extension ReceivedMessageContentParser {
	static func pollCreationContent(_ poll: Proto_Message.PollCreationMessage) -> ReceivedPollCreationContent {
		let contentType: ReceivedPollContentType = switch poll.pollContentType {
		case .unknown:
			.unknown
		case .text:
			.text
		case .image:
			.image
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
		let pollType: ReceivedPollType = switch poll.pollType {
		case .poll:
			.poll
		case .quiz:
			.quiz
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
		return ReceivedPollCreationContent(
			name: poll.hasName ? poll.name : nil,
			options: poll.options.map {
				ReceivedPollOption(
					name: $0.hasOptionName ? $0.optionName : nil,
					hash: $0.hasOptionHash ? $0.optionHash : nil
				)
			},
			selectableOptionsCount: poll.hasSelectableOptionsCount ? poll.selectableOptionsCount : nil,
			encryptedKey: poll.hasEncKey ? poll.encKey : nil,
			contentType: contentType,
			pollType: pollType,
			correctAnswer: poll.hasCorrectAnswer ? ReceivedPollOption(
				name: poll.correctAnswer.hasOptionName ? poll.correctAnswer.optionName : nil,
				hash: poll.correctAnswer.hasOptionHash ? poll.correctAnswer.optionHash : nil
			) : nil
		)
	}

	static func pollResultSnapshotContent(_ snapshot: Proto_Message.PollResultSnapshotMessage) -> ReceivedPollResultSnapshotContent {
		let pollType: ReceivedPollType = switch snapshot.pollType {
		case .poll:
			.poll
		case .quiz:
			.quiz
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
		return ReceivedPollResultSnapshotContent(
			name: snapshot.hasName ? snapshot.name : nil,
			votes: snapshot.pollVotes.map {
				ReceivedPollResultVote(
					optionName: $0.hasOptionName ? $0.optionName : nil,
					voteCount: $0.hasOptionVoteCount ? $0.optionVoteCount : nil
				)
			},
			pollType: pollType
		)
	}
}
