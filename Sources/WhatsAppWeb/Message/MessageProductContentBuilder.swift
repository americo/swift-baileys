struct UploadedProductContent: Equatable, Sendable {
	let image: UploadedImageContent
	let product: OutgoingProductContent
}

extension MessageContentBuilder {
	static func product(_ content: UploadedProductContent) -> Proto_Message {
		var snapshot = Proto_Message.ProductMessage.ProductSnapshot()
		snapshot.productImage = productImage(content.image)
		if let productID = content.product.productID {
			snapshot.productID = productID
		}
		if let title = content.product.title {
			snapshot.title = title
		}
		if let description = content.product.description {
			snapshot.description_p = description
		}
		if let currencyCode = content.product.currencyCode {
			snapshot.currencyCode = currencyCode
		}
		if let priceAmount1000 = content.product.priceAmount1000 {
			snapshot.priceAmount1000 = priceAmount1000
		}
		if let retailerID = content.product.retailerID {
			snapshot.retailerID = retailerID
		}
		if let url = content.product.url {
			snapshot.url = url
		}
		if let productImageCount = content.product.productImageCount {
			snapshot.productImageCount = productImageCount
		}
		if let firstImageID = content.product.firstImageID {
			snapshot.firstImageID = firstImageID
		}
		if let salePriceAmount1000 = content.product.salePriceAmount1000 {
			snapshot.salePriceAmount1000 = salePriceAmount1000
		}
		if let signedURL = content.product.signedURL {
			snapshot.signedURL = signedURL
		}

		var productMessage = Proto_Message.ProductMessage()
		productMessage.product = snapshot
		if let businessOwnerJID = content.product.businessOwnerJID {
			productMessage.businessOwnerJid = businessOwnerJID
		}
		if let body = content.product.body {
			productMessage.body = body
		}
		if let footer = content.product.footer {
			productMessage.footer = footer
		}

		var message = Proto_Message()
		message.productMessage = productMessage
		return message
	}

	private static func productImage(_ content: UploadedImageContent) -> Proto_Message.ImageMessage {
		var image = Proto_Message.ImageMessage()
		image.url = content.url
		image.directPath = content.directPath
		image.mediaKey = content.mediaKey
		image.fileEncSha256 = content.fileEncSha256
		image.fileSha256 = content.fileSha256
		image.fileLength = content.fileLength
		image.mediaKeyTimestamp = content.mediaKeyTimestamp
		image.mimetype = content.mimetype
		if let caption = content.caption {
			image.caption = caption
		}
		if let jpegThumbnail = content.jpegThumbnail {
			image.jpegThumbnail = jpegThumbnail
		}
		return image
	}
}
