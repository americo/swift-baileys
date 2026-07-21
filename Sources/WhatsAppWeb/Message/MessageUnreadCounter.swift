public enum MessageUnreadCounter {
	public static func shouldIncrementChatUnread(for message: ReceivedMessage) -> Bool {
		message.fromMe != true && message.stub == nil
	}
}
