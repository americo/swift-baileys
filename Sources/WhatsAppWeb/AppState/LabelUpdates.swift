public struct LabelUpdate: Equatable, Sendable {
	public let id: String
	public let name: String?
	public let color: Int32?
	public let deleted: Bool?
	public let predefinedID: String?

	public init(id: String, name: String?, color: Int32?, deleted: Bool?, predefinedID: String?) {
		self.id = id
		self.name = name
		self.color = color
		self.deleted = deleted
		self.predefinedID = predefinedID
	}
}

public enum LabelAssociationUpdateType: Equatable, Sendable {
	case add
	case remove
}

public enum LabelAssociation: Equatable, Sendable {
	case chat(chatID: String, labelID: String)
	case message(chatID: String, messageID: String, labelID: String)
}

public struct LabelAssociationUpdate: Equatable, Sendable {
	public let association: LabelAssociation
	public let type: LabelAssociationUpdateType

	public init(association: LabelAssociation, type: LabelAssociationUpdateType) {
		self.association = association
		self.type = type
	}
}
