public enum MessageRealityClassifier {
	public static func isRealMessage(_ message: ReceivedMessage) -> Bool {
		isRealContent(message.content) || message.stub.map(isRealStub) == true
	}

	private static func isRealStub(_ stub: ReceivedMessageStubContent) -> Bool {
		stub.type == .callMissedGroupVideo ||
			stub.type == .callMissedGroupVoice ||
			stub.type == .callMissedVideo ||
			stub.type == .callMissedVoice ||
			stub.type == .groupParticipantAdd
	}

	private static func isRealContent(_ content: ReceivedMessageContent) -> Bool {
		switch content {
		case .reaction, .encryptedReaction, .pollUpdate, .messageRevoked, .messageEdited, .ephemeralSetting, .phoneNumberShared,
			 .limitSharing, .appStateSyncKeyShare, .appStateSyncKeyRequest, .lidMigrationMappingSync,
			 .groupMemberLabelChange, .historySyncNotification, .peerDataOperationRequestResponse, .stub:
			false
		default:
			true
		}
	}
}
