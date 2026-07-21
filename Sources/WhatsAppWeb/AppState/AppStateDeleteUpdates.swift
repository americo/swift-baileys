public struct MessageDeleteUpdate: Equatable, Sendable {
	public let keys: [WhatsAppMessageKey]

	public init(keys: [WhatsAppMessageKey]) {
		self.keys = keys
	}
}

public struct ChatDeleteUpdate: Equatable, Sendable {
	public let ids: [String]

	public init(ids: [String]) {
		self.ids = ids
	}
}
