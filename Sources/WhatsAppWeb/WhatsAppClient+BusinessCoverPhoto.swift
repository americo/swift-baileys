import CryptoKit
import Foundation

extension WhatsAppClient {
	public func updateBusinessCoverPhoto(_ photoData: Data, requestID: String? = nil) async throws -> Int {
		guard let mediaUploader else {
			throw WhatsAppClientError.missingMediaUploader
		}

		let upload = try await mediaUploader.upload(
			photoData,
			fileEncSha256Base64: Data(SHA256.hash(data: photoData)).base64EncodedString(),
			mediaType: .businessCoverPhoto
		)
		guard let fileID = upload.fileID, let metaHMAC = upload.metaHMAC, let timestamp = upload.timestamp else {
			throw WhatsAppClientError.missingBusinessCoverPhotoUploadResponse
		}

		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		_ = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"to": "@s.whatsapp.net",
				"type": "set",
				"xmlns": "w:biz"
			],
			content: .nodes([
				BinaryNode(
					tag: "business_profile",
					attrs: ["v": "3", "mutation_type": "delta"],
					content: .nodes([
						BinaryNode(
							tag: "cover_photo",
							attrs: [
								"id": String(fileID),
								"op": "update",
								"token": metaHMAC,
								"ts": String(timestamp)
							]
						)
					])
				)
			])
		))
		return fileID
	}

	public func updateCoverPhoto(_ photoData: Data, requestID: String? = nil) async throws -> Int {
		try await updateBusinessCoverPhoto(photoData, requestID: requestID)
	}
}
