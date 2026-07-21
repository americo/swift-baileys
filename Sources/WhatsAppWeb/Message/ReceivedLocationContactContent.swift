import Foundation

public struct ReceivedLocationContent: Equatable, Sendable {
	public let latitude: Double
	public let longitude: Double
	public let name: String?
	public let address: String?
	public let url: String?
	public let accuracyInMeters: UInt32?
	public let comment: String?
	public let jpegThumbnail: Data?

	public init(
		latitude: Double,
		longitude: Double,
		name: String?,
		address: String?,
		url: String?,
		accuracyInMeters: UInt32?,
		comment: String?,
		jpegThumbnail: Data?
	) {
		self.latitude = latitude
		self.longitude = longitude
		self.name = name
		self.address = address
		self.url = url
		self.accuracyInMeters = accuracyInMeters
		self.comment = comment
		self.jpegThumbnail = jpegThumbnail
	}
}

public struct ReceivedLiveLocationContent: Equatable, Sendable {
	public let latitude: Double
	public let longitude: Double
	public let accuracyInMeters: UInt32?
	public let speedInMetersPerSecond: Float?
	public let degreesClockwiseFromMagneticNorth: UInt32?
	public let caption: String?
	public let sequenceNumber: Int64?
	public let timeOffsetSeconds: UInt32?
	public let jpegThumbnail: Data?

	public init(
		latitude: Double,
		longitude: Double,
		accuracyInMeters: UInt32?,
		speedInMetersPerSecond: Float?,
		degreesClockwiseFromMagneticNorth: UInt32?,
		caption: String?,
		sequenceNumber: Int64?,
		timeOffsetSeconds: UInt32?,
		jpegThumbnail: Data?
	) {
		self.latitude = latitude
		self.longitude = longitude
		self.accuracyInMeters = accuracyInMeters
		self.speedInMetersPerSecond = speedInMetersPerSecond
		self.degreesClockwiseFromMagneticNorth = degreesClockwiseFromMagneticNorth
		self.caption = caption
		self.sequenceNumber = sequenceNumber
		self.timeOffsetSeconds = timeOffsetSeconds
		self.jpegThumbnail = jpegThumbnail
	}
}

public struct ReceivedContactContent: Equatable, Sendable {
	public let displayName: String
	public let vcard: String

	public init(displayName: String, vcard: String) {
		self.displayName = displayName
		self.vcard = vcard
	}
}

public struct ReceivedContactsContent: Equatable, Sendable {
	public let displayName: String?
	public let contacts: [ReceivedContactContent]

	public init(displayName: String?, contacts: [ReceivedContactContent]) {
		self.displayName = displayName
		self.contacts = contacts
	}
}
