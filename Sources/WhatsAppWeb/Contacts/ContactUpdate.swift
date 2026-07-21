import Foundation

public struct ContactUpdate: Equatable, Sendable {
	public let id: String
	public let imageURL: String?
	public let name: String?
	public let username: String?
	public let lid: String?
	public let phoneNumber: String?

	public init(
		id: String,
		imageURL: String? = nil,
		name: String? = nil,
		username: String? = nil,
		lid: String? = nil,
		phoneNumber: String? = nil
	) {
		self.id = id
		self.imageURL = imageURL
		self.name = name
		self.username = username
		self.lid = lid
		self.phoneNumber = phoneNumber
	}
}
